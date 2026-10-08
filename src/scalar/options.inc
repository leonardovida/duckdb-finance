//! Reads option inputs from one of three argument layouts:
//!   KIND:    (kind, spot, strike, ttm, rate, vol[, dividend_yield], extras...)  extras start at column 7
//!   NO_KIND: (spot, strike, ttm, rate, vol[, dividend_yield], extras...)        extras start at column 6
//!   SPEC:    (spec STRUCT, extras...)                                           extras start at column 1
//! Option specs must describe a European BSM option; other exercise styles or models raise an error rather
//! than being priced with the wrong model.
class OptionReader {
public:
	enum class Layout : uint8_t { KIND, NO_KIND, SPEC };

	static Layout DetectLayout(DataChunk &args) {
		auto type_id = args.data[0].GetType().id();
		return type_id == LogicalTypeId::STRUCT ? Layout::SPEC
		       : type_id == LogicalTypeId::VARCHAR ? Layout::KIND
		                                            : Layout::NO_KIND;
	}

	OptionReader(DataChunk &args, const string &purpose)
	    : layout(DetectLayout(args)),
	      kind(args, layout == Layout::KIND ? 0 : DConstants::INVALID_INDEX, ParseCallKind, true),
	      purpose_name(purpose) {
		if (layout == Layout::SPEC) {
			auto &children = StructVector::GetEntries(args.data[0]);
			if (children.size() != spec_children.size()) {
				throw InvalidInputException("option spec must come from fin_option_spec or fin_option_spec_dates");
			}
			for (idx_t i = 0; i < children.size(); i++) {
				FinanceToUnifiedFormat(FINANCE_STRUCT_CHILD(children[i]), args.size(), spec_children[i]);
			}
		}
		column_count = args.ColumnCount();
	}

	idx_t ExtraOffset() const {
		return layout == Layout::SPEC ? 1 : layout == Layout::KIND ? 7 : 6;
	}

	//! False when a spec field is NULL (the row result is NULL).
	bool Read(const PreparedInputs &input, idx_t row, OptionRow &out) {
		if (layout != Layout::SPEC) {
			idx_t base = layout == Layout::KIND ? 1 : 0;
			out.call = layout == Layout::KIND ? kind.Get(input, row) : true;
			out.spot = input.GetDouble(base, row);
			out.strike = input.GetDouble(base + 1, row);
			out.ttm = input.GetDouble(base + 2, row);
			out.rate = input.GetDouble(base + 3, row);
			out.vol = input.GetDouble(base + 4, row);
			out.dividend_yield = column_count > base + 5 ? input.GetDouble(base + 5, row) : 0.0;
			return true;
		}
		for (auto &child : spec_children) {
			if (!child.validity.RowIsValid(child.sel->get_index(row))) {
				return false;
			}
		}
		out.call = SpecString(0, row, call_cache, [](const string &s) { return ParseCallKind(s) ? 1 : 0; }) == 1;
		SpecString(7, row, exercise_cache, [&](const string &s) {
			if (ParseExerciseStyleEnum(s) != ExerciseStyle::EUROPEAN) {
				throw InvalidInputException("option spec exercise '%s' is not supported by %s; BSM prices European "
				                            "exercise only (use fin_binomial_price for American options)",
				                            s, purpose_name);
			}
			return 1;
		});
		SpecString(8, row, model_cache, [&](const string &s) {
			auto normalized = NormalizeCompact(s);
			if (normalized != "bsm" && normalized != "blackscholes" && normalized != "blackscholesmerton") {
				throw InvalidInputException("option spec model '%s' is not supported by %s; use the matching "
				                            "fin_black76_*, fin_bachelier_* or fin_binomial_price function",
				                            s, purpose_name);
			}
			return 1;
		});
		out.spot = SpecDouble(1, row);
		out.strike = SpecDouble(2, row);
		out.ttm = SpecDouble(3, row);
		out.rate = SpecDouble(4, row);
		out.vol = SpecDouble(5, row);
		out.dividend_yield = SpecDouble(6, row);
		return true;
	}

private:
	double SpecDouble(idx_t i, idx_t row) const {
		auto &child = spec_children[i];
		return UnifiedVectorFormat::GetData<double>(child)[child.sel->get_index(row)];
	}

