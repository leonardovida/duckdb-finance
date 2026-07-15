static void FinanceVersionFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	result.SetVectorType(VectorType::CONSTANT_VECTOR);
#ifdef EXT_VERSION_FINANCE
	string version = "finance ";
	version += EXT_VERSION_FINANCE;
#else
	string version = "finance-dev";
#endif
	ConstantVector::GetData<string_t>(result)[0] = StringVector::AddString(result, version);
}

static void UnaryDoubleFunction(DataChunk &args, ExpressionState &, Vector &result, double (*func)(double)) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		return func(input.GetDouble(0, row));
	});
}

static void BinaryDoubleFunction(DataChunk &args, ExpressionState &, Vector &result,
                                 double (*func)(double, double)) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		return func(input.GetDouble(0, row), input.GetDouble(1, row));
	});
}

static void NormPDFFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	UnaryDoubleFunction(args, state, result, NormPDF);
}
static void NormCDFFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	UnaryDoubleFunction(args, state, result, NormCDF);
}
static void NormInvFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	UnaryDoubleFunction(args, state, result, NormInv);
}
static void StudentTCdfFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	BinaryDoubleFunction(args, state, result, StudentTCDF);
}
static void StudentTInvFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	BinaryDoubleFunction(args, state, result, StudentTInv);
}
static void Chi2CdfFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	BinaryDoubleFunction(args, state, result, Chi2CDF);
}
static void Chi2InvFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	BinaryDoubleFunction(args, state, result, Chi2Inv);
}

static void SafeDivFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double den = input.GetDouble(1, row);
		if (den == 0.0) {
			if (args.ColumnCount() == 3) {
				return input.GetDouble(2, row);
			}
			return std::numeric_limits<double>::quiet_NaN();
		}
		return input.GetDouble(0, row) / den;
	});
}

static void BpsFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [](const PreparedInputs &input, idx_t row) { return input.GetDouble(0, row) * 10000.0; });
}

static void FromBpsFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [](const PreparedInputs &input, idx_t row) { return input.GetDouble(0, row) / 10000.0; });
}

static void ClipFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [](const PreparedInputs &input, idx_t row) {
		double x = input.GetDouble(0, row);
		double lower = input.GetDouble(1, row);
		double upper = input.GetDouble(2, row);
		if (lower > upper) {
			throw InvalidInputException("lower must be <= upper");
		}
		return std::min(std::max(x, lower), upper);
	});
}

static void RoundToTickFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double price = input.GetDouble(0, row);
		double tick = input.GetDouble(1, row);
		if (!(tick > 0.0)) {
			throw InvalidInputException("tick_size must be positive");
		}
		auto mode = args.ColumnCount() == 3 ? Normalize(input.GetString(2, row)) : "nearest";
		double scaled = price / tick;
		if (mode == "up" || mode == "ceil") {
			return std::ceil(scaled) * tick;
		}
		if (mode == "down" || mode == "floor") {
			return std::floor(scaled) * tick;
		}
		if (mode != "nearest" && mode != "round") {
			throw InvalidInputException("Unknown tick rounding mode '%s'", mode);
		}
		return std::round(scaled) * tick;
	});
}
