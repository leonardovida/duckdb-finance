static void OptionPayoffFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [](const PreparedInputs &input, idx_t row) {
		return OptionPayoff(IsCallKind(input.GetString(0, row)), input.GetDouble(1, row), input.GetDouble(2, row));
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

static void BSMD1Function(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 6 ? input.GetDouble(5, row) : 0.0;
		return BSMD1(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), input.GetDouble(3, row),
		             input.GetDouble(4, row), q);
	});
}

static void BSMD2Function(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 6 ? input.GetDouble(5, row) : 0.0;
		return BSMD2(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), input.GetDouble(3, row),
		             input.GetDouble(4, row), q);
	});
}

static void BSMPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		return BSMPrice(IsCallKind(input.GetString(0, row)), input.GetDouble(1, row), input.GetDouble(2, row),
		                input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row), q);
	});
}

static void BSMDeltaFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		return BSMDelta(IsCallKind(input.GetString(0, row)), input.GetDouble(1, row), input.GetDouble(2, row),
		                input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row), q);
	});
}

static void BSMGammaFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 6 ? input.GetDouble(5, row) : 0.0;
		return BSMGamma(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), input.GetDouble(3, row),
		                input.GetDouble(4, row), q);
	});
}

static void BSMVegaFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		double value = BSMVega(input.GetDouble(1, row), input.GetDouble(2, row), input.GetDouble(3, row),
		                       input.GetDouble(4, row), input.GetDouble(5, row), q);
		if (args.ColumnCount() >= 8 && Normalize(input.GetString(7, row)) == "market") {
			value /= 100.0;
		}
		return value;
	});
}

static void BSMThetaFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		double value = BSMTheta(IsCallKind(input.GetString(0, row)), input.GetDouble(1, row), input.GetDouble(2, row),
		                        input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row), q);
		if (args.ColumnCount() >= 8 && Normalize(input.GetString(7, row)) == "day") {
			value /= 365.0;
		}
		return value;
	});
}

static void BSMRhoFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		double value = BSMRho(IsCallKind(input.GetString(0, row)), input.GetDouble(1, row), input.GetDouble(2, row),
		                      input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row), q);
		if (args.ColumnCount() >= 8 && Normalize(input.GetString(7, row)) == "market") {
			value /= 10000.0;
		}
		return value;
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

struct OptionSpecData {
	UnifiedVectorFormat spec;
	array<UnifiedVectorFormat, 9> children;
};

struct OptionSpecRow {
	bool call;
	double spot;
	double strike;
	double ttm;
	double rate;
	double vol;
	double dividend_yield;
};

struct GreeksOutput {
	double *delta;
	double *gamma;
	double *vega;
	double *theta;
	double *rho;
};

static GreeksOutput GetGreeksOutput(Vector &result) {
	auto &children = StructVector::GetEntries(result);
	return {FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[0])),
	        FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[1])),
	        FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[2])),
	        FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[3])),
	        FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[4]))};
}

static void WriteBSMGreeks(const GreeksOutput &out, idx_t row, bool call, const BSMKernel &k) {
	out.delta[row] = BSMDeltaFromKernel(call, k);
	out.gamma[row] = BSMGammaFromKernel(k);
	out.vega[row] = BSMVegaFromKernel(k);
	out.theta[row] = BSMThetaFromKernel(call, k);
	out.rho[row] = BSMRhoFromKernel(call, k);
}

struct BSMAllOutput {
	array<double *, 10> values;
};

static BSMAllOutput GetBSMAllOutput(Vector &result) {
	BSMAllOutput output;
	auto &children = StructVector::GetEntries(result);
	for (idx_t i = 0; i < output.values.size(); i++) {
		output.values[i] = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[i]));
	}
	return output;
}

static void WriteBSMAll(const BSMAllOutput &out, idx_t row, bool call, const BSMKernel &k) {
	double price = BSMPriceFromKernel(call, k);
	double intrinsic = OptionPayoff(call, k.spot, k.strike);
	out.values[0][row] = price;
	out.values[1][row] = BSMDeltaFromKernel(call, k);
	out.values[2][row] = BSMGammaFromKernel(k);
	out.values[3][row] = BSMVegaFromKernel(k);
	out.values[4][row] = BSMThetaFromKernel(call, k);
	out.values[5][row] = BSMRhoFromKernel(call, k);
	out.values[6][row] = k.d1;
	out.values[7][row] = k.d2;
	out.values[8][row] = intrinsic;
	out.values[9][row] = price - intrinsic;
}