	template <class PARSE>
	int SpecString(idx_t i, idx_t row, ParsedStringCache<int> &cache, PARSE parse) {
		auto &child = spec_children[i];
		auto str = UnifiedVectorFormat::GetData<string_t>(child)[child.sel->get_index(row)];
		return cache.Get(str, parse);
	}

public:
	Layout layout;

private:
	ConfigArg<bool> kind;
	string purpose_name;
	idx_t column_count = 0;
	array<UnifiedVectorFormat, 9> spec_children;
	ParsedStringCache<int> call_cache, exercise_cache, model_cache;
};

//! Run `func(OptionRow, input, row, extra_offset)` for every row producing a DOUBLE.
template <class FUNC>
static void ExecuteOption(DataChunk &args, ExpressionState &state, Vector &result, FUNC func) {
	auto &bound = state.expr.Cast<BoundFunctionExpression>();
	OptionReader reader(args, bound.function.name);
	auto extra = reader.ExtraOffset();
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		OptionRow o;
		if (!reader.Read(input, row, o)) {
			return FIN_NAN;
		}
		return func(o, input, row, extra);
	});
}

static void OptionPayoffFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		return OptionPayoff(kind.Get(input, row), input.GetDouble(1, row), input.GetDouble(2, row));
	});
}

static void ForwardPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double dividend_yield = args.ColumnCount() >= 4 ? input.GetDouble(3, row) : 0.0;
		return ForwardPrice(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), dividend_yield);
	});
}

static void PutCallParityFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		double call = input.GetDouble(0, row);
		double put = input.GetDouble(1, row);
		double spot = input.GetDouble(2, row);
		double strike = input.GetDouble(3, row);
		double ttm = input.GetDouble(4, row);
		double rate = input.GetDouble(5, row);
		return call - put - spot * std::exp(-q * ttm) + strike * std::exp(-rate * ttm);
	});
}

static void BSMD1Function(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result, [](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) {
		BSMKernel k;
		return MakeBSMKernel(o, k) ? k.d1 : FIN_NAN;
	});
}

static void BSMD2Function(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result, [](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) {
		BSMKernel k;
		return MakeBSMKernel(o, k) ? k.d2 : FIN_NAN;
	});
}

static void BSMPriceFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result,
	              [](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) { return BSMPrice(o); });
}

static void BSMDeltaFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result, [](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) {
		BSMKernel k;
		return MakeBSMKernel(o, k) ? BSMDeltaFromKernel(o.call, k) : FIN_NAN;
	});
}

static void BSMGammaFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result, [](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) {
		BSMKernel k;
		return MakeBSMKernel(o, k) ? BSMGammaFromKernel(k) : FIN_NAN;
	});
}

static void BSMVegaFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	auto extra = args.data[0].GetType().id() == LogicalTypeId::STRUCT ? idx_t(1) : idx_t(7);
	ConfigArg<double> unit(args, extra, ParseVegaRhoScale, 1.0);
	ExecuteOption(args, state, result, [&](const OptionRow &o, const PreparedInputs &input, idx_t row, idx_t) {
		BSMKernel k;
		return MakeBSMKernel(o, k) ? BSMVegaFromKernel(k) * unit.Get(input, row) : FIN_NAN;
	});
}

static void BSMThetaFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	auto extra = args.data[0].GetType().id() == LogicalTypeId::STRUCT ? idx_t(1) : idx_t(7);
	ConfigArg<double> unit(args, extra, ParseThetaScale, 1.0);
	ExecuteOption(args, state, result, [&](const OptionRow &o, const PreparedInputs &input, idx_t row, idx_t) {
		BSMKernel k;
		return MakeBSMKernel(o, k) ? BSMThetaFromKernel(o.call, k) * unit.Get(input, row) : FIN_NAN;
	});
}

