static void YearFracFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<DayCount> day_count(args, 2, ParseDayCountNoPeriod, DayCount::ACT_365F);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		return YearFrac(input.GetDate(0, row), input.GetDate(1, row), day_count.Get(input, row));
	});
}

static void DiscountFactorFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<Compounding> compounding(args, 2, ParseCompoundingEnum, Compounding::CONTINUOUS);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int64_t frequency = args.ColumnCount() >= 4 ? input.GetInteger(3, row) : 1;
		return DiscountFactor(input.GetDouble(0, row), input.GetDouble(1, row), compounding.Get(input, row), frequency);
	});
}

static void RateFromDiscountFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<Compounding> compounding(args, 2, ParseCompoundingEnum, Compounding::CONTINUOUS);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int64_t frequency = args.ColumnCount() >= 4 ? input.GetInteger(3, row) : 1;
		return RateFromDiscount(input.GetDouble(0, row), input.GetDouble(1, row), compounding.Get(input, row),
		                        frequency);
	});
}

static void ForwardRateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<Compounding> compounding(args, 4, ParseCompoundingEnum, Compounding::CONTINUOUS);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		return ForwardRate(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row),
		                   input.GetDouble(3, row), compounding.Get(input, row));
	});
}

static void PresentValueFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<Compounding> compounding(args, 3, ParseCompoundingEnum, Compounding::CONTINUOUS);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		return input.GetDouble(0, row) *
		       DiscountFactor(input.GetDouble(1, row), input.GetDouble(2, row), compounding.Get(input, row), 1);
	});
}

static void FutureValueFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<Compounding> compounding(args, 3, ParseCompoundingEnum, Compounding::CONTINUOUS);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		return input.GetDouble(0, row) /
		       DiscountFactor(input.GetDouble(1, row), input.GetDouble(2, row), compounding.Get(input, row), 1);
	});
}

static void AnnuityPaymentFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<AnnuityTiming> timing(args, 4, ParseAnnuityTiming, AnnuityTiming::END);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double rate = input.GetDouble(0, row);
		double nper = input.GetDouble(1, row);
		double pv = input.GetDouble(2, row);
		double fv = args.ColumnCount() >= 4 ? input.GetDouble(3, row) : 0.0;
		double due = timing.Get(input, row) == AnnuityTiming::BEGIN ? 1.0 : 0.0;
		if (!IsFinite(rate) || rate <= -1.0 || !IsFinite(nper) || !(nper > 0.0) || !IsFinite(pv) || !IsFinite(fv)) {
			return FIN_NAN;
		}
		if (rate == 0.0) {
			return -(pv + fv) / nper;
		}
		double growth = std::expm1(nper * std::log1p(rate));
		return -(rate * (fv + (growth + 1.0) * pv)) / ((1.0 + rate * due) * growth);
	});
}

static void BondPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int64_t frequency = args.ColumnCount() >= 4 ? input.GetInteger(3, row) : 2;
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		return BondPrice(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), frequency, face);
	});
}

static void BondYTMFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int64_t frequency = args.ColumnCount() >= 4 ? input.GetInteger(3, row) : 2;
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		return BondYTM(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), frequency, face);
	});
}

static void BondDurationFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<DurationKind> kind(args, 5, ParseDurationKind, DurationKind::MACAULAY);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int64_t frequency = args.ColumnCount() >= 4 ? input.GetInteger(3, row) : 2;
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		return BondDuration(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), frequency, face,
		                    kind.Get(input, row));
	});
}

static void BondConvexityFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int64_t frequency = args.ColumnCount() >= 4 ? input.GetInteger(3, row) : 2;
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		return BondConvexity(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), frequency,
		                     face);
	});
}

static void DV01Function(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int64_t frequency = args.ColumnCount() >= 4 ? input.GetInteger(3, row) : 2;
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		double coupon = input.GetDouble(0, row);
		double ytm = input.GetDouble(1, row);
		double maturity = input.GetDouble(2, row);
		return BondPrice(coupon, ytm - 0.0001, maturity, frequency, face) -
		       BondPrice(coupon, ytm, maturity, frequency, face);
	});
}

static void AccruedInterestFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<DayCount> day_count(args, 5, ParseDayCountEnum, DayCount::ACT_365F);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		return AccruedInterest(input.GetDate(0, row), input.GetDate(1, row), input.GetDate(2, row),
		                       input.GetDouble(3, row), face, day_count.Get(input, row));
	});
}

enum class CashflowKind : uint8_t { NPV, IRR, MIRR, XIRR };