static OptionSpecData PrepareOptionSpecData(DataChunk &args) {
	OptionSpecData data;
	FinanceToUnifiedFormat(args.data[0], args.size(), data.spec);
	auto &children = StructVector::GetEntries(args.data[0]);
	if (children.size() != data.children.size()) {
		throw InvalidInputException("Option spec must come from fin_option_spec or fin_option_spec_dates");
	}
	for (idx_t i = 0; i < children.size(); i++) {
		FinanceToUnifiedFormat(FINANCE_STRUCT_CHILD(children[i]), args.size(), data.children[i]);
	}
	return data;
}

static bool ReadOptionSpecRow(OptionSpecData &data, idx_t row, OptionSpecRow &out) {
	auto spec_idx = data.spec.sel->get_index(row);
	if (!data.spec.validity.RowIsValid(spec_idx)) {
		return false;
	}
	for (auto &child : data.children) {
		auto child_idx = child.sel->get_index(row);
		if (!child.validity.RowIsValid(child_idx)) {
			return false;
		}
	}
	auto kind = UnifiedVectorFormat::GetData<string_t>(data.children[0])[data.children[0].sel->get_index(row)];
	out.call = IsCallKind(kind.GetString());
	out.spot = UnifiedVectorFormat::GetData<double>(data.children[1])[data.children[1].sel->get_index(row)];
	out.strike = UnifiedVectorFormat::GetData<double>(data.children[2])[data.children[2].sel->get_index(row)];
	out.ttm = UnifiedVectorFormat::GetData<double>(data.children[3])[data.children[3].sel->get_index(row)];
	out.rate = UnifiedVectorFormat::GetData<double>(data.children[4])[data.children[4].sel->get_index(row)];
	out.vol = UnifiedVectorFormat::GetData<double>(data.children[5])[data.children[5].sel->get_index(row)];
	out.dividend_yield = UnifiedVectorFormat::GetData<double>(data.children[6])[data.children[6].sel->get_index(row)];
	return true;
}

template <class FUNC>
static void ExecuteOptionSpecDouble(DataChunk &args, Vector &result, FUNC func) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	auto spec_data = PrepareOptionSpecData(args);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		OptionSpecRow spec;
		if (!ReadOptionSpecRow(spec_data, row, spec)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		try {
			output[row] = func(spec);
			if (!std::isfinite(output[row])) {
				SetResultNull(result, row, args.size(), constant);
			}
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

static void BSMPriceSpecFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteOptionSpecDouble(args, result, [](const OptionSpecRow &spec) {
		return BSMPrice(spec.call, spec.spot, spec.strike, spec.ttm, spec.rate, spec.vol, spec.dividend_yield);
	});
}

static void BSMDeltaSpecFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteOptionSpecDouble(args, result, [](const OptionSpecRow &spec) {
		return BSMDelta(spec.call, spec.spot, spec.strike, spec.ttm, spec.rate, spec.vol, spec.dividend_yield);
	});
}

static void BSMGammaSpecFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteOptionSpecDouble(args, result, [](const OptionSpecRow &spec) {
		return BSMGamma(spec.spot, spec.strike, spec.ttm, spec.rate, spec.vol, spec.dividend_yield);
	});
}

static void BSMVegaSpecFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteOptionSpecDouble(args, result, [](const OptionSpecRow &spec) {
		return BSMVega(spec.spot, spec.strike, spec.ttm, spec.rate, spec.vol, spec.dividend_yield);
	});
}