static void BSMRhoFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	auto extra = args.data[0].GetType().id() == LogicalTypeId::STRUCT ? idx_t(1) : idx_t(7);
	ConfigArg<double> unit(args, extra, ParseVegaRhoScale, 1.0);
	ExecuteOption(args, state, result, [&](const OptionRow &o, const PreparedInputs &input, idx_t row, idx_t) {
		BSMKernel k;
		return MakeBSMKernel(o, k) ? BSMRhoFromKernel(o.call, k) * unit.Get(input, row) : FIN_NAN;
	});
}

static LogicalType GreeksType() {
	return FinanceStructType({{"delta", LogicalTypeId::DOUBLE},
	                          {"gamma", LogicalTypeId::DOUBLE},
	                          {"vega", LogicalTypeId::DOUBLE},
	                          {"theta", LogicalTypeId::DOUBLE},
	                          {"rho", LogicalTypeId::DOUBLE}});
}

static LogicalType BSMAllType() {
	return FinanceStructType({{"price", LogicalTypeId::DOUBLE},
	                          {"delta", LogicalTypeId::DOUBLE},
	                          {"gamma", LogicalTypeId::DOUBLE},
	                          {"vega", LogicalTypeId::DOUBLE},
	                          {"theta", LogicalTypeId::DOUBLE},
	                          {"rho", LogicalTypeId::DOUBLE},
	                          {"d1", LogicalTypeId::DOUBLE},
	                          {"d2", LogicalTypeId::DOUBLE},
	                          {"intrinsic", LogicalTypeId::DOUBLE},
	                          {"time_value", LogicalTypeId::DOUBLE}});
}

static LogicalType OptionSpecType() {
	return FinanceStructType({{"kind", LogicalTypeId::VARCHAR},
	                          {"spot", LogicalTypeId::DOUBLE},
	                          {"strike", LogicalTypeId::DOUBLE},
	                          {"ttm", LogicalTypeId::DOUBLE},
	                          {"rate", LogicalTypeId::DOUBLE},
	                          {"vol", LogicalTypeId::DOUBLE},
	                          {"dividend_yield", LogicalTypeId::DOUBLE},
	                          {"exercise", LogicalTypeId::VARCHAR},
	                          {"model", LogicalTypeId::VARCHAR}});
}

//! Writes N DOUBLE struct fields per row; a row is NULL when any field is non-finite.
template <idx_t N, class FUNC>
static void ExecuteStructRows(DataChunk &args, Vector &result, FUNC func) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	array<double *, N> out;
	for (idx_t i = 0; i < N; i++) {
		out[i] = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[i]));
	}
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	array<double, N> values;
	for (idx_t row = 0; row < row_count; row++) {
		bool ok = !input.HasNull(row) && func(input, row, values);
		for (idx_t i = 0; ok && i < N; i++) {
			ok = IsFinite(values[i]);
		}
		if (!ok) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		for (idx_t i = 0; i < N; i++) {
			out[i][row] = values[i];
		}
	}
}

static void BSMGreeksFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	OptionReader reader(args, "fin_bsm_greeks");
	ExecuteStructRows<5>(args, result, [&](const PreparedInputs &input, idx_t row, array<double, 5> &v) {
		OptionRow o;
		BSMKernel k;
		if (!reader.Read(input, row, o) || !MakeBSMKernel(o, k)) {
			return false;
		}
		v = {BSMDeltaFromKernel(o.call, k), BSMGammaFromKernel(k), BSMVegaFromKernel(k), BSMThetaFromKernel(o.call, k),
		     BSMRhoFromKernel(o.call, k)};
		return true;
	});
}