static double MIRR(const double *cashflows, const list_entry_t &entry, double finance_rate, double reinvest_rate) {
	if (!IsFinite(finance_rate) || !IsFinite(reinvest_rate) || finance_rate <= -1.0 || reinvest_rate <= -1.0 ||
	    entry.length < 2) {
		return FIN_NAN;
	}
	double finance_df = 1.0 / (1.0 + finance_rate);
	double finance_discount = 1.0;
	auto n = entry.length - 1;
	double reinvest_growth = std::exp(double(n) * std::log1p(reinvest_rate));
	double pv_negative = 0.0;
	double fv_positive = 0.0;
	for (idx_t i = 0; i < entry.length; i++) {
		double cf = cashflows[entry.offset + i];
		if (cf < 0.0) {
			pv_negative += cf * finance_discount;
		} else {
			fv_positive += cf * reinvest_growth;
		}
		finance_discount *= finance_df;
		reinvest_growth /= 1.0 + reinvest_rate;
	}
	if (!(pv_negative < 0.0) || !(fv_positive > 0.0)) {
		return FIN_NAN;
	}
	return std::pow(-fv_positive / pv_negative, 1.0 / double(n)) - 1.0;
}

static void CashflowListFunction(DataChunk &args, ExpressionState &, Vector &result, CashflowKind kind) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	PreparedInputs input(args);
	idx_t cf_col = kind == CashflowKind::NPV ? 1 : 0;
	DoubleListArg cashflows(args, input, cf_col);
	const list_entry_t *date_entries = nullptr;
	const date_t *date_values = nullptr;
	const ValidityMask *date_validity = nullptr;
	vector<double> amounts;
	vector<double> years;
	if (kind == CashflowKind::XIRR) {
		date_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
		auto &date_child = ListVector::GetChildMutable(args.data[1]);
		FinanceFlatten(date_child, ListVector::GetListSize(args.data[1]));
		date_validity = &FlatVector::Validity(date_child);
		date_values = FlatVector::GetData<date_t>(date_child);
	}
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		auto entry = cashflows.Entry(input, row);
		double value = FIN_NAN;
		if (entry.length > 0 && !cashflows.HasNullElement(entry)) {
			const double *cf = cashflows.values;
			switch (kind) {
			case CashflowKind::NPV:
				value = CashflowNPV(input.GetDouble(0, row), cf, entry);
				break;
			case CashflowKind::IRR: {
				auto scale = IRRCashflowScale(cf, entry);
				double guess = args.ColumnCount() >= 2 ? input.GetDouble(1, row) : 0.1;
				if (IsFinite(scale)) {
					value = SolveRate([&](double rate) { return CashflowNPVEvaluation(rate, cf, entry, scale); }, guess);
				}
				break;
			}
			case CashflowKind::MIRR:
				value = MIRR(cf, entry, input.GetDouble(1, row), input.GetDouble(2, row));
				break;
			case CashflowKind::XIRR: {
				auto scale = IRRCashflowScale(cf, entry);
				auto date_entry = date_entries[input.formats[1].sel->get_index(row)];
				bool valid = IsFinite(scale) && date_entry.length == entry.length;
				for (idx_t i = 0; valid && i < date_entry.length; i++) {
					auto pos = date_entry.offset + i;
					valid = (!date_validity->CanHaveNull() || date_validity->RowIsValid(pos)) &&
					        Date::IsFinite(date_values[pos]);
				}
				if (!valid) {
					break;
				}
				amounts.clear();
				years.clear();
				auto first_day = int64_t(date_values[date_entry.offset].days);
				for (idx_t i = 0; i < entry.length; i++) {
					amounts.push_back(cf[entry.offset + i] / scale);
					years.push_back(double(int64_t(date_values[date_entry.offset + i].days) - first_day) / 365.0);
				}
				double guess = args.ColumnCount() >= 3 ? input.GetDouble(2, row) : 0.1;
				value = SolveRate(
				    [&](double rate) {
					    double log_rate = std::log1p(rate);
					    double npv = 0.0;
					    double derivative = 0.0;
					    for (idx_t i = 0; i < amounts.size(); i++) {
						    auto present_value = amounts[i] * std::exp(-years[i] * log_rate);
						    npv += present_value;
						    derivative -= years[i] * present_value;
					    }
					    return RateEvaluation {npv, derivative / (1.0 + rate)};
				    },
				    guess);
				break;
			}
			}
		}
		output[row] = value;
		if (!std::isfinite(value)) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