static void BSMGreeksFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	PreparedInputs input(args);
	auto out = GetGreeksOutput(result);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		try {
			double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
			bool call = IsCallKind(input.GetString(0, row));
			double spot = input.GetDouble(1, row);
			double strike = input.GetDouble(2, row);
			double ttm = input.GetDouble(3, row);
			double rate = input.GetDouble(4, row);
			double vol = input.GetDouble(5, row);
			auto k = MakeBSMKernel(spot, strike, ttm, rate, vol, q);
			WriteBSMGreeks(out, row, call, k);
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

static void BSMGreeksSpecFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto spec_data = PrepareOptionSpecData(args);
	auto out = GetGreeksOutput(result);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		OptionSpecRow spec;
		if (!ReadOptionSpecRow(spec_data, row, spec)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		try {
			auto k = MakeBSMKernel(spec.spot, spec.strike, spec.ttm, spec.rate, spec.vol, spec.dividend_yield);
			WriteBSMGreeks(out, row, spec.call, k);
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

static void BSMAllFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	PreparedInputs input(args);
	auto out = GetBSMAllOutput(result);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		try {
			double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
			bool call = IsCallKind(input.GetString(0, row));
			double spot = input.GetDouble(1, row);
			double strike = input.GetDouble(2, row);
			double ttm = input.GetDouble(3, row);
			double rate = input.GetDouble(4, row);
			double vol = input.GetDouble(5, row);
			auto k = MakeBSMKernel(spot, strike, ttm, rate, vol, q);
			WriteBSMAll(out, row, call, k);
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

static void BSMAllSpecFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto spec_data = PrepareOptionSpecData(args);
	auto out = GetBSMAllOutput(result);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		OptionSpecRow spec;
		if (!ReadOptionSpecRow(spec_data, row, spec)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		try {
			auto k = MakeBSMKernel(spec.spot, spec.strike, spec.ttm, spec.rate, spec.vol, spec.dividend_yield);
			WriteBSMAll(out, row, spec.call, k);
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

static void BSMImpliedVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		double tol = args.ColumnCount() >= 9 ? input.GetDouble(8, row) : 1e-8;
		int max_iter = args.ColumnCount() >= 10 ? input.GetInt32(9, row) : 100;
		return BSMImpliedVol(IsCallKind(input.GetString(0, row)), input.GetDouble(1, row), input.GetDouble(2, row),
		                     input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row), q, tol,
		                     max_iter);
	});
}

static void BSMProbITMFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		bool call = IsCallKind(input.GetString(0, row));
		double d2 = BSMD2(input.GetDouble(1, row), input.GetDouble(2, row), input.GetDouble(3, row), input.GetDouble(4, row),
		                  input.GetDouble(5, row), q);
		return call ? NormCDF(d2) : NormCDF(-d2);
	});
}

static void BSMElasticityFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		bool call = IsCallKind(input.GetString(0, row));
		double spot = input.GetDouble(1, row);
		double price = BSMPrice(call, spot, input.GetDouble(2, row), input.GetDouble(3, row), input.GetDouble(4, row),
		                        input.GetDouble(5, row), q);
		double delta = BSMDelta(call, spot, input.GetDouble(2, row), input.GetDouble(3, row), input.GetDouble(4, row),
		                        input.GetDouble(5, row), q);
		return delta * spot / price;
	});
}

static void BSMHigherGreekFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool has_kind = args.data[0].GetType().id() == LogicalTypeId::VARCHAR;
		idx_t offset = has_kind ? 1 : 0;
		double q = args.ColumnCount() > offset + 5 ? input.GetDouble(offset + 5, row) : 0.0;
		bool call = has_kind ? IsCallKind(input.GetString(0, row)) : true;
		double spot = input.GetDouble(offset, row);
		double strike = input.GetDouble(offset + 1, row);
		double ttm = input.GetDouble(offset + 2, row);
		double rate = input.GetDouble(offset + 3, row);
		double vol = input.GetDouble(offset + 4, row);
		auto k = MakeBSMKernel(spot, strike, ttm, rate, vol, q);
		double gamma = BSMGammaFromKernel(k);
		double vega = BSMVegaFromKernel(k);
		if (name == "vanna") {
			return -k.df_dividend * k.pdf_d1 * k.d2 / vol;
		}
		if (name == "vomma") {
			return vega * k.d1 * k.d2 / vol;
		}
		if (name == "speed") {
			return -gamma / spot * (k.d1 / k.st + 1.0);
		}
		if (name == "zomma") {
			return gamma * (k.d1 * k.d2 - 1.0) / vol;
		}
		if (name == "ultima") {
			return -vega / (vol * vol) * (k.d1 * k.d2 * (1.0 - k.d1 * k.d2) + k.d1 * k.d1 + k.d2 * k.d2);
		}
		if (name == "charm") {
			double term = (2.0 * (rate - q) * ttm - k.d2 * k.st) / (2.0 * ttm * k.st);
			if (call) {
				return q * k.df_dividend * NormCDF(k.d1) - k.df_dividend * k.pdf_d1 * term;
			}
			return -q * k.df_dividend * NormCDF(-k.d1) - k.df_dividend * k.pdf_d1 * term;
		}
		if (name == "color") {
			return -k.df_dividend * k.pdf_d1 / (2.0 * spot * ttm * k.st) *
			       (2.0 * q * ttm + 1.0 + k.d1 * (2.0 * (rate - q) * ttm - k.d2 * k.st) / k.st);
		}
		return std::numeric_limits<double>::quiet_NaN();
	});
}