static void BSMAllFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	OptionReader reader(args, "fin_bsm_all");
	ExecuteStructRows<10>(args, result, [&](const PreparedInputs &input, idx_t row, array<double, 10> &v) {
		OptionRow o;
		BSMKernel k;
		if (!reader.Read(input, row, o) || !MakeBSMKernel(o, k)) {
			return false;
		}
		double price = BSMPriceFromKernel(o.call, k);
		double intrinsic = OptionPayoff(o.call, k.spot, k.strike);
		v = {price,
		     BSMDeltaFromKernel(o.call, k),
		     BSMGammaFromKernel(k),
		     BSMVegaFromKernel(k),
		     BSMThetaFromKernel(o.call, k),
		     BSMRhoFromKernel(o.call, k),
		     k.d1,
		     k.d2,
		     intrinsic,
		     price - intrinsic};
		return true;
	});
}

//! (kind, price, spot, strike, ttm, rate[, q[, guess[, tolerance[, max_iter]]]]) or (spec, price).
static void BSMImpliedVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	if (args.data[0].GetType().id() == LogicalTypeId::STRUCT) {
		OptionReader reader(args, "fin_bsm_implied_vol");
		ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
			OptionRow o;
			if (!reader.Read(input, row, o)) {
				return FIN_NAN;
			}
			double guess = IsFinite(o.vol) && o.vol > 0.0 ? o.vol : 0.2;
			return BSMImpliedVol(o, input.GetDouble(1, row), guess, 1e-8, 100);
		});
		return;
	}
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		OptionRow o;
		o.call = kind.Get(input, row);
		o.spot = input.GetDouble(2, row);
		o.strike = input.GetDouble(3, row);
		o.ttm = input.GetDouble(4, row);
		o.rate = input.GetDouble(5, row);
		o.vol = 0.0;
		o.dividend_yield = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		double guess = args.ColumnCount() >= 8 ? input.GetDouble(7, row) : 0.2;
		double tol = args.ColumnCount() >= 9 ? input.GetDouble(8, row) : 1e-8;
		int64_t max_iter = args.ColumnCount() >= 10 ? input.GetInteger(9, row) : 100;
		return BSMImpliedVol(o, input.GetDouble(1, row), guess, tol, max_iter);
	});
}

static void BSMProbITMFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result,
	              [](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) { return BSMProbITM(o); });
}

static void BSMProbTouchFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result,
	              [](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) { return BSMProbTouch(o); });
}

static void BSMElasticityFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result, [](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) {
		return BSMHigherGreek(o, HigherGreek::ELASTICITY);
	});
}

static scalar_function_t BSMHigherGreekScalar(HigherGreek greek) {
	return [greek](DataChunk &args, ExpressionState &state, Vector &result) {
		ExecuteOption(args, state, result, [greek](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) {
			return BSMHigherGreek(o, greek);
		});
	};
}

static void BSMPriceDatesFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ConfigArg<DayCount> day_count(args, 8, ParseDayCountNoPeriod, DayCount::ACT_365F);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		OptionRow o;
		o.call = kind.Get(input, row);
		o.spot = input.GetDouble(1, row);
		o.strike = input.GetDouble(2, row);
		o.ttm = YearFrac(input.GetDate(3, row), input.GetDate(4, row), day_count.Get(input, row));
		o.rate = input.GetDouble(5, row);
		o.vol = input.GetDouble(6, row);
		o.dividend_yield = args.ColumnCount() >= 8 ? input.GetDouble(7, row) : 0.0;
		return BSMPrice(o);
	});
}

