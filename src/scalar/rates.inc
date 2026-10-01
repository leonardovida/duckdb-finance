static void YearFracFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		auto convention = args.ColumnCount() == 3 ? input.GetString(2, row) : "ACT/365F";
		return YearFrac(input.GetDate(0, row), input.GetDate(1, row), convention);
	});
}

static void DiscountFactorFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		string compounding = args.ColumnCount() >= 3 ? input.GetString(2, row) : "continuous";
		int frequency = args.ColumnCount() >= 4 ? input.GetInt32(3, row) : 1;
		return DiscountFactor(input.GetDouble(0, row), input.GetDouble(1, row), compounding, frequency);
	});
}

static void RateFromDiscountFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		string compounding = args.ColumnCount() >= 3 ? input.GetString(2, row) : "continuous";
		int frequency = args.ColumnCount() >= 4 ? input.GetInt32(3, row) : 1;
		return RateFromDiscount(input.GetDouble(0, row), input.GetDouble(1, row), compounding, frequency);
	});
}

static void ForwardRateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		string compounding = args.ColumnCount() >= 5 ? input.GetString(4, row) : "continuous";
		return ForwardRate(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row),
		                   input.GetDouble(3, row), compounding);
	});
}

static void PresentValueFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		string compounding = args.ColumnCount() >= 4 ? input.GetString(3, row) : "continuous";
		return PresentValue(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), compounding);
	});
}

static void FutureValueFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		string compounding = args.ColumnCount() >= 4 ? input.GetString(3, row) : "continuous";
		return FutureValue(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), compounding);
	});
}

static void AnnuityPaymentFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double rate = input.GetDouble(0, row);
		double nper = input.GetDouble(1, row);
		double pv = input.GetDouble(2, row);
		double fv = args.ColumnCount() >= 4 ? input.GetDouble(3, row) : 0.0;
		string when = args.ColumnCount() >= 5 ? Normalize(input.GetString(4, row)) : "end";
		if (!IsFinite(rate) || rate <= -1.0 || !IsFinite(nper) || !(nper > 0.0) ||
		    !IsFinite(pv) || !IsFinite(fv)) {
			throw InvalidInputException("Annuity inputs must be finite, nper positive, and rate greater than -1");
		}
		if (when != "end" && when != "0" && when != "begin" && when != "start" && when != "1") {
			throw InvalidInputException("Unknown annuity payment timing '%s'", when);
		}
		double due = (when == "begin" || when == "start" || when == "1") ? 1.0 : 0.0;
		if (rate == 0.0) {
			return -(pv + fv) / nper;
		}
		double growth = std::expm1(nper * std::log1p(rate));
		return -(rate * (fv + (growth + 1.0) * pv)) / ((1.0 + rate * due) * growth);
	});
}

static void BondPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int frequency = args.ColumnCount() >= 4 ? input.GetInt32(3, row) : 2;
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		return BondPrice(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), frequency, face);
	});
}

static void BondYTMFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int frequency = args.ColumnCount() >= 4 ? input.GetInt32(3, row) : 2;
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		return BondYTM(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), frequency, face);
	});
}

static void BondDurationFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int frequency = args.ColumnCount() >= 4 ? input.GetInt32(3, row) : 2;
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		string kind = args.ColumnCount() >= 6 ? input.GetString(5, row) : "macaulay";
		return BondDuration(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), frequency, face,
		                    kind);
	});
}

static void BondConvexityFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int frequency = args.ColumnCount() >= 4 ? input.GetInt32(3, row) : 2;
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		return BondConvexity(input.GetDouble(0, row), input.GetDouble(1, row), input.GetDouble(2, row), frequency,
		                     face);
	});
}

static void DV01Function(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		int frequency = args.ColumnCount() >= 4 ? input.GetInt32(3, row) : 2;
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		double coupon = input.GetDouble(0, row);
		double ytm = input.GetDouble(1, row);
		double maturity = input.GetDouble(2, row);
		return BondPrice(coupon, ytm - 0.0001, maturity, frequency, face) - BondPrice(coupon, ytm, maturity, frequency, face);
	});
}