static scalar_function_t BSMHigherGreekScalar(const string &name) {
	return [name](DataChunk &args, ExpressionState &state, Vector &result) {
		BSMHigherGreekFunction(args, state, result, name);
	};
}

static void BSMProbTouchFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		bool call = IsCallKind(input.GetString(0, row));
		double d2 = BSMD2(input.GetDouble(1, row), input.GetDouble(2, row), input.GetDouble(3, row), input.GetDouble(4, row),
		                  input.GetDouble(5, row), q);
		double prob_itm = call ? NormCDF(d2) : NormCDF(-d2);
		return std::min(1.0, 2.0 * prob_itm);
	});
}

static void BSMPriceDatesFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 8 ? input.GetDouble(7, row) : 0.0;
		string day_count = args.ColumnCount() >= 9 ? input.GetString(8, row) : "ACT/365F";
		double ttm = YearFrac(input.GetDate(3, row), input.GetDate(4, row), day_count);
		return BSMPrice(IsCallKind(input.GetString(0, row)), input.GetDouble(1, row), input.GetDouble(2, row), ttm,
		                input.GetDouble(5, row), input.GetDouble(6, row), q);
	});
}

static double ImpliedVolBisection(const std::function<double(double)> &price_fn, double target, double tolerance,
                                  int max_iter) {
	if (!IsFinite(target) || !IsFinite(tolerance) || target < 0.0 || !(tolerance > 0.0) || max_iter <= 0) {
		throw InvalidInputException("Invalid implied-vol input");
	}
	double lo = 1e-10;
	double hi = 5.0;
	double low_price = price_fn(lo);
	if (target < low_price - tolerance) {
		throw InvalidInputException("Option price is below no-arbitrage intrinsic value");
	}
	if (std::fabs(target - low_price) <= tolerance) {
		return 0.0;
	}
	while (price_fn(hi) < target && hi < 100.0) {
		hi *= 2.0;
	}
	if (price_fn(hi) < target) {
		throw InvalidInputException("Could not bracket implied volatility");
	}
	for (int i = 0; i < max_iter; i++) {
		double mid = 0.5 * (lo + hi);
		double value = price_fn(mid);
		if (std::fabs(value - target) <= tolerance) {
			return mid;
		}
		if (value < target) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	return 0.5 * (lo + hi);
}

static void Black76GreeksFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	PreparedInputs input(args);
	auto out = GetGreeksOutput(result);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		try {
			bool call = IsCallKind(input.GetString(0, row));
			double forward = input.GetDouble(1, row);
			double strike = input.GetDouble(2, row);
			double ttm = input.GetDouble(3, row);
			double rate = input.GetDouble(4, row);
			double vol = input.GetDouble(5, row);
			if (!(ttm > 0.0) || !(vol > 0.0)) {
				throw InvalidInputException("Black-76 Greeks require ttm > 0 and vol > 0");
			}
			double df = std::exp(-rate * ttm);
			double st = vol * std::sqrt(ttm);
			double d1 = (std::log(forward / strike) + 0.5 * vol * vol * ttm) / st;
			double d2 = d1 - st;
			out.delta[row] = call ? df * NormCDF(d1) : -df * NormCDF(-d1);
			out.gamma[row] = df * NormPDF(d1) / (forward * st);
			out.vega[row] = df * forward * NormPDF(d1) * std::sqrt(ttm);
			double price = Black76Price(call, forward, strike, ttm, rate, vol);
			out.theta[row] = -forward * df * NormPDF(d1) * vol / (2.0 * std::sqrt(ttm)) + rate * price;
			out.rho[row] = -ttm * price;
			(void)d2;
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

static void Black76ImpliedVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool call = IsCallKind(input.GetString(0, row));
		double price = input.GetDouble(1, row);
		double forward = input.GetDouble(2, row);
		double strike = input.GetDouble(3, row);
		double ttm = input.GetDouble(4, row);
		double rate = input.GetDouble(5, row);
		double tol = args.ColumnCount() >= 8 ? input.GetDouble(7, row) : 1e-8;
		int max_iter = 100;
		return ImpliedVolBisection([&](double vol) { return Black76Price(call, forward, strike, ttm, rate, vol); },
		                           price, tol, max_iter);
	});
}