static void Black76GreeksFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ExecuteStructRows<5>(args, result, [&](const PreparedInputs &input, idx_t row, array<double, 5> &v) {
		bool call = kind.Get(input, row);
		double forward = input.GetDouble(1, row);
		double strike = input.GetDouble(2, row);
		double ttm = input.GetDouble(3, row);
		double rate = input.GetDouble(4, row);
		double vol = input.GetDouble(5, row);
		if (!(ttm > 0.0) || !(vol > 0.0) || !(forward > 0.0) || !(strike > 0.0) || !IsFinite(rate) ||
		    !IsFinite(ttm) || !IsFinite(vol)) {
			return false;
		}
		double df = std::exp(-rate * ttm);
		double st = vol * std::sqrt(ttm);
		double d1 = (std::log(forward / strike) + 0.5 * vol * vol * ttm) / st;
		double price = Black76Price(call, forward, strike, ttm, rate, vol);
		v = {call ? df * NormCDF(d1) : -df * NormCDF(-d1), df * NormPDF(d1) / (forward * st),
		     df * forward * NormPDF(d1) * std::sqrt(ttm),
		     -forward * df * NormPDF(d1) * vol / (2.0 * std::sqrt(ttm)) + rate * price, -ttm * price};
		return true;
	});
}

static void Black76ImpliedVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool call = kind.Get(input, row);
		double price = input.GetDouble(1, row);
		double forward = input.GetDouble(2, row);
		double strike = input.GetDouble(3, row);
		double ttm = input.GetDouble(4, row);
		double rate = input.GetDouble(5, row);
		double guess = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.2;
		double tol = args.ColumnCount() >= 8 ? input.GetDouble(7, row) : 1e-8;
		double df = std::exp(-rate * ttm);
		double upper_bound = (call ? forward : strike) * df;
		if (!IsFinite(forward) || !IsFinite(strike) || !IsFinite(ttm) || !IsFinite(rate) || !(forward > 0.0) ||
		    !(strike > 0.0) || !(ttm > 0.0) || !IsFinite(upper_bound) || !(price < upper_bound)) {
			return FIN_NAN;
		}
		double root_time = std::sqrt(ttm);
		double log_moneyness = std::log(forward / strike);
		return ImpliedVolSolve(
		    [&](double vol) {
			    if (vol == 0.0) {
				    return std::make_pair(df * OptionPayoff(call, forward, strike), 0.0);
			    }
			    double st = vol * root_time;
			    double d1 = log_moneyness / st + 0.5 * st;
			    double d2 = d1 - st;
			    double value = call ? df * (forward * NormCDF(d1) - strike * NormCDF(d2))
			                        : df * (strike * NormCDF(-d2) - forward * NormCDF(-d1));
			    return std::make_pair(value, df * forward * root_time * NormPDF(d1));
		    },
		    price, guess, tol, 100);
	});
}

static void BachelierGreeksFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ExecuteStructRows<5>(args, result, [&](const PreparedInputs &input, idx_t row, array<double, 5> &v) {
		bool call = kind.Get(input, row);
		double forward = input.GetDouble(1, row);
		double strike = input.GetDouble(2, row);
		double ttm = input.GetDouble(3, row);
		double rate = input.GetDouble(4, row);
		double normal_vol = input.GetDouble(5, row);
		if (!(ttm > 0.0) || !(normal_vol > 0.0) || !IsFinite(forward) || !IsFinite(strike) || !IsFinite(rate) ||
		    !IsFinite(ttm) || !IsFinite(normal_vol)) {
			return false;
		}
		double df = std::exp(-rate * ttm);
		double stddev = normal_vol * std::sqrt(ttm);
		double d = (forward - strike) / stddev;
		double price = BachelierPrice(call, forward, strike, ttm, rate, normal_vol);
		v = {call ? df * NormCDF(d) : -df * NormCDF(-d), df * NormPDF(d) / stddev, df * std::sqrt(ttm) * NormPDF(d),
		     -0.5 * df * normal_vol * NormPDF(d) / std::sqrt(ttm) + rate * price, -ttm * price};
		return true;
	});
}

