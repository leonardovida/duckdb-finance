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
		if (!(lower <= upper)) {
			return FIN_NAN;
		}
		return std::min(std::max(x, lower), upper);
	});
}

//! Round to a tick grid. The price/tick quotient is first snapped to the nearest integer when it is within
//! 1e-9 relative of it, so on-grid prices such as 1.13 with tick 0.01 never move under 'up' or 'down'.
static double RoundToTick(double price, double tick, TickMode mode) {
	if (!IsFinite(price) || !IsFinite(tick) || !(tick > 0.0)) {
		return FIN_NAN;
	}
	double scaled = price / tick;
	double nearest = std::round(scaled);
	if (std::fabs(scaled - nearest) <= 1e-9 * std::max(1.0, std::fabs(scaled))) {
		scaled = nearest;
	}
	double steps;
	switch (mode) {
	case TickMode::UP:
		steps = std::ceil(scaled);
		break;
	case TickMode::DOWN:
		steps = std::floor(scaled);
		break;
	default:
		steps = std::round(scaled);
		break;
	}
	// Divide by the integer reciprocal for decimal ticks (0.01, 0.05, 0.25) so 113 ticks of 0.01 is exactly 1.13.
	double inverse = 1.0 / tick;
	double rounded_inverse = std::round(inverse);
	if (rounded_inverse >= 1.0 && std::fabs(inverse - rounded_inverse) <= 1e-9 * rounded_inverse) {
		return steps / rounded_inverse;
	}
	return steps * tick;
}

static void RoundToTickFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<TickMode> mode(args, 2, ParseTickMode, TickMode::NEAREST);
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		return RoundToTick(input.GetDouble(0, row), input.GetDouble(1, row), mode.Get(input, row));
	});
}