static void BachelierGreeksFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	PreparedInputs input(args);
	auto out = GetGreeksOutput(result);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		try {
			bool call = IsCallKind(input.GetString(0, row));
			double forward = input.GetDouble(1, row);
			double strike = input.GetDouble(2, row);
			double ttm = input.GetDouble(3, row);
			double rate = input.GetDouble(4, row);
			double normal_vol = input.GetDouble(5, row);
			if (!(ttm > 0.0) || !(normal_vol > 0.0) || !IsFinite(forward) || !IsFinite(strike) ||
			    !IsFinite(rate)) {
				throw InvalidInputException("Bachelier Greeks require finite inputs, ttm > 0, and vol > 0");
			}
			double df = std::exp(-rate * ttm);
			double stddev = normal_vol * std::sqrt(ttm);
			double d = (forward - strike) / stddev;
			double price = BachelierPrice(call, forward, strike, ttm, rate, normal_vol);
			out.delta[row] = call ? df * NormCDF(d) : -df * NormCDF(-d);
			out.gamma[row] = df * NormPDF(d) / stddev;
			out.vega[row] = df * std::sqrt(ttm) * NormPDF(d);
			out.theta[row] = -0.5 * df * normal_vol * NormPDF(d) / std::sqrt(ttm) + rate * price;
			out.rho[row] = -ttm * price;
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

static void BachelierImpliedVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool call = IsCallKind(input.GetString(0, row));
		double price = input.GetDouble(1, row);
		double forward = input.GetDouble(2, row);
		double strike = input.GetDouble(3, row);
		double ttm = input.GetDouble(4, row);
		double rate = input.GetDouble(5, row);
		double tol = args.ColumnCount() >= 8 ? input.GetDouble(7, row) : 1e-8;
		int max_iter = 100;
		return ImpliedVolBisection([&](double vol) { return BachelierPrice(call, forward, strike, ttm, rate, vol); },
		                           price, tol, max_iter);
	});
}

static double BarrierSafeProduct(double power, double probability) {
	return probability == 0.0 ? 0.0 : power * probability;
}

