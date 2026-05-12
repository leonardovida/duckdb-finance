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
	child_list_t<LogicalType> children;
	children.emplace_back("delta", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("gamma", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("vega", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("theta", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("rho", FinanceLogicalType(LogicalTypeId::DOUBLE));
	return LogicalType::STRUCT(std::move(children));
}

static LogicalType BSMAllType() {
	child_list_t<LogicalType> children;
	children.emplace_back("price", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("delta", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("gamma", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("vega", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("theta", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("rho", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("d1", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("d2", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("intrinsic", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("time_value", FinanceLogicalType(LogicalTypeId::DOUBLE));
	return LogicalType::STRUCT(std::move(children));
}

static void BSMGreeksFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	auto delta = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[0]));
	auto gamma = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[1]));
	auto vega = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[2]));
	auto theta = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[3]));
	auto rho = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[4]));
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
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
			delta[row] = BSMDeltaFromKernel(call, k);
			gamma[row] = BSMGammaFromKernel(k);
			vega[row] = BSMVegaFromKernel(k);
			theta[row] = BSMThetaFromKernel(call, k);
			rho[row] = BSMRhoFromKernel(call, k);
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void BSMAllFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	vector<double *> out;
	for (auto &child : children) {
		out.push_back(FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(child)));
	}
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
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
			double price = BSMPriceFromKernel(call, k);
			double intrinsic = OptionPayoff(call, spot, strike);
			out[0][row] = price;
			out[1][row] = BSMDeltaFromKernel(call, k);
			out[2][row] = BSMGammaFromKernel(k);
			out[3][row] = BSMVegaFromKernel(k);
			out[4][row] = BSMThetaFromKernel(call, k);
			out[5][row] = BSMRhoFromKernel(call, k);
			out[6][row] = k.d1;
			out[7][row] = k.d2;
			out[8][row] = intrinsic;
			out[9][row] = price - intrinsic;
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
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
	double lo = 1e-10;
	double hi = 5.0;
	while (price_fn(hi) < target && hi < 100.0) {
		hi *= 2.0;
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
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	auto delta = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[0]));
	auto gamma = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[1]));
	auto vega = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[2]));
	auto theta = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[3]));
	auto rho = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[4]));
	for (idx_t row = 0; row < args.size(); row++) {
		try {
			bool call = IsCallKind(input.GetString(0, row));
			double forward = input.GetDouble(1, row);
			double strike = input.GetDouble(2, row);
			double ttm = input.GetDouble(3, row);
			double rate = input.GetDouble(4, row);
			double vol = input.GetDouble(5, row);
			double df = std::exp(-rate * ttm);
			double st = vol * std::sqrt(ttm);
			double d1 = (std::log(forward / strike) + 0.5 * vol * vol * ttm) / st;
			double d2 = d1 - st;
			delta[row] = call ? df * NormCDF(d1) : -df * NormCDF(-d1);
			gamma[row] = df * NormPDF(d1) / (forward * st);
			vega[row] = df * forward * NormPDF(d1) * std::sqrt(ttm);
			double price = Black76Price(call, forward, strike, ttm, rate, vol);
			theta[row] = -forward * df * NormPDF(d1) * vol / (2.0 * std::sqrt(ttm)) + rate * price;
			rho[row] = -ttm * price;
			(void)d2;
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
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
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	auto delta = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[0]));
	auto gamma = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[1]));
	auto vega = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[2]));
	auto theta = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[3]));
	auto rho = FlatVector::GetDataMutable<double>(FINANCE_STRUCT_CHILD(children[4]));
	for (idx_t row = 0; row < args.size(); row++) {
		try {
			bool call = IsCallKind(input.GetString(0, row));
			double forward = input.GetDouble(1, row);
			double strike = input.GetDouble(2, row);
			double ttm = input.GetDouble(3, row);
			double rate = input.GetDouble(4, row);
			double normal_vol = input.GetDouble(5, row);
			double df = std::exp(-rate * ttm);
			double stddev = normal_vol * std::sqrt(ttm);
			double d = (forward - strike) / stddev;
			double price = BachelierPrice(call, forward, strike, ttm, rate, normal_vol);
			delta[row] = call ? df * NormCDF(d) : -df * NormCDF(-d);
			gamma[row] = df * NormPDF(d) / stddev;
			vega[row] = df * std::sqrt(ttm) * NormPDF(d);
			theta[row] = -0.5 * df * normal_vol * NormPDF(d) / std::sqrt(ttm) + rate * price;
			rho[row] = -ttm * price;
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
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

static void BarrierPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool call = IsCallKind(input.GetString(0, row));
		auto barrier_kind = Normalize(input.GetString(1, row));
		double spot = input.GetDouble(2, row);
		double strike = input.GetDouble(3, row);
		double barrier = input.GetDouble(4, row);
		idx_t offset = args.ColumnCount() >= 9 ? 1 : 0;
		double ttm = input.GetDouble(5 + offset, row);
		double rate = input.GetDouble(6 + offset, row);
		double vol = input.GetDouble(7 + offset, row);
		double q = args.ColumnCount() >= 10 ? input.GetDouble(9, row) : 0.0;
		bool knocked_out = (barrier_kind.find("down") != string::npos && spot <= barrier) ||
		                    (barrier_kind.find("up") != string::npos && spot >= barrier);
		double vanilla = BSMPrice(call, spot, strike, ttm, rate, vol, q);
		if (barrier_kind.find("out") != string::npos) {
			return knocked_out ? 0.0 : vanilla;
		}
		if (barrier_kind.find("in") != string::npos) {
			return knocked_out ? vanilla : 0.0;
		}
		throw InvalidInputException("Unknown barrier kind '%s'", barrier_kind);
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