static void BachelierImpliedVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool call = kind.Get(input, row);
		double price = input.GetDouble(1, row);
		double forward = input.GetDouble(2, row);
		double strike = input.GetDouble(3, row);
		double ttm = input.GetDouble(4, row);
		double rate = input.GetDouble(5, row);
		double tol = args.ColumnCount() >= 8 ? input.GetDouble(7, row) : 1e-8;
		if (!IsFinite(forward) || !IsFinite(strike) || !IsFinite(ttm) || !IsFinite(rate) || !(ttm > 0.0)) {
			return FIN_NAN;
		}
		double df = std::exp(-rate * ttm);
		double root_time = std::sqrt(ttm);
		double difference = forward - strike;
		double guess = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : price / (df * root_time * INV_SQRT_2PI);
		if (args.ColumnCount() < 7 && (!IsFinite(guess) || guess < 0.0)) {
			guess = 5.0;
		}
		return ImpliedVolSolve(
		    [&](double vol) {
			    if (vol == 0.0) {
				    return std::make_pair(df * OptionPayoff(call, forward, strike), 0.0);
			    }
			    double st = vol * root_time;
			    double d = difference / st;
			    double pdf = NormPDF(d);
			    double value = df * (call ? difference * NormCDF(d) + st * pdf : -difference * NormCDF(-d) + st * pdf);
			    return std::make_pair(value, df * root_time * pdf);
		    },
		    price, guess, tol, 100);
	});
}

static double BarrierSafeProduct(double power, double probability) {
	return probability == 0.0 ? 0.0 : power * probability;
}