static double BarrierPrice(bool call, const string &kind, double spot, double strike, double barrier, double rebate,
                           double ttm, double rate, double vol, double dividend_yield) {
	if (!IsFinite(spot) || !IsFinite(strike) || !IsFinite(barrier) || !IsFinite(rebate) || !IsFinite(ttm) ||
	    !IsFinite(rate) || !IsFinite(vol) || !IsFinite(dividend_yield) || !(spot > 0.0) || !(strike > 0.0) ||
	    !(barrier > 0.0) || rebate < 0.0 || ttm < 0.0 || vol < 0.0) {
		throw InvalidInputException("Invalid barrier option input");
	}
	auto barrier_kind = Normalize(kind);
	barrier_kind = StringUtil::Replace(barrier_kind, "_", "-");
	if (barrier_kind == "di") {
		barrier_kind = "down-in";
	} else if (barrier_kind == "do") {
		barrier_kind = "down-out";
	} else if (barrier_kind == "ui") {
		barrier_kind = "up-in";
	} else if (barrier_kind == "uo") {
		barrier_kind = "up-out";
	}
	const bool down = barrier_kind == "down-in" || barrier_kind == "down-out";
	const bool up = barrier_kind == "up-in" || barrier_kind == "up-out";
	const bool knock_in = barrier_kind == "down-in" || barrier_kind == "up-in";
	const bool knock_out = barrier_kind == "down-out" || barrier_kind == "up-out";
	if ((!down && !up) || (!knock_in && !knock_out)) {
		throw InvalidInputException("Unknown barrier kind '%s'", kind);
	}
	const bool touched = (down && spot <= barrier) || (up && spot >= barrier);
	const double vanilla = BSMPrice(call, spot, strike, ttm, rate, vol, dividend_yield);
	if (touched) {
		return knock_in ? vanilla : rebate;
	}
	if (ttm == 0.0) {
		return knock_in ? rebate : vanilla;
	}
	if (vol == 0.0) {
		throw InvalidInputException("Barrier pricing requires positive volatility before expiry");
	}

	// Reiner-Rubinstein continuously monitored European single-barrier terms.
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
		return option_phi * (spot * df_q * NormCDF(option_phi * x1) -
		                     strike * df_r * NormCDF(option_phi * (x1 - sigma_sqrt_t)));
	};
	auto b = [&](double option_phi) {
		double x2 = std::log(spot / barrier) / sigma_sqrt_t + mu_sigma;
		return option_phi * (spot * df_q * NormCDF(option_phi * x2) -
		                     strike * df_r * NormCDF(option_phi * (x2 - sigma_sqrt_t)));
	};
	auto c = [&](double direction_eta, double option_phi) {
		double y1 = std::log(barrier * hs / strike) / sigma_sqrt_t + mu_sigma;
		double n1 = NormCDF(direction_eta * y1);
		double n2 = NormCDF(direction_eta * (y1 - sigma_sqrt_t));
		return option_phi *
		       (spot * df_q * BarrierSafeProduct(power_mu_plus, n1) -
		        strike * df_r * BarrierSafeProduct(power_mu, n2));
	};
	auto d = [&](double direction_eta, double option_phi) {
		double y2 = std::log(barrier / spot) / sigma_sqrt_t + mu_sigma;
		double n1 = NormCDF(direction_eta * y2);
		double n2 = NormCDF(direction_eta * (y2 - sigma_sqrt_t));
		return option_phi *
		       (spot * df_q * BarrierSafeProduct(power_mu_plus, n1) -
		        strike * df_r * BarrierSafeProduct(power_mu, n2));
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
			throw InvalidInputException("Barrier rebate formula is undefined for these rate inputs");
		}
		double lambda = std::sqrt(lambda_sq);
		double z = std::log(barrier / spot) / sigma_sqrt_t + lambda * sigma_sqrt_t;
		double n1 = NormCDF(direction_eta * z);
		double n2 = NormCDF(direction_eta * (z - 2.0 * lambda * sigma_sqrt_t));
		return rebate *
		       (BarrierSafeProduct(std::pow(hs, mu + lambda), n1) +
		        BarrierSafeProduct(std::pow(hs, mu - lambda), n2));
	};

	double price;
	if (call && barrier_kind == "down-in") {
		price = strike >= barrier ? c(1.0, phi) + e(1.0) : a(phi) - b(phi) + d(1.0, phi) + e(1.0);
	} else if (call && barrier_kind == "up-in") {
		price = strike >= barrier ? a(phi) + e(-1.0) : b(phi) - c(-1.0, phi) + d(-1.0, phi) + e(-1.0);
	} else if (call && barrier_kind == "down-out") {
		price = strike >= barrier ? a(phi) - c(1.0, phi) + f(1.0) : b(phi) - d(1.0, phi) + f(1.0);
	} else if (call) {
		price = strike >= barrier ? f(-1.0) : a(phi) - b(phi) + c(-1.0, phi) - d(-1.0, phi) + f(-1.0);
	} else if (barrier_kind == "down-in") {
		price = strike >= barrier ? b(phi) - c(1.0, phi) + d(1.0, phi) + e(1.0) : a(phi) + e(1.0);
	} else if (barrier_kind == "up-in") {
		price = strike >= barrier ? a(phi) - b(phi) + d(-1.0, phi) + e(-1.0) : c(-1.0, phi) + e(-1.0);
	} else if (barrier_kind == "down-out") {
		price = strike >= barrier ? a(phi) - b(phi) + c(1.0, phi) - d(1.0, phi) + f(1.0) : f(1.0);
	} else {
		price = strike >= barrier ? b(phi) - d(-1.0, phi) + f(-1.0) : a(phi) - c(-1.0, phi) + f(-1.0);
	}
	if (!IsFinite(price) || price < -1e-10) {
		throw InvalidInputException("Barrier price is not finite and non-negative");
	}
	return std::max(0.0, price);
}

