// Compensated sums operate on normalized inputs so neither accumulation nor
// intermediate squares overflow for otherwise finite observations.
static void AddCompensated(double value, double &sum, double &correction) {
	auto adjusted = value - correction;
	auto next = sum + adjusted;
	correction = (next - sum) - adjusted;
	sum = next;
}

template <class TRANSFORM>
static double CompensatedVectorSum(const vector<double> &values, const TRANSFORM &transform) {
	// Independent lanes shorten the recurrence dependency chain and allow SIMD
	// across lanes without reassociating any individual compensated sum.
	double sums[4] = {0.0, 0.0, 0.0, 0.0};
	double corrections[4] = {0.0, 0.0, 0.0, 0.0};
	idx_t i = 0;
	for (; i + 4 <= values.size(); i += 4) {
		AddCompensated(transform(values[i]), sums[0], corrections[0]);
		AddCompensated(transform(values[i + 1]), sums[1], corrections[1]);
		AddCompensated(transform(values[i + 2]), sums[2], corrections[2]);
		AddCompensated(transform(values[i + 3]), sums[3], corrections[3]);
	}
	for (; i < values.size(); i++) {
		AddCompensated(transform(values[i]), sums[0], corrections[0]);
	}
	double sum = 0.0, correction = 0.0;
	for (idx_t lane = 0; lane < 4; lane++) {
		AddCompensated(sums[lane], sum, correction);
		AddCompensated(-corrections[lane], sum, correction);
	}
	return sum;
}

static double ConvexCombination(double lower, double upper, double fraction) {
	if (fraction == 0.0) {
		return lower;
	}
	if (fraction == 1.0) {
		return upper;
	}
	if (std::signbit(lower) != std::signbit(upper)) {
		return (1.0 - fraction) * lower + fraction * upper;
	}
	return lower + fraction * (upper - lower);
}

static double ScaledRatio(double numerator, double numerator_scale, double denominator, double denominator_scale,
                          double multiplier) {
	if (numerator == 0.0) {
		return 0.0;
	}
	int a, b, c, d, e;
	auto mantissa = std::frexp(numerator, &a) * std::frexp(numerator_scale, &b) * std::frexp(multiplier, &e) /
	                (std::frexp(denominator, &c) * std::frexp(denominator_scale, &d));
	return std::ldexp(mantissa, a + b + e - c - d);
}