//! Reiner-Rubinstein continuously monitored European single-barrier option.
static double BarrierPrice(bool call, BarrierKind barrier_kind, double spot, double strike, double barrier,
                           double rebate, double ttm, double rate, double vol, double dividend_yield) {
	if (!IsFinite(spot) || !IsFinite(strike) || !IsFinite(barrier) || !IsFinite(rebate) || !IsFinite(ttm) ||
	    !IsFinite(rate) || !IsFinite(vol) || !IsFinite(dividend_yield) || !(spot > 0.0) || !(strike > 0.0) ||
	    !(barrier > 0.0) || rebate < 0.0 || ttm < 0.0 || vol < 0.0) {
		return FIN_NAN;
	}
	const bool down = barrier_kind == BarrierKind::DOWN_IN || barrier_kind == BarrierKind::DOWN_OUT;
	const bool knock_in = barrier_kind == BarrierKind::DOWN_IN || barrier_kind == BarrierKind::UP_IN;
	const bool touched = (down && spot <= barrier) || (!down && spot >= barrier);
	OptionRow vanilla_row {call, spot, strike, ttm, rate, vol, dividend_yield};
	const double vanilla = BSMPrice(vanilla_row);
	if (touched) {
		return knock_in ? vanilla : rebate;
	}
	if (ttm == 0.0) {
		return knock_in ? rebate : vanilla;
	}
	if (vol == 0.0) {
		return FIN_NAN;
	}

	const double phi = call ? 1.0 : -1.0;
	const double sigma_sqrt_t = vol * std::sqrt(ttm);
	const double mu = (rate - dividend_yield) / (vol * vol) - 0.5;
	const double mu_sigma = (1.0 + mu) * sigma_sqrt_t;
	const double df_r = std::exp(-rate * ttm);
	const double df_q = std::exp(-dividend_yield * ttm);
	const double hs = barrier / spot;
	const double power_mu = std::pow(hs, 2.0 * mu);
	const double power_mu_plus = power_mu * hs * hs;

	auto a = [&](double option_phi) {
		double x1 = std::log(spot / strike) / sigma_sqrt_t + mu_sigma;
		return option_phi *
		       (spot * df_q * NormCDF(option_phi * x1) - strike * df_r * NormCDF(option_phi * (x1 - sigma_sqrt_t)));
	};
	auto b = [&](double option_phi) {
		double x2 = std::log(spot / barrier) / sigma_sqrt_t + mu_sigma;
		return option_phi *
		       (spot * df_q * NormCDF(option_phi * x2) - strike * df_r * NormCDF(option_phi * (x2 - sigma_sqrt_t)));
	};
	auto c = [&](double direction_eta, double option_phi) {
		double y1 = std::log(barrier * hs / strike) / sigma_sqrt_t + mu_sigma;
		double n1 = NormCDF(direction_eta * y1);
		double n2 = NormCDF(direction_eta * (y1 - sigma_sqrt_t));
		return option_phi *
		       (spot * df_q * BarrierSafeProduct(power_mu_plus, n1) - strike * df_r * BarrierSafeProduct(power_mu, n2));
	};
	auto d = [&](double direction_eta, double option_phi) {
		double y2 = std::log(barrier / spot) / sigma_sqrt_t + mu_sigma;
		double n1 = NormCDF(direction_eta * y2);
		double n2 = NormCDF(direction_eta * (y2 - sigma_sqrt_t));
		return option_phi *
		       (spot * df_q * BarrierSafeProduct(power_mu_plus, n1) - strike * df_r * BarrierSafeProduct(power_mu, n2));
	};
	auto e = [&](double direction_eta) {
		if (rebate == 0.0) {
			return 0.0;
		}
		double x2 = std::log(spot / barrier) / sigma_sqrt_t + mu_sigma;
		double y2 = std::log(barrier / spot) / sigma_sqrt_t + mu_sigma;
		double n1 = NormCDF(direction_eta * (x2 - sigma_sqrt_t));
		double n2 = NormCDF(direction_eta * (y2 - sigma_sqrt_t));
		return rebate * df_r * (n1 - BarrierSafeProduct(power_mu, n2));
	};
	auto f = [&](double direction_eta) {
		if (rebate == 0.0) {
			return 0.0;
		}
		double lambda_sq = mu * mu + 2.0 * rate / (vol * vol);
		if (lambda_sq < 0.0) {
			return FIN_NAN;
		}
		double lambda = std::sqrt(lambda_sq);
		double z = std::log(barrier / spot) / sigma_sqrt_t + lambda * sigma_sqrt_t;
		double n1 = NormCDF(direction_eta * z);
		double n2 = NormCDF(direction_eta * (z - 2.0 * lambda * sigma_sqrt_t));
		return rebate *
		       (BarrierSafeProduct(std::pow(hs, mu + lambda), n1) + BarrierSafeProduct(std::pow(hs, mu - lambda), n2));
	};

	double price;
	if (call && barrier_kind == BarrierKind::DOWN_IN) {
		price = strike >= barrier ? c(1.0, phi) + e(1.0) : a(phi) - b(phi) + d(1.0, phi) + e(1.0);
	} else if (call && barrier_kind == BarrierKind::UP_IN) {
		price = strike >= barrier ? a(phi) + e(-1.0) : b(phi) - c(-1.0, phi) + d(-1.0, phi) + e(-1.0);
	} else if (call && barrier_kind == BarrierKind::DOWN_OUT) {
		price = strike >= barrier ? a(phi) - c(1.0, phi) + f(1.0) : b(phi) - d(1.0, phi) + f(1.0);
	} else if (call) {
		price = strike >= barrier ? f(-1.0) : a(phi) - b(phi) + c(-1.0, phi) - d(-1.0, phi) + f(-1.0);
	} else if (barrier_kind == BarrierKind::DOWN_IN) {
		price = strike >= barrier ? b(phi) - c(1.0, phi) + d(1.0, phi) + e(1.0) : a(phi) + e(1.0);
	} else if (barrier_kind == BarrierKind::UP_IN) {
		price = strike >= barrier ? a(phi) - b(phi) + d(-1.0, phi) + e(-1.0) : c(-1.0, phi) + e(-1.0);
	} else if (barrier_kind == BarrierKind::DOWN_OUT) {
		price = strike >= barrier ? a(phi) - b(phi) + c(1.0, phi) - d(1.0, phi) + f(1.0) : f(1.0);
	} else {
		price = strike >= barrier ? b(phi) - d(-1.0, phi) + f(-1.0) : a(phi) - c(-1.0, phi) + f(-1.0);
	}
	if (!IsFinite(price) || price < -1e-10) {
		return FIN_NAN;
	}
	return std::max(0.0, price);
}