static void BarrierPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		idx_t offset = args.ColumnCount() >= 9 ? 1 : 0;
		double rebate = offset ? input.GetDouble(5, row) : 0.0;
		double q = args.ColumnCount() >= 10 ? input.GetDouble(9, row) : 0.0;
		return BarrierPrice(IsCallKind(input.GetString(0, row)), input.GetString(1, row), input.GetDouble(2, row),
		                    input.GetDouble(3, row), input.GetDouble(4, row), rebate,
		                    input.GetDouble(5 + offset, row), input.GetDouble(6 + offset, row),
		                    input.GetDouble(7 + offset, row), q);
	});
}

static void Black76PriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [](const PreparedInputs &input, idx_t row) {
		return Black76Price(IsCallKind(input.GetString(0, row)), input.GetDouble(1, row), input.GetDouble(2, row),
		                    input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row));
	});
}

static void BachelierPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [](const PreparedInputs &input, idx_t row) {
		return BachelierPrice(IsCallKind(input.GetString(0, row)), input.GetDouble(1, row), input.GetDouble(2, row),
		                      input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row));
	});
}

static void BinomialPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		int steps = args.ColumnCount() >= 8 ? input.GetInt32(7, row) : 200;
		string exercise = args.ColumnCount() >= 9 ? input.GetString(8, row) : "european";
		string tree = args.ColumnCount() >= 10 ? input.GetString(9, row) : "crr";
		return BinomialPrice(IsCallKind(input.GetString(0, row)), input.GetDouble(1, row), input.GetDouble(2, row),
		                     input.GetDouble(3, row), input.GetDouble(4, row), input.GetDouble(5, row), q, steps,
		                     exercise, tree);
	});
}

static void DigitalPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		double payout = args.ColumnCount() >= 8 ? input.GetDouble(7, row) : 1.0;
		bool call = IsCallKind(input.GetString(0, row));
		double d2 = BSMD2(input.GetDouble(1, row), input.GetDouble(2, row), input.GetDouble(3, row), input.GetDouble(4, row),
		                  input.GetDouble(5, row), q);
		return payout * std::exp(-input.GetDouble(4, row) * input.GetDouble(3, row)) * (call ? NormCDF(d2) : NormCDF(-d2));
	});
}

static void AssetOrNothingPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		bool call = IsCallKind(input.GetString(0, row));
		double d1 = BSMD1(input.GetDouble(1, row), input.GetDouble(2, row), input.GetDouble(3, row), input.GetDouble(4, row),
		                  input.GetDouble(5, row), q);
		return input.GetDouble(1, row) * std::exp(-q * input.GetDouble(3, row)) * (call ? NormCDF(d1) : NormCDF(-d1));
	});
}

static void AsianGeometricPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double q = args.ColumnCount() >= 7 ? input.GetDouble(6, row) : 0.0;
		bool call = IsCallKind(input.GetString(0, row));
		double spot = input.GetDouble(1, row);
		double strike = input.GetDouble(2, row);
		double ttm = input.GetDouble(3, row);
		double rate = input.GetDouble(4, row);
		double vol = input.GetDouble(5, row);
		double sigma_g = vol / std::sqrt(3.0);
		double b_g = 0.5 * (rate - q - 0.5 * vol * vol) + 0.5 * sigma_g * sigma_g;
		double d1 = (std::log(spot / strike) + (b_g + 0.5 * sigma_g * sigma_g) * ttm) / (sigma_g * std::sqrt(ttm));
		double d2 = d1 - sigma_g * std::sqrt(ttm);
		double forward = spot * std::exp((b_g - rate) * ttm);
		return call ? forward * NormCDF(d1) - strike * std::exp(-rate * ttm) * NormCDF(d2)
		            : strike * std::exp(-rate * ttm) * NormCDF(-d2) - forward * NormCDF(-d1);
	});
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
		if (!(ttm > 0.0) || total_var < 0.0) {
			throw InvalidInputException("Invalid SVI vol input");
		}
		return std::sqrt(total_var / ttm);
	});
}