static void AccruedInterestFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double face = args.ColumnCount() >= 5 ? input.GetDouble(4, row) : 100.0;
		string day_count = args.ColumnCount() >= 6 ? input.GetString(5, row) : "ACT/365F";
		double elapsed = YearFrac(input.GetDate(1, row), input.GetDate(0, row), day_count);
		double period = YearFrac(input.GetDate(1, row), input.GetDate(2, row), day_count);
		if (!(period > 0.0)) {
			throw InvalidInputException("Invalid coupon period");
		}
		return face * input.GetDouble(3, row) * elapsed / period;
	});
}

static void CashflowListFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	PreparedInputs input(args);
	idx_t cf_col = name == "npv" ? 1 : 0;
	auto cashflow_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[cf_col]);
	auto &cashflow_child = ListVector::GetChildMutable(args.data[cf_col]);
	auto cashflow_size = ListVector::GetListSize(args.data[cf_col]);
	FinanceFlatten(cashflow_child, cashflow_size);
	auto &cashflow_validity = FlatVector::Validity(cashflow_child);
	auto cashflow_values = FlatVector::GetData<double>(cashflow_child);
	const list_entry_t *date_entries = nullptr;
	const date_t *date_values = nullptr;
	const ValidityMask *date_validity = nullptr;
	if (name == "xirr") {
		date_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
		auto &date_child = ListVector::GetChildMutable(args.data[1]);
		auto date_size = ListVector::GetListSize(args.data[1]);
		FinanceFlatten(date_child, date_size);
		date_validity = &FlatVector::Validity(date_child);
		date_values = FlatVector::GetData<date_t>(date_child);
	}
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		try {
			auto cf_idx = input.formats[cf_col].sel->get_index(row);
			auto cashflow_entry = cashflow_entries[cf_idx];
			if (cashflow_entry.length == 0) {
				throw InvalidInputException("Cashflow list must not be empty");
			}
			ValidateListEntryNoNull(cashflow_validity, cashflow_entry,
			                        "Finance cashflow functions do not accept NULL list elements");
			if (name == "npv") {
				output[row] = CashflowNPV(input.GetDouble(0, row), cashflow_values, cashflow_entry);
			} else if (name == "irr") {
				auto scale = ValidateIRRCashflows(cashflow_values, cashflow_entry);
				double guess = args.ColumnCount() >= 2 ? input.GetDouble(1, row) : 0.1;
				output[row] = SolveRate(
				    [&](double rate) { return CashflowNPVEvaluation(rate, cashflow_values, cashflow_entry, scale); }, guess);
			} else if (name == "mirr") {
				double finance_rate = input.GetDouble(1, row);
				double reinvest_rate = input.GetDouble(2, row);
				if (!IsFinite(finance_rate) || !IsFinite(reinvest_rate) || finance_rate <= -1.0 || reinvest_rate <= -1.0) {
					throw InvalidInputException("MIRR rates must be finite and greater than -1");
				}
				double finance_df = 1.0 / (1.0 + finance_rate);
				double finance_discount = 1.0;
				double reinvest_growth = 1.0;
				auto n = cashflow_entry.length - 1;
				for (idx_t i = 0; i < n; i++) {
					reinvest_growth *= 1.0 + reinvest_rate;
				}
				double pv_negative = 0.0;
				double fv_positive = 0.0;
				for (idx_t i = 0; i < cashflow_entry.length; i++) {
					double cf = cashflow_values[cashflow_entry.offset + i];
					if (cf < 0.0) {
						pv_negative += cf * finance_discount;
					} else {
						fv_positive += cf * reinvest_growth;
					}
					finance_discount *= finance_df;
					reinvest_growth /= 1.0 + reinvest_rate;
				}
				if (pv_negative >= 0.0 || fv_positive <= 0.0 || n == 0) {
					throw InvalidInputException("MIRR requires positive and negative cashflows");
				}
				output[row] = std::pow(-fv_positive / pv_negative, 1.0 / double(n)) - 1.0;
			} else {
				auto scale = ValidateIRRCashflows(cashflow_values, cashflow_entry);
				auto date_idx = input.formats[1].sel->get_index(row);
				auto date_entry = date_entries[date_idx];
				ValidateListEntryNoNull(*date_validity, date_entry,
				                        "Finance date-list functions do not accept NULL list elements");
				if (cashflow_entry.length != date_entry.length || !Date::IsFinite(date_values[date_entry.offset])) {
					throw InvalidInputException("XIRR requires equal cashflow/date lengths and finite dates");
				}
				vector<double> amounts;
				vector<double> years;
				amounts.reserve(cashflow_entry.length);
				years.reserve(cashflow_entry.length);
				for (idx_t i = 0; i < cashflow_entry.length; i++) {
					auto date = date_values[date_entry.offset + i];
					if (!Date::IsFinite(date)) {
						throw InvalidInputException("XIRR requires finite dates");
					}
					amounts.push_back(cashflow_values[cashflow_entry.offset + i] / scale);
					years.push_back(double(int64_t(date.days) - int64_t(date_values[date_entry.offset].days)) / 365.0);
				}
				double guess = args.ColumnCount() >= 3 ? input.GetDouble(2, row) : 0.1;
				output[row] = SolveRate(
				    [&](double rate) {
					    double log_rate = std::log1p(rate);
					    double value = 0.0;
					    double derivative = 0.0;
					    for (idx_t i = 0; i < amounts.size(); i++) {
						    auto present_value = amounts[i] * std::exp(-years[i] * log_rate);
						    value += present_value;
						    derivative -= years[i] * present_value;
					    }
					    return RateEvaluation {value, derivative / (1.0 + rate)};
				    },
				    guess);
			}
			if (!std::isfinite(output[row])) {
				SetResultNull(result, row, args.size(), constant);
			}
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

static void NPVWithTimesFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	PreparedInputs input(args);
	auto cashflow_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto time_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto &cashflow_child = ListVector::GetChildMutable(args.data[0]);
	auto &time_child = ListVector::GetChildMutable(args.data[1]);
	auto cashflow_size = ListVector::GetListSize(args.data[0]);
	auto time_size = ListVector::GetListSize(args.data[1]);
	FinanceFlatten(cashflow_child, cashflow_size);
	FinanceFlatten(time_child, time_size);
	auto &cashflow_validity = FlatVector::Validity(cashflow_child);
	auto &time_validity = FlatVector::Validity(time_child);
	auto cashflow_values = FlatVector::GetData<double>(cashflow_child);
	auto time_values = FlatVector::GetData<double>(time_child);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		try {
			auto cf_idx = input.formats[0].sel->get_index(row);
			auto t_idx = input.formats[1].sel->get_index(row);
			auto cashflow_entry = cashflow_entries[cf_idx];
			auto time_entry = time_entries[t_idx];
			if (cashflow_entry.length != time_entry.length || cashflow_entry.length == 0) {
				throw InvalidInputException("NPV cashflow/time lists must be non-empty and have equal length");
			}
			ValidateListEntryNoNull(cashflow_validity, cashflow_entry, "NPV cashflow/time lists do not accept NULL elements");
			ValidateListEntryNoNull(time_validity, time_entry, "NPV cashflow/time lists do not accept NULL elements");
			auto rate = input.GetDouble(2, row);
			auto compounding = args.ColumnCount() >= 4 ? ParseCompounding(input.GetString(3, row)) : "continuous";
			double result_value = 0.0;
			if (compounding == "continuous") {
				for (idx_t i = 0; i < cashflow_entry.length; i++) {
					result_value += cashflow_values[cashflow_entry.offset + i] *
					                std::exp(-rate * time_values[time_entry.offset + i]);
				}
			} else if (compounding == "simple") {
				for (idx_t i = 0; i < cashflow_entry.length; i++) {
					result_value += cashflow_values[cashflow_entry.offset + i] /
					                (1.0 + rate * time_values[time_entry.offset + i]);
				}
			} else {
				for (idx_t i = 0; i < cashflow_entry.length; i++) {
					result_value += cashflow_values[cashflow_entry.offset + i] *
					                DiscountFactor(rate, time_values[time_entry.offset + i], compounding, 1);
				}
			}
			output[row] = result_value;
			if (!std::isfinite(output[row])) {
				SetResultNull(result, row, args.size(), constant);
			}
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

static void CurveListFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	PreparedInputs input(args);
	auto x_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto y_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto &x_child = ListVector::GetChildMutable(args.data[0]);
	auto &y_child = ListVector::GetChildMutable(args.data[1]);
	auto x_size = ListVector::GetListSize(args.data[0]);
	auto y_size = ListVector::GetListSize(args.data[1]);
	FinanceFlatten(x_child, x_size);
	FinanceFlatten(y_child, y_size);
	auto &x_validity = FlatVector::Validity(x_child);
	auto &y_validity = FlatVector::Validity(y_child);
	auto x_values = FlatVector::GetData<double>(x_child);
	auto y_values = FlatVector::GetData<double>(y_child);
	bool checked_x = false;
	bool checked_y = false;
	auto constant_x = args.data[0].GetVectorType() == VectorType::CONSTANT_VECTOR;
	auto constant_y = args.data[1].GetVectorType() == VectorType::CONSTANT_VECTOR;
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		try {
			auto x_idx = input.formats[0].sel->get_index(row);
			auto y_idx = input.formats[1].sel->get_index(row);
			if (!checked_x) {
				auto entry = x_entries[x_idx];
				ValidateListEntryNoNull(x_validity, entry, "Curve list functions do not accept NULL list elements");
				for (idx_t i = 0; i < entry.length; i++) {
					if (!IsFinite(x_values[entry.offset + i]) ||
					    (i > 0 && !(x_values[entry.offset + i] > x_values[entry.offset + i - 1]))) {
						throw InvalidInputException("Curve maturities must be finite and strictly increasing");
					}
				}
				checked_x = constant_x;
			}
			if (!checked_y) {
				auto entry = y_entries[y_idx];
				ValidateListEntryNoNull(y_validity, entry, "Curve list functions do not accept NULL list elements");
				for (idx_t i = 0; i < entry.length; i++) {
					if (!IsFinite(y_values[entry.offset + i])) {
						throw InvalidInputException("Curve values must be finite");
					}
				}
				checked_y = constant_y;
			}
			double target = input.GetDouble(2, row);
			if (!IsFinite(target)) {
				throw InvalidInputException("Curve target must be finite");
			}
			double interpolated = LinearInterpolateList(x_values, x_entries[x_idx], y_values, y_entries[y_idx], target);
			output[row] = name == "discount" ? std::exp(-interpolated * target) : interpolated;
			if (!std::isfinite(output[row])) {
				SetResultNull(result, row, args.size(), constant);
			}
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

static void SwapRateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	PreparedInputs input(args);
	auto maturity_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto discount_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto &maturity_child = ListVector::GetChildMutable(args.data[0]);
	auto &discount_child = ListVector::GetChildMutable(args.data[1]);
	auto maturity_size = ListVector::GetListSize(args.data[0]);
	auto discount_size = ListVector::GetListSize(args.data[1]);
	FinanceFlatten(maturity_child, maturity_size);
	FinanceFlatten(discount_child, discount_size);
	auto &maturity_validity = FlatVector::Validity(maturity_child);
	auto &discount_validity = FlatVector::Validity(discount_child);
	auto maturities = FlatVector::GetData<double>(maturity_child);
	auto discounts = FlatVector::GetData<double>(discount_child);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		try {
			auto m_idx = input.formats[0].sel->get_index(row);
			auto d_idx = input.formats[1].sel->get_index(row);
			auto maturity_entry = maturity_entries[m_idx];
			auto discount_entry = discount_entries[d_idx];
			if (maturity_entry.length != discount_entry.length || discount_entry.length == 0) {
				throw InvalidInputException("Swap-rate inputs must be non-empty and have equal length");
			}
			ValidateListEntryNoNull(maturity_validity, maturity_entry, "Swap-rate lists do not accept NULL list elements");
			ValidateListEntryNoNull(discount_validity, discount_entry, "Swap-rate lists do not accept NULL list elements");
			double annuity = 0.0;
			double previous = 0.0;
			for (idx_t i = 0; i < maturity_entry.length; i++) {
				double maturity = maturities[maturity_entry.offset + i];
				double accrual = maturity - previous;
				annuity += accrual * discounts[discount_entry.offset + i];
				previous = maturity;
			}
			output[row] = (1.0 - discounts[discount_entry.offset + discount_entry.length - 1]) / annuity;
			if (!std::isfinite(output[row])) {
				SetResultNull(result, row, args.size(), constant);
			}
		} catch (const std::exception &) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}