static void BarrierPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ConfigArg<BarrierKind> barrier_kind(args, 1, ParseBarrierKind, BarrierKind::DOWN_OUT);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		idx_t offset = args.ColumnCount() >= 9 ? 1 : 0;
		double rebate = offset ? input.GetDouble(5, row) : 0.0;
		double q = args.ColumnCount() >= 10 ? input.GetDouble(9, row) : 0.0;
		return BarrierPrice(kind.Get(input, row), barrier_kind.Get(input, row), input.GetDouble(2, row),
		                    input.GetDouble(3, row), input.GetDouble(4, row), rebate, input.GetDouble(5 + offset, row),
		                    input.GetDouble(6 + offset, row), input.GetDouble(7 + offset, row), q);
	});
}

static void Black76PriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		return Black76Price(kind.Get(input, row), input.GetDouble(1, row), input.GetDouble(2, row),
		                    input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row));
	});
}

static void BachelierPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		return BachelierPrice(kind.Get(input, row), input.GetDouble(1, row), input.GetDouble(2, row),
		                      input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row));
	});
}

static void BinomialPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<bool> kind(args, 0, ParseCallKind, true);
	ConfigArg<ExerciseStyle> exercise(args, 8, ParseExerciseStyleEnum, ExerciseStyle::EUROPEAN);
	ConfigArg<BinomialTree> tree(args, 9, ParseBinomialTree, BinomialTree::CRR);
	vector<double> buffer;
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		OptionRow o;
		o.call = kind.Get(input, row);
		o.spot = input.GetDouble(1, row);
		o.strike = input.GetDouble(2, row);
		o.ttm = input.GetDouble(3, row);
		o.rate = input.GetDouble(4, row);
		o.vol = input.GetDouble(5, row);
		o.dividend_yield = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		int64_t steps = args.ColumnCount() >= 8 ? input.GetInteger(7, row) : 200;
		if (steps <= 0 || steps > MAX_BINOMIAL_STEPS) {
			throw InvalidInputException("steps must be between 1 and %lld, got %lld", (long long)MAX_BINOMIAL_STEPS,
			                            (long long)steps);
		}
		return BinomialPrice(o, steps, exercise.Get(input, row), tree.Get(input, row), buffer);
	});
}

static void DigitalPriceFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result, [&](const OptionRow &o, const PreparedInputs &input, idx_t row, idx_t extra) {
		double payout = args.ColumnCount() > extra ? input.GetDouble(extra, row) : 1.0;
		return DigitalPrice(o, payout);
	});
}

static void AssetOrNothingPriceFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result,
	              [](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) { return AssetOrNothingPrice(o); });
}

static void AsianGeometricPriceFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ExecuteOption(args, state, result,
	              [](const OptionRow &o, const PreparedInputs &, idx_t, idx_t) { return AsianGeometricPrice(o); });
}

static void SABRVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double shift = args.ColumnCount() >= 8 ? input.GetDouble(7, row) : 0.0;
		return SABRVol(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), input.GetDouble(3, row),
		               input.GetDouble(4, row), input.GetDouble(5, row), input.GetDouble(6, row), shift);
	});
}

static void SviTotalVarianceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [](const PreparedInputs &input, idx_t row) {
		return SviTotalVariance(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row),
		                        input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row));
	});
}

static void SviVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [](const PreparedInputs &input, idx_t row) {
		double total_var = SviTotalVariance(input.GetDouble(0, row), input.GetDouble(2, row), input.GetDouble(3, row),
		                                    input.GetDouble(4, row), input.GetDouble(5, row), input.GetDouble(6, row));
		double ttm = input.GetDouble(1, row);
		if (!(ttm > 0.0) || !(total_var >= 0.0)) {
			return FIN_NAN;
		}
		return std::sqrt(total_var / ttm);
	});
}