//! NPV of cashflows at year fractions `times` (may be negative). Default compounding is periodic annual,
//! (1 + r)^-t, matching fin_npv(rate, cashflows) and fin_irr.
static void NPVWithTimesFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<Compounding> compounding_arg(args, 3, ParseCompoundingEnum, Compounding::PERIODIC);
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	PreparedInputs input(args);
	DoubleListArg cashflows(args, input, 0);
	DoubleListArg times(args, input, 1);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		auto compounding = compounding_arg.Get(input, row);
		auto cashflow_entry = cashflows.Entry(input, row);
		auto time_entry = times.Entry(input, row);
		double rate = input.GetDouble(2, row);
		double value = FIN_NAN;
		if (cashflow_entry.length == time_entry.length && cashflow_entry.length > 0 &&
		    !cashflows.HasNullElement(cashflow_entry) && !times.HasNullElement(time_entry) && IsFinite(rate)) {
			double frequency = double(CompoundingFrequency(compounding, 1));
			double log_growth = compounding == Compounding::CONTINUOUS ? rate
			                    : compounding == Compounding::SIMPLE  ? 0.0
			                    : (1.0 + rate / frequency > 0.0) ? frequency * std::log1p(rate / frequency)
			                                                       : FIN_NAN;
			value = 0.0;
			for (idx_t i = 0; i < cashflow_entry.length; i++) {
				double t = times.values[time_entry.offset + i];
				double cf = cashflows.values[cashflow_entry.offset + i];
				double df;
				if (compounding == Compounding::SIMPLE) {
					double base = 1.0 + rate * t;
					df = base > 0.0 ? 1.0 / base : FIN_NAN;
				} else {
					df = std::exp(-log_growth * t);
				}
				value += cf * df;
			}
		}
		output[row] = value;
		if (!std::isfinite(value)) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

enum class CurveKind : uint8_t { INTERPOLATE, ZERO, DISCOUNT };

static void CurveListFunction(DataChunk &args, ExpressionState &, Vector &result, CurveKind kind) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	PreparedInputs input(args);
	DoubleListArg xs(args, input, 0);
	DoubleListArg ys(args, input, 1);
	// Constant curves are validated once per chunk.
	int x_state = -1;
	int y_state = -1;
	auto constant_x = args.data[0].GetVectorType() == VectorType::CONSTANT_VECTOR;
	auto constant_y = args.data[1].GetVectorType() == VectorType::CONSTANT_VECTOR;
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		auto x_entry = xs.Entry(input, row);
		auto y_entry = ys.Entry(input, row);
		bool x_ok;
		if (constant_x && x_state >= 0) {
			x_ok = x_state == 1;
		} else {
			x_ok = x_entry.length > 0 && !xs.HasNullElement(x_entry);
			for (idx_t i = 0; x_ok && i < x_entry.length; i++) {
				double value = xs.values[x_entry.offset + i];
				x_ok = IsFinite(value) && (i == 0 || value > xs.values[x_entry.offset + i - 1]);
			}
			x_state = x_ok ? 1 : 0;
		}
		bool y_ok;
		if (constant_y && y_state >= 0) {
			y_ok = y_state == 1;
		} else {
			y_ok = !ys.HasNullElement(y_entry);
			for (idx_t i = 0; y_ok && i < y_entry.length; i++) {
				y_ok = IsFinite(ys.values[y_entry.offset + i]);
			}
			y_state = y_ok ? 1 : 0;
		}
		double target = input.GetDouble(2, row);
		double value = FIN_NAN;
		bool target_ok = IsFinite(target) && (kind != CurveKind::DISCOUNT || target >= 0.0);
		if (x_ok && y_ok && target_ok && x_entry.length == y_entry.length) {
			double interpolated = LinearInterpolateList(xs.values, x_entry, ys.values, y_entry, target);
			value = kind == CurveKind::DISCOUNT ? std::exp(-interpolated * target) : interpolated;
		}
		output[row] = value;
		if (!std::isfinite(value)) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

//! Par swap rate from payment times and discount factors: (1 - P(T_n)) / sum(tau_i P(T_i)).
static void SwapRateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	PreparedInputs input(args);
	DoubleListArg maturities(args, input, 0);
	DoubleListArg discounts(args, input, 1);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		auto maturity_entry = maturities.Entry(input, row);
		auto discount_entry = discounts.Entry(input, row);
		double value = FIN_NAN;
		if (maturity_entry.length == discount_entry.length && discount_entry.length > 0 &&
		    !maturities.HasNullElement(maturity_entry) && !discounts.HasNullElement(discount_entry)) {
			double annuity = 0.0;
			double previous = 0.0;
			bool valid = true;
			for (idx_t i = 0; valid && i < maturity_entry.length; i++) {
				double maturity = maturities.values[maturity_entry.offset + i];
				double df = discounts.values[discount_entry.offset + i];
				valid = IsFinite(maturity) && maturity > previous && IsFinite(df) && df > 0.0;
				annuity += (maturity - previous) * df;
				previous = maturity;
			}
			if (valid && annuity > 0.0) {
				value = (1.0 - discounts.values[discount_entry.offset + discount_entry.length - 1]) / annuity;
			}
		}
		output[row] = value;
		if (!std::isfinite(value)) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}
