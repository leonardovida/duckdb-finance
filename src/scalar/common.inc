constexpr double INV_SQRT_2PI = 0.398942280401432677939946059934381868;
constexpr double SQRT_2 = 1.414213562373095048801688724209698079;

static bool IsFinite(double value) {
	return std::isfinite(value);
}

static string Normalize(string input) {
	StringUtil::Trim(input);
	return StringUtil::Lower(input);
}

static bool IsAsciiSpace(char c) {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

static char LowerAscii(char c) {
	return c >= 'A' && c <= 'Z' ? char(c - 'A' + 'a') : c;
}

static bool IsCallKind(const string &kind) {
	idx_t begin = 0;
	idx_t end = kind.size();
	while (begin < end && IsAsciiSpace(kind[begin])) {
		begin++;
	}
	while (end > begin && IsAsciiSpace(kind[end - 1])) {
		end--;
	}
	const idx_t len = end - begin;
	if (len == 1) {
		const auto c = LowerAscii(kind[begin]);
		if (c == 'c') {
			return true;
		}
		if (c == 'p') {
			return false;
		}
	}
	if (len == 4 && LowerAscii(kind[begin]) == 'c' && LowerAscii(kind[begin + 1]) == 'a' &&
	    LowerAscii(kind[begin + 2]) == 'l' && LowerAscii(kind[begin + 3]) == 'l') {
		return true;
	}
	if (len == 3 && LowerAscii(kind[begin]) == 'p' && LowerAscii(kind[begin + 1]) == 'u' &&
	    LowerAscii(kind[begin + 2]) == 't') {
		return false;
	}
	auto normalized = Normalize(kind);
	if (normalized == "call" || normalized == "c") {
		return true;
	}
	if (normalized == "put" || normalized == "p") {
		return false;
	}
	throw InvalidInputException("Unknown option kind '%s'. Expected call/put/c/p", kind);
}

static string ParseOptionKind(const string &kind) {
	return IsCallKind(kind) ? "call" : "put";
}

static string ParseExerciseStyle(const string &style) {
	auto normalized = Normalize(style);
	if (normalized == "european" || normalized == "euro" || normalized == "eu") {
		return "european";
	}
	if (normalized == "american" || normalized == "amer" || normalized == "us") {
		return "american";
	}
	if (normalized == "bermudan" || normalized == "bermuda") {
		return "bermudan";
	}
	throw InvalidInputException("Unknown exercise style '%s'", style);
}

static string ParseReturnMethod(const string &method) {
	auto normalized = Normalize(method);
	if (normalized == "simple" || normalized == "simp" || normalized == "arithmetic") {
		return "simple";
	}
	if (normalized == "log" || normalized == "ln" || normalized == "continuous") {
		return "log";
	}
	throw InvalidInputException("Unknown return method '%s'", method);
}

static string ParseCompounding(const string &compounding) {
	auto normalized = Normalize(compounding);
	if (normalized == "continuous" || normalized == "cont" || normalized == "cc") {
		return "continuous";
	}
	if (normalized == "simple") {
		return "simple";
	}
	if (normalized == "periodic" || normalized == "annual" || normalized == "annually") {
		return "periodic";
	}
	if (normalized == "semiannual" || normalized == "semi-annually" || normalized == "semi") {
		return "semiannual";
	}
	if (normalized == "quarterly" || normalized == "quarter") {
		return "quarterly";
	}
	if (normalized == "monthly" || normalized == "month") {
		return "monthly";
	}
	if (normalized == "daily" || normalized == "day") {
		return "daily";
	}
	throw InvalidInputException("Unknown compounding convention '%s'", compounding);
}

static string ParseDayCount(const string &day_count) {
	auto normalized = Normalize(day_count);
	normalized = StringUtil::Replace(normalized, " ", "");
	if (normalized == "act/365f" || normalized == "actual/365fixed" || normalized == "act365f" ||
	    normalized == "actual365fixed") {
		return "ACT/365F";
	}
	if (normalized == "act/360" || normalized == "actual/360" || normalized == "act360") {
		return "ACT/360";
	}
	if (normalized == "act/act" || normalized == "actual/actual" || normalized == "actact") {
		return "ACT/ACT";
	}
	if (normalized == "30/360" || normalized == "bondbasis" || normalized == "30u/360") {
		return "30/360";
	}
	if (normalized == "30e/360" || normalized == "eurobondbasis") {
		return "30E/360";
	}
	throw InvalidInputException("Unknown day-count convention '%s'", day_count);
}

static int CompoundingFrequency(const string &compounding, int fallback) {
	auto normalized = ParseCompounding(compounding);
	if (normalized == "semiannual") {
		return 2;
	}
	if (normalized == "quarterly") {
		return 4;
	}
	if (normalized == "monthly") {
		return 12;
	}
	if (normalized == "daily") {
		return 365;
	}
	return fallback;
}

static double NormPDF(double x) {
	return INV_SQRT_2PI * std::exp(-0.5 * x * x);
}

static double NormCDF(double x) {
	return 0.5 * std::erfc(-x / SQRT_2);
}

static double NormInv(double p) {
	if (!(p > 0.0 && p < 1.0)) {
		throw InvalidInputException("fin_norm_inv requires 0 < p < 1");
	}

	// Peter J. Acklam's rational approximation.
	const double a1 = -3.969683028665376e+01;
	const double a2 = 2.209460984245205e+02;
	const double a3 = -2.759285104469687e+02;
	const double a4 = 1.383577518672690e+02;
	const double a5 = -3.066479806614716e+01;
	const double a6 = 2.506628277459239e+00;

	const double b1 = -5.447609879822406e+01;
	const double b2 = 1.615858368580409e+02;
	const double b3 = -1.556989798598866e+02;
	const double b4 = 6.680131188771972e+01;
	const double b5 = -1.328068155288572e+01;

	const double c1 = -7.784894002430293e-03;
	const double c2 = -3.223964580411365e-01;
	const double c3 = -2.400758277161838e+00;
	const double c4 = -2.549732539343734e+00;
	const double c5 = 4.374664141464968e+00;
	const double c6 = 2.938163982698783e+00;

	const double d1 = 7.784695709041462e-03;
	const double d2 = 3.224671290700398e-01;
	const double d3 = 2.445134137142996e+00;
	const double d4 = 3.754408661907416e+00;

	const double plow = 0.02425;
	const double phigh = 1.0 - plow;
	double q;
	double x;

	if (p < plow) {
		q = std::sqrt(-2.0 * std::log(p));
		x = (((((c1 * q + c2) * q + c3) * q + c4) * q + c5) * q + c6) /
		    ((((d1 * q + d2) * q + d3) * q + d4) * q + 1.0);
	} else if (p <= phigh) {
		q = p - 0.5;
		const double r = q * q;
		x = (((((a1 * r + a2) * r + a3) * r + a4) * r + a5) * r + a6) * q /
		    (((((b1 * r + b2) * r + b3) * r + b4) * r + b5) * r + 1.0);
	} else {
		q = std::sqrt(-2.0 * std::log(1.0 - p));
		x = -(((((c1 * q + c2) * q + c3) * q + c4) * q + c5) * q + c6) /
		    ((((d1 * q + d2) * q + d3) * q + d4) * q + 1.0);
	}

	// One Halley refinement gives near double precision for typical finance use.
	const double err = NormCDF(x) - p;
	const double u = err / NormPDF(x);
	return x - u / (1.0 + 0.5 * x * u);
}

static double Betacf(double a, double b, double x) {
	constexpr int MAX_ITER = 200;
	constexpr double EPS = 3e-14;
	constexpr double FPMIN = 1e-300;
	double qab = a + b;
	double qap = a + 1.0;
	double qam = a - 1.0;
	double c = 1.0;
	double d = 1.0 - qab * x / qap;
	if (std::fabs(d) < FPMIN) {
		d = FPMIN;
	}
	d = 1.0 / d;
	double h = d;
	for (int m = 1; m <= MAX_ITER; m++) {
		int m2 = 2 * m;
		double aa = m * (b - m) * x / ((qam + m2) * (a + m2));
		d = 1.0 + aa * d;
		if (std::fabs(d) < FPMIN) {
			d = FPMIN;
		}
		c = 1.0 + aa / c;
		if (std::fabs(c) < FPMIN) {
			c = FPMIN;
		}
		d = 1.0 / d;
		h *= d * c;
		aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
		d = 1.0 + aa * d;
		if (std::fabs(d) < FPMIN) {
			d = FPMIN;
		}
		c = 1.0 + aa / c;
		if (std::fabs(c) < FPMIN) {
			c = FPMIN;
		}
		d = 1.0 / d;
		double del = d * c;
		h *= del;
		if (std::fabs(del - 1.0) <= EPS) {
			break;
		}
	}
	return h;
}

static double RegularizedBeta(double a, double b, double x) {
	if (x < 0.0 || x > 1.0 || a <= 0.0 || b <= 0.0) {
		throw InvalidInputException("Invalid regularized beta input");
	}
	if (x == 0.0 || x == 1.0) {
		return x;
	}
	double bt = std::exp(std::lgamma(a + b) - std::lgamma(a) - std::lgamma(b) + a * std::log(x) +
	                     b * std::log(1.0 - x));
	if (x < (a + 1.0) / (a + b + 2.0)) {
		return bt * Betacf(a, b, x) / a;
	}
	return 1.0 - bt * Betacf(b, a, 1.0 - x) / b;
}

static double RegularizedGammaP(double a, double x) {
	if (a <= 0.0 || x < 0.0) {
		throw InvalidInputException("Invalid regularized gamma input");
	}
	if (x == 0.0) {
		return 0.0;
	}
	constexpr int MAX_ITER = 200;
	constexpr double EPS = 1e-14;
	constexpr double FPMIN = 1e-300;
	const double gln = std::lgamma(a);
	if (x < a + 1.0) {
		double ap = a;
		double sum = 1.0 / a;
		double del = sum;
		for (int n = 1; n <= MAX_ITER; n++) {
			ap += 1.0;
			del *= x / ap;
			sum += del;
			if (std::fabs(del) < std::fabs(sum) * EPS) {
				return sum * std::exp(-x + a * std::log(x) - gln);
			}
		}
		return sum * std::exp(-x + a * std::log(x) - gln);
	}
	double b = x + 1.0 - a;
	double c = 1.0 / FPMIN;
	double d = 1.0 / b;
	double h = d;
	for (int i = 1; i <= MAX_ITER; i++) {
		double an = -i * (i - a);
		b += 2.0;
		d = an * d + b;
		if (std::fabs(d) < FPMIN) {
			d = FPMIN;
		}
		c = b + an / c;
		if (std::fabs(c) < FPMIN) {
			c = FPMIN;
		}
		d = 1.0 / d;
		double del = d * c;
		h *= del;
		if (std::fabs(del - 1.0) < EPS) {
			break;
		}
	}
	return 1.0 - std::exp(-x + a * std::log(x) - gln) * h;
}

static double StudentTCDF(double x, double df) {
	if (!(df > 0.0) || !IsFinite(x)) {
		throw InvalidInputException("Student-t CDF requires finite x and df > 0");
	}
	double t = df / (df + x * x);
	double ib = RegularizedBeta(0.5 * df, 0.5, t);
	return x >= 0.0 ? 1.0 - 0.5 * ib : 0.5 * ib;
}

static double Chi2CDF(double x, double df) {
	if (!(df > 0.0)) {
		throw InvalidInputException("Chi-square CDF requires df > 0");
	}
	if (x < 0.0) {
		return 0.0;
	}
	return RegularizedGammaP(0.5 * df, 0.5 * x);
}

template <class CDF>
static double InvertMonotone(double p, double lower, double upper, CDF cdf) {
	if (!(p > 0.0 && p < 1.0)) {
		throw InvalidInputException("Inverse CDF requires 0 < p < 1");
	}
	for (idx_t i = 0; i < 200 && cdf(upper) < p; i++) {
		upper *= 2.0;
	}
	for (idx_t i = 0; i < 200; i++) {
		double mid = 0.5 * (lower + upper);
		double value = cdf(mid);
		if (std::fabs(value - p) < 1e-12) {
			return mid;
		}
		if (value < p) {
			lower = mid;
		} else {
			upper = mid;
		}
	}
	return 0.5 * (lower + upper);
}

static double StudentTInv(double p, double df) {
	if (!(df > 0.0)) {
		throw InvalidInputException("Student-t inverse requires df > 0");
	}
	return InvertMonotone(p, -64.0, 64.0, [&](double x) { return StudentTCDF(x, df); });
}

static double Chi2Inv(double p, double df) {
	if (!(df > 0.0)) {
		throw InvalidInputException("Chi-square inverse requires df > 0");
	}
	return InvertMonotone(p, 0.0, std::max(1.0, df), [&](double x) { return Chi2CDF(x, df); });
}

static double YearFrac(date_t start, date_t end, const string &convention) {
	auto day_count = ParseDayCount(convention);
	const int32_t days = end.days - start.days;
	if (day_count == "ACT/365F") {
		return double(days) / 365.0;
	}
	if (day_count == "ACT/360") {
		return double(days) / 360.0;
	}
	if (day_count == "ACT/ACT") {
		int32_t sy, sm, sd;
		int32_t ey, em, ed;
		Date::Convert(start, sy, sm, sd);
		Date::Convert(end, ey, em, ed);
		if (sy == ey) {
			return double(days) / (Date::IsLeapYear(sy) ? 366.0 : 365.0);
		}
		double result = 0.0;
		auto start_next_year = Date::FromDate(sy + 1, 1, 1);
		result += double(start_next_year.days - start.days) / (Date::IsLeapYear(sy) ? 366.0 : 365.0);
		for (int32_t y = sy + 1; y < ey; y++) {
			result += 1.0;
		}
		auto end_year_start = Date::FromDate(ey, 1, 1);
		result += double(end.days - end_year_start.days) / (Date::IsLeapYear(ey) ? 366.0 : 365.0);
		return result;
	}
	int32_t sy, sm, sd;
	int32_t ey, em, ed;
	Date::Convert(start, sy, sm, sd);
	Date::Convert(end, ey, em, ed);
	if (day_count == "30E/360") {
		sd = std::min(sd, 30);
		ed = std::min(ed, 30);
	} else {
		if (sd == 31) {
			sd = 30;
		}
		if (ed == 31 && sd == 30) {
			ed = 30;
		}
	}
	return double((ey - sy) * 360 + (em - sm) * 30 + (ed - sd)) / 360.0;
}

static double DiscountFactor(double rate, double ttm, const string &compounding, int frequency) {
	if (!IsFinite(rate) || !IsFinite(ttm) || ttm < 0.0) {
		throw InvalidInputException("Invalid discount factor input");
	}
	auto normalized = ParseCompounding(compounding);
	frequency = CompoundingFrequency(compounding, frequency);
	if (normalized == "continuous") {
		return std::exp(-rate * ttm);
	}
	if (normalized == "simple") {
		return 1.0 / (1.0 + rate * ttm);
	}
	if (frequency <= 0) {
		throw InvalidInputException("Periodic compounding requires frequency > 0");
	}
	return std::pow(1.0 + rate / frequency, -frequency * ttm);
}

static double RateFromDiscount(double df, double ttm, const string &compounding, int frequency) {
	if (!(df > 0.0) || !(ttm > 0.0)) {
		throw InvalidInputException("fin_rate_from_discount requires df > 0 and ttm > 0");
	}
	auto normalized = ParseCompounding(compounding);
	frequency = CompoundingFrequency(compounding, frequency);
	if (normalized == "continuous") {
		return -std::log(df) / ttm;
	}
	if (normalized == "simple") {
		return (1.0 / df - 1.0) / ttm;
	}
	if (frequency <= 0) {
		throw InvalidInputException("Periodic compounding requires frequency > 0");
	}
	return frequency * (std::pow(df, -1.0 / (frequency * ttm)) - 1.0);
}

static double ForwardRate(double df1, double df2, double t1, double t2, const string &compounding) {
	if (!(df1 > 0.0) || !(df2 > 0.0) || !(t2 > t1)) {
		throw InvalidInputException("Invalid forward-rate input");
	}
	double forward_df = df2 / df1;
	return RateFromDiscount(forward_df, t2 - t1, compounding, 1);
}

static double PresentValue(double cashflow, double rate, double ttm, const string &compounding) {
	return cashflow * DiscountFactor(rate, ttm, compounding, 1);
}

static double FutureValue(double pv, double rate, double ttm, const string &compounding) {
	double df = DiscountFactor(rate, ttm, compounding, 1);
	return pv / df;
}

static double BondPrice(double coupon_rate, double ytm, double maturity_years, int frequency, double face) {
	if (!(maturity_years > 0.0) || frequency <= 0 || !(face > 0.0)) {
		throw InvalidInputException("Invalid bond input");
	}
	int periods = int(std::round(maturity_years * frequency));
	double coupon = face * coupon_rate / frequency;
	double period_df = 1.0 / (1.0 + ytm / frequency);
	double discount = period_df;
	double price = 0.0;
	for (int i = 1; i <= periods; i++) {
		price += coupon * discount;
		discount *= period_df;
	}
	price += face * (discount / period_df);
	return price;
}

static double BondYTM(double price, double coupon_rate, double maturity_years, int frequency, double face) {
	if (!(price > 0.0)) {
		throw InvalidInputException("Bond price must be positive");
	}
	double lo = -0.9999 * frequency;
	double hi = 1.0;
	while (BondPrice(coupon_rate, hi, maturity_years, frequency, face) > price) {
		hi *= 2.0;
		if (hi > 100.0) {
			break;
		}
	}
	for (idx_t i = 0; i < 200; i++) {
		double mid = 0.5 * (lo + hi);
		double p = BondPrice(coupon_rate, mid, maturity_years, frequency, face);
		if (std::fabs(p - price) < 1e-12) {
			return mid;
		}
		if (p > price) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	return 0.5 * (lo + hi);
}

static double BondDuration(double coupon_rate, double ytm, double maturity_years, int frequency, double face,
                           const string &kind) {
	int periods = int(std::round(maturity_years * frequency));
	double coupon = face * coupon_rate / frequency;
	double price = BondPrice(coupon_rate, ytm, maturity_years, frequency, face);
	double weighted = 0.0;
	double period_df = 1.0 / (1.0 + ytm / frequency);
	double discount = period_df;
	for (int i = 1; i <= periods; i++) {
		double cf = coupon + (i == periods ? face : 0.0);
		double t = double(i) / frequency;
		weighted += t * cf * discount;
		discount *= period_df;
	}
	double macaulay = weighted / price;
	auto normalized = Normalize(kind);
	if (normalized == "modified" || normalized == "mod") {
		return macaulay / (1.0 + ytm / frequency);
	}
	return macaulay;
}

static double BondConvexity(double coupon_rate, double ytm, double maturity_years, int frequency, double face) {
	int periods = int(std::round(maturity_years * frequency));
	double coupon = face * coupon_rate / frequency;
	double price = BondPrice(coupon_rate, ytm, maturity_years, frequency, face);
	double convexity = 0.0;
	double period_df = 1.0 / (1.0 + ytm / frequency);
	double discount_i_plus_2 = period_df * period_df * period_df;
	for (int i = 1; i <= periods; i++) {
		double cf = coupon + (i == periods ? face : 0.0);
		convexity += cf * i * (i + 1) * discount_i_plus_2;
		discount_i_plus_2 *= period_df;
	}
	return convexity / (price * frequency * frequency);
}

static double OptionPayoff(bool call, double spot, double strike) {
	if (!IsFinite(spot) || !IsFinite(strike)) {
		throw InvalidInputException("Invalid option payoff input");
	}
	return call ? std::max(spot - strike, 0.0) : std::max(strike - spot, 0.0);
}

static double ForwardPrice(double spot, double ttm, double rate, double dividend_yield) {
	if (!(spot >= 0.0) || ttm < 0.0 || !IsFinite(rate) || !IsFinite(dividend_yield)) {
		throw InvalidInputException("Invalid forward price input");
	}
	return spot * std::exp((rate - dividend_yield) * ttm);
}

struct BSMKernel {
	double spot;
	double strike;
	double ttm;
	double rate;
	double vol;
	double dividend_yield;
	double sqrt_ttm;
	double st;
	double d1;
	double d2;
	double df_rate;
	double df_dividend;
	double pdf_d1;
};

static BSMKernel MakeBSMKernel(double spot, double strike, double ttm, double rate, double vol, double dividend_yield) {
	if (!(spot > 0.0) || !(strike > 0.0) || !(ttm > 0.0) || !(vol > 0.0)) {
		throw InvalidInputException("BSM requires spot > 0, strike > 0, ttm > 0, and vol > 0");
	}
	BSMKernel k;
	k.spot = spot;
	k.strike = strike;
	k.ttm = ttm;
	k.rate = rate;
	k.vol = vol;
	k.dividend_yield = dividend_yield;
	k.sqrt_ttm = std::sqrt(ttm);
	k.st = vol * k.sqrt_ttm;
	k.d1 = (std::log(spot / strike) + (rate - dividend_yield + 0.5 * vol * vol) * ttm) / k.st;
	k.d2 = k.d1 - k.st;
	k.df_rate = std::exp(-rate * ttm);
	k.df_dividend = std::exp(-dividend_yield * ttm);
	k.pdf_d1 = NormPDF(k.d1);
	return k;
}

static double BSMPriceFromKernel(bool call, const BSMKernel &k) {
	if (call) {
		return k.spot * k.df_dividend * NormCDF(k.d1) - k.strike * k.df_rate * NormCDF(k.d2);
	}
	return k.strike * k.df_rate * NormCDF(-k.d2) - k.spot * k.df_dividend * NormCDF(-k.d1);
}

static double BSMDeltaFromKernel(bool call, const BSMKernel &k) {
	return call ? k.df_dividend * NormCDF(k.d1) : k.df_dividend * (NormCDF(k.d1) - 1.0);
}

static double BSMGammaFromKernel(const BSMKernel &k) {
	return k.df_dividend * k.pdf_d1 / (k.spot * k.st);
}

static double BSMVegaFromKernel(const BSMKernel &k) {
	return k.spot * k.df_dividend * k.pdf_d1 * k.sqrt_ttm;
}

static double BSMThetaFromKernel(bool call, const BSMKernel &k) {
	double first = -k.spot * k.df_dividend * k.pdf_d1 * k.vol / (2.0 * k.sqrt_ttm);
	if (call) {
		return first - k.rate * k.strike * k.df_rate * NormCDF(k.d2) +
		       k.dividend_yield * k.spot * k.df_dividend * NormCDF(k.d1);
	}
	return first + k.rate * k.strike * k.df_rate * NormCDF(-k.d2) -
	       k.dividend_yield * k.spot * k.df_dividend * NormCDF(-k.d1);
}

static double BSMRhoFromKernel(bool call, const BSMKernel &k) {
	if (call) {
		return k.strike * k.ttm * k.df_rate * NormCDF(k.d2);
	}
	return -k.strike * k.ttm * k.df_rate * NormCDF(-k.d2);
}

static double BSMD1(double spot, double strike, double ttm, double rate, double vol, double dividend_yield) {
	return MakeBSMKernel(spot, strike, ttm, rate, vol, dividend_yield).d1;
}

static double BSMD2(double spot, double strike, double ttm, double rate, double vol, double dividend_yield) {
	return MakeBSMKernel(spot, strike, ttm, rate, vol, dividend_yield).d2;
}

static double BSMPrice(bool call, double spot, double strike, double ttm, double rate, double vol,
                       double dividend_yield) {
	if (ttm == 0.0 || vol == 0.0) {
		double forward_intrinsic = call ? spot * std::exp(-dividend_yield * ttm) - strike * std::exp(-rate * ttm)
		                                : strike * std::exp(-rate * ttm) - spot * std::exp(-dividend_yield * ttm);
		return std::max(forward_intrinsic, 0.0);
	}
	return BSMPriceFromKernel(call, MakeBSMKernel(spot, strike, ttm, rate, vol, dividend_yield));
}

static double BSMDelta(bool call, double spot, double strike, double ttm, double rate, double vol,
                       double dividend_yield) {
	return BSMDeltaFromKernel(call, MakeBSMKernel(spot, strike, ttm, rate, vol, dividend_yield));
}

static double BSMGamma(double spot, double strike, double ttm, double rate, double vol, double dividend_yield) {
	return BSMGammaFromKernel(MakeBSMKernel(spot, strike, ttm, rate, vol, dividend_yield));
}

static double BSMVega(double spot, double strike, double ttm, double rate, double vol, double dividend_yield) {
	return BSMVegaFromKernel(MakeBSMKernel(spot, strike, ttm, rate, vol, dividend_yield));
}

static double BSMTheta(bool call, double spot, double strike, double ttm, double rate, double vol,
                       double dividend_yield) {
	return BSMThetaFromKernel(call, MakeBSMKernel(spot, strike, ttm, rate, vol, dividend_yield));
}

static double BSMRho(bool call, double spot, double strike, double ttm, double rate, double vol,
                     double dividend_yield) {
	return BSMRhoFromKernel(call, MakeBSMKernel(spot, strike, ttm, rate, vol, dividend_yield));
}

static double BSMImpliedVol(bool call, double price, double spot, double strike, double ttm, double rate,
                            double dividend_yield, double tolerance, int max_iter) {
	if (!(price >= 0.0) || !(spot > 0.0) || !(strike > 0.0) || !(ttm > 0.0)) {
		throw InvalidInputException("Invalid implied-vol input");
	}
	double intrinsic = BSMPrice(call, spot, strike, ttm, rate, 1e-12, dividend_yield);
	if (price < intrinsic - 1e-10) {
		throw InvalidInputException("Option price is below no-arbitrage intrinsic value");
	}
	double lo = 1e-8;
	double hi = 5.0;
	while (BSMPrice(call, spot, strike, ttm, rate, hi, dividend_yield) < price && hi < 100.0) {
		hi *= 2.0;
	}
	double guess = 0.5 * (lo + hi);
	for (int i = 0; i < max_iter; i++) {
		double value = BSMPrice(call, spot, strike, ttm, rate, guess, dividend_yield);
		if (std::fabs(value - price) < tolerance) {
			return guess;
		}
		if (value < price) {
			lo = guess;
		} else {
			hi = guess;
		}
		double next = 0.5 * (lo + hi);
		try {
			double vega = BSMVega(spot, strike, ttm, rate, guess, dividend_yield);
			double newton = guess - (value - price) / vega;
			if (std::isfinite(newton) && newton > lo && newton < hi) {
				next = newton;
			}
		} catch (const std::exception &) {
		}
		guess = next;
	}
	return 0.5 * (lo + hi);
}

static double Black76Price(bool call, double forward, double strike, double ttm, double rate, double vol) {
	if (!(forward > 0.0) || !(strike > 0.0) || !(ttm >= 0.0) || !(vol >= 0.0)) {
		throw InvalidInputException("Invalid Black-76 input");
	}
	if (ttm == 0.0 || vol == 0.0) {
		return std::exp(-rate * ttm) * OptionPayoff(call, forward, strike);
	}
	double st = vol * std::sqrt(ttm);
	double d1 = (std::log(forward / strike) + 0.5 * vol * vol * ttm) / st;
	double d2 = d1 - st;
	double df = std::exp(-rate * ttm);
	return call ? df * (forward * NormCDF(d1) - strike * NormCDF(d2))
	            : df * (strike * NormCDF(-d2) - forward * NormCDF(-d1));
}

static double BachelierPrice(bool call, double forward, double strike, double ttm, double rate, double normal_vol) {
	if (!(ttm >= 0.0) || !(normal_vol >= 0.0)) {
		throw InvalidInputException("Invalid Bachelier input");
	}
	double df = std::exp(-rate * ttm);
	if (ttm == 0.0 || normal_vol == 0.0) {
		return df * OptionPayoff(call, forward, strike);
	}
	double stddev = normal_vol * std::sqrt(ttm);
	double d = (forward - strike) / stddev;
	double undiscounted = call ? (forward - strike) * NormCDF(d) + stddev * NormPDF(d)
	                           : (strike - forward) * NormCDF(-d) + stddev * NormPDF(d);
	return df * undiscounted;
}

static double BinomialPrice(bool call, double spot, double strike, double ttm, double rate, double vol,
                            double dividend_yield, int steps, const string &exercise, const string &tree) {
	if (steps <= 0 || !(spot > 0.0) || !(strike > 0.0) || !(ttm >= 0.0) || !(vol >= 0.0)) {
		throw InvalidInputException("Invalid binomial option input");
	}
	if (ttm == 0.0 || vol == 0.0) {
		return OptionPayoff(call, spot, strike);
	}
	const bool american = ParseExerciseStyle(exercise) == "american";
	auto normalized_tree = Normalize(tree);
	double dt = ttm / steps;
	double u;
	double d;
	double p;
	if (normalized_tree == "jr" || normalized_tree == "jarrow-rudd") {
		double drift = (rate - dividend_yield - 0.5 * vol * vol) * dt;
		u = std::exp(drift + vol * std::sqrt(dt));
		d = std::exp(drift - vol * std::sqrt(dt));
		p = 0.5;
	} else {
		u = std::exp(vol * std::sqrt(dt));
		d = 1.0 / u;
		p = (std::exp((rate - dividend_yield) * dt) - d) / (u - d);
	}
	if (p < 0.0 || p > 1.0) {
		throw InvalidInputException("Invalid binomial risk-neutral probability");
	}
	vector<double> values(steps + 1);
	const double down_over_up = d / u;
	double s = spot * std::pow(u, steps);
	for (int i = 0; i <= steps; i++) {
		values[i] = OptionPayoff(call, s, strike);
		s *= down_over_up;
	}
	double disc = std::exp(-rate * dt);
	double american_start = american ? spot * std::pow(u, steps - 1) : 0.0;
	for (int step = steps - 1; step >= 0; step--) {
		double american_spot = american_start;
		for (int i = 0; i <= step; i++) {
			double continuation = disc * (p * values[i] + (1.0 - p) * values[i + 1]);
			if (american) {
				values[i] = std::max(continuation, OptionPayoff(call, american_spot, strike));
				american_spot *= down_over_up;
			} else {
				values[i] = continuation;
			}
		}
		if (american) {
			american_start /= u;
		}
	}
	return values[0];
}

static double SABRVol(double forward, double strike, double ttm, double alpha, double beta, double rho, double nu,
                      double shift) {
	forward += shift;
	strike += shift;
	if (!(forward > 0.0) || !(strike > 0.0) || !(alpha > 0.0) || beta < 0.0 || beta > 1.0 ||
	    std::fabs(rho) >= 1.0 || nu < 0.0 || ttm < 0.0) {
		throw InvalidInputException("Invalid SABR input");
	}
	double one_minus_beta = 1.0 - beta;
	if (std::fabs(forward - strike) < 1e-12) {
		double fk_beta = std::pow(forward, one_minus_beta);
		double correction = ((one_minus_beta * one_minus_beta * alpha * alpha) / (24.0 * fk_beta * fk_beta) +
		                     (rho * beta * nu * alpha) / (4.0 * fk_beta) +
		                     (2.0 - 3.0 * rho * rho) * nu * nu / 24.0) *
		                    ttm;
		return alpha / fk_beta * (1.0 + correction);
	}
	double fk = forward * strike;
	double log_fk = std::log(forward / strike);
	double fk_beta = std::pow(fk, 0.5 * one_minus_beta);
	double z = (nu / alpha) * fk_beta * log_fk;
	double xz = std::log((std::sqrt(1.0 - 2.0 * rho * z + z * z) + z - rho) / (1.0 - rho));
	double denom = fk_beta * (1.0 + one_minus_beta * one_minus_beta * log_fk * log_fk / 24.0 +
	                          std::pow(one_minus_beta, 4) * std::pow(log_fk, 4) / 1920.0);
	double correction = ((one_minus_beta * one_minus_beta * alpha * alpha) / (24.0 * fk_beta * fk_beta) +
	                     (rho * beta * nu * alpha) / (4.0 * fk_beta) +
	                     (2.0 - 3.0 * rho * rho) * nu * nu / 24.0) *
	                    ttm;
	return (alpha / denom) * (z / xz) * (1.0 + correction);
}

static double SviTotalVariance(double k, double a, double b, double rho, double m, double sigma) {
	if (!(b >= 0.0) || std::fabs(rho) >= 1.0 || !(sigma > 0.0)) {
		throw InvalidInputException("Invalid SVI input");
	}
	return a + b * (rho * (k - m) + std::sqrt((k - m) * (k - m) + sigma * sigma));
}

static bool IsBusinessDay(date_t date) {
	int32_t iso_day = Date::ExtractISODayOfTheWeek(date);
	return iso_day >= 1 && iso_day <= 5;
}

struct PreparedInputs {
	explicit PreparedInputs(DataChunk &args) : formats(args.ColumnCount()) {
		for (idx_t col = 0; col < args.ColumnCount(); col++) {
			FinanceToUnifiedFormat(args.data[col], args.size(), formats[col]);
			if (formats[col].validity.CanHaveNull()) {
				nullable_cols.push_back(col);
			}
		}
	}
	vector<UnifiedVectorFormat> formats;
	vector<idx_t> nullable_cols;

	bool IsNull(idx_t col, idx_t row) const {
		auto &format = formats[col];
		auto idx = format.sel->get_index(row);
		return !format.validity.RowIsValid(idx);
	}

	bool HasNull(idx_t row) const {
		for (auto col : nullable_cols) {
			if (IsNull(col, row)) {
				return true;
			}
		}
		return false;
	}

	bool HasNull(idx_t row, idx_t col_count) const {
		for (auto col : nullable_cols) {
			if (col >= col_count) {
				continue;
			}
			if (IsNull(col, row)) {
				return true;
			}
		}
		return false;
	}

	double GetDouble(idx_t col, idx_t row) const {
		auto &format = formats[col];
		auto idx = format.sel->get_index(row);
		auto data = UnifiedVectorFormat::GetData<double>(format);
		return data[idx];
	}

	int32_t GetInt32(idx_t col, idx_t row) const {
		auto &format = formats[col];
		auto idx = format.sel->get_index(row);
		auto data = UnifiedVectorFormat::GetData<int32_t>(format);
		return data[idx];
	}

	int64_t GetInt64(idx_t col, idx_t row) const {
		auto &format = formats[col];
		auto idx = format.sel->get_index(row);
		auto data = UnifiedVectorFormat::GetData<int64_t>(format);
		return data[idx];
	}

	bool GetBool(idx_t col, idx_t row) const {
		auto &format = formats[col];
		auto idx = format.sel->get_index(row);
		auto data = UnifiedVectorFormat::GetData<bool>(format);
		return data[idx];
	}

	date_t GetDate(idx_t col, idx_t row) const {
		auto &format = formats[col];
		auto idx = format.sel->get_index(row);
		auto data = UnifiedVectorFormat::GetData<date_t>(format);
		return data[idx];
	}

	timestamp_t GetTimestamp(idx_t col, idx_t row) const {
		auto &format = formats[col];
		auto idx = format.sel->get_index(row);
		auto data = UnifiedVectorFormat::GetData<timestamp_t>(format);
		return data[idx];
	}

	string GetString(idx_t col, idx_t row) const {
		auto &format = formats[col];
		auto idx = format.sel->get_index(row);
		auto data = UnifiedVectorFormat::GetData<string_t>(format);
		return data[idx].GetString();
	}
};

template <class FUNC>
static void ExecuteDouble(DataChunk &args, Vector &result, FUNC func) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<double>(result);
	PreparedInputs inputs(args);
	for (idx_t row = 0; row < args.size(); row++) {
		if (inputs.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			output[row] = func(inputs, row);
			if (!std::isfinite(output[row])) {
				FlatVector::SetNull(result, row, true);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

template <class FUNC>
static void ExecuteBool(DataChunk &args, Vector &result, FUNC func) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<bool>(result);
	PreparedInputs inputs(args);
	for (idx_t row = 0; row < args.size(); row++) {
		if (inputs.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			output[row] = func(inputs, row);
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

template <class FUNC>
static void ExecuteString(DataChunk &args, Vector &result, FUNC func) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<string_t>(result);
	PreparedInputs inputs(args);
	for (idx_t row = 0; row < args.size(); row++) {
		if (inputs.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			output[row] = StringVector::AddString(result, func(inputs, row));
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static vector<double> ReadDoubleList(Vector &list_vec, const list_entry_t &entry) {
	auto list_size = ListVector::GetListSize(list_vec);
	auto &child = ListVector::GetChildMutable(list_vec);
	FinanceFlatten(child, list_size);
	auto &validity = FlatVector::Validity(child);
	auto data = FlatVector::GetData<double>(child);
	vector<double> result;
	result.reserve(entry.length);
	for (idx_t i = 0; i < entry.length; i++) {
		if (validity.CanHaveNull() && !validity.RowIsValid(entry.offset + i)) {
			throw InvalidInputException("Finance list functions do not accept NULL list elements");
		}
		result.push_back(data[entry.offset + i]);
	}
	return result;
}

static void ValidateListEntryNoNull(const ValidityMask &validity, const list_entry_t &entry, const string &message) {
	if (!validity.CanHaveNull()) {
		return;
	}
	for (idx_t i = 0; i < entry.length; i++) {
		if (!validity.RowIsValid(entry.offset + i)) {
			throw InvalidInputException(message);
		}
	}
}

static vector<vector<double>> ReadDoubleMatrix(Vector &matrix_vec, const list_entry_t &entry) {
	auto outer_size = ListVector::GetListSize(matrix_vec);
	auto &inner_vec = ListVector::GetChildMutable(matrix_vec);
	FinanceFlatten(inner_vec, outer_size);
	ValidateListEntryNoNull(FlatVector::Validity(inner_vec), entry, "Matrix rows must not be NULL");
	auto inner_entries = FlatVector::GetData<list_entry_t>(inner_vec);
	vector<vector<double>> matrix;
	matrix.reserve(entry.length);
	for (idx_t i = 0; i < entry.length; i++) {
		matrix.push_back(ReadDoubleList(inner_vec, inner_entries[entry.offset + i]));
	}
	if (!matrix.empty()) {
		auto cols = matrix[0].size();
		for (auto &row : matrix) {
			if (row.size() != cols) {
				throw InvalidInputException("Matrix rows must have consistent length");
			}
		}
	}
	return matrix;
}

static void WriteDoubleLists(Vector &result, const vector<vector<double>> &lists, idx_t count) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	idx_t total = 0;
	for (auto &list : lists) {
		total += list.size();
	}
	ListVector::Reserve(result, total);
	auto &child = ListVector::GetChildMutable(result);
	auto child_data = FlatVector::GetDataMutable<double>(child);
	auto result_entries = FlatVector::GetDataMutable<list_entry_t>(result);
	idx_t offset = 0;
	for (idx_t row = 0; row < count; row++) {
		auto &list = lists[row];
		result_entries[row] = list_entry_t(offset, list.size());
		for (idx_t i = 0; i < list.size(); i++) {
			child_data[offset + i] = list[i];
		}
		offset += list.size();
	}
	ListVector::SetListSize(result, total);
}

static void WriteDoubleMatrices(Vector &result, const vector<vector<vector<double>>> &matrices, idx_t count) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	idx_t total_rows = 0;
	idx_t total_values = 0;
	for (auto &matrix : matrices) {
		total_rows += matrix.size();
		for (auto &row : matrix) {
			total_values += row.size();
		}
	}
	ListVector::Reserve(result, total_rows);
	auto &row_vector = ListVector::GetChildMutable(result);
	ListVector::Reserve(row_vector, total_values);
	auto &value_vector = ListVector::GetChildMutable(row_vector);
	auto result_entries = FlatVector::GetDataMutable<list_entry_t>(result);
	auto row_entries = FlatVector::GetDataMutable<list_entry_t>(row_vector);
	auto values = FlatVector::GetDataMutable<double>(value_vector);

	idx_t row_offset = 0;
	idx_t value_offset = 0;
	for (idx_t outer = 0; outer < count; outer++) {
		auto &matrix = matrices[outer];
		result_entries[outer] = list_entry_t(row_offset, matrix.size());
		for (auto &matrix_row : matrix) {
			row_entries[row_offset++] = list_entry_t(value_offset, matrix_row.size());
			for (auto value : matrix_row) {
				values[value_offset++] = value;
			}
		}
	}
	ListVector::SetListSize(result, total_rows);
	ListVector::SetListSize(row_vector, total_values);
}

static double Dot(const vector<double> &x, const vector<double> &y) {
	if (x.size() != y.size()) {
		throw InvalidInputException("Vector lengths must match");
	}
	double sum = 0.0;
	double c = 0.0;
	for (idx_t i = 0; i < x.size(); i++) {
		double prod = x[i] * y[i];
		double yk = prod - c;
		double t = sum + yk;
		c = (t - sum) - yk;
		sum = t;
	}
	return sum;
}

static vector<double> MatrixVecMul(const vector<vector<double>> &matrix, const vector<double> &v) {
	vector<double> result;
	result.reserve(matrix.size());
	for (auto &row : matrix) {
		if (row.size() != v.size()) {
			throw InvalidInputException("Matrix/vector dimensions do not match");
		}
		result.push_back(Dot(row, v));
	}
	return result;
}

static vector<vector<double>> MatrixTranspose(const vector<vector<double>> &matrix) {
	if (matrix.empty()) {
		return {};
	}
	vector<vector<double>> result(matrix[0].size(), vector<double>(matrix.size(), 0.0));
	for (idx_t r = 0; r < matrix.size(); r++) {
		for (idx_t c = 0; c < matrix[r].size(); c++) {
			result[c][r] = matrix[r][c];
		}
	}
	return result;
}

static vector<vector<double>> MatrixMul(const vector<vector<double>> &left, const vector<vector<double>> &right) {
	if (left.empty() || right.empty()) {
		return {};
	}
	if (left[0].size() != right.size()) {
		throw InvalidInputException("Matrix dimensions do not match");
	}
	auto right_t = MatrixTranspose(right);
	vector<vector<double>> result(left.size(), vector<double>(right[0].size(), 0.0));
	for (idx_t r = 0; r < left.size(); r++) {
		for (idx_t c = 0; c < right_t.size(); c++) {
			result[r][c] = Dot(left[r], right_t[c]);
		}
	}
	return result;
}

static vector<vector<double>> MatrixCholesky(const vector<vector<double>> &matrix, double tolerance = 1e-12) {
	if (matrix.empty() || matrix.size() != matrix[0].size()) {
		throw InvalidInputException("Cholesky requires a non-empty square matrix");
	}
	vector<vector<double>> result(matrix.size(), vector<double>(matrix.size(), 0.0));
	for (idx_t i = 0; i < matrix.size(); i++) {
		for (idx_t j = 0; j <= i; j++) {
			double sum = matrix[i][j];
			for (idx_t k = 0; k < j; k++) {
				sum -= result[i][k] * result[j][k];
			}
			if (i == j) {
				if (sum < -tolerance) {
					throw InvalidInputException("Matrix is not positive semidefinite");
				}
				result[i][j] = std::sqrt(std::max(0.0, sum));
			} else {
				result[i][j] = result[j][j] <= tolerance ? 0.0 : sum / result[j][j];
			}
		}
	}
	return result;
}

static bool MatrixIsPSD(const vector<vector<double>> &matrix, double tolerance) {
	if (matrix.empty() || matrix.size() != matrix[0].size()) {
		return false;
	}
	for (idx_t r = 0; r < matrix.size(); r++) {
		for (idx_t c = r + 1; c < matrix.size(); c++) {
			if (std::fabs(matrix[r][c] - matrix[c][r]) > tolerance) {
				return false;
			}
		}
	}
	try {
		MatrixCholesky(matrix, tolerance);
		return true;
	} catch (const std::exception &) {
		return false;
	}
}

static vector<vector<double>> NearestPSD(const vector<vector<double>> &matrix) {
	if (matrix.empty() || matrix.size() != matrix[0].size()) {
		throw InvalidInputException("Nearest PSD requires a non-empty square matrix");
	}
	auto result = matrix;
	for (idx_t r = 0; r < result.size(); r++) {
		for (idx_t c = r + 1; c < result.size(); c++) {
			double value = 0.5 * (result[r][c] + result[c][r]);
			result[r][c] = value;
			result[c][r] = value;
		}
		result[r][r] = std::max(result[r][r], 1e-12);
	}
	double bump = 1e-12;
	while (!MatrixIsPSD(result, 1e-10) && bump < 1.0) {
		for (idx_t i = 0; i < result.size(); i++) {
			result[i][i] += bump;
		}
		bump *= 10.0;
	}
	return result;
}

static vector<double> EqualWeights(idx_t n) {
	if (n == 0) {
		throw InvalidInputException("fin_equal_weights requires n > 0");
	}
	return vector<double>(n, 1.0 / static_cast<double>(n));
}

static double PortfolioVarianceList(const double *weights, const list_entry_t &weights_entry,
                                    const list_entry_t *matrix_rows, const double *matrix_values,
                                    const list_entry_t &matrix_entry, const ValidityMask &matrix_value_validity) {
	if (matrix_entry.length != weights_entry.length) {
		throw InvalidInputException("Covariance matrix dimensions do not match weights");
	}
	const auto n = weights_entry.length;
	const auto w_offset = weights_entry.offset;
	if (n == 1) {
		auto row0 = matrix_rows[matrix_entry.offset];
		if (row0.length != 1) {
			throw InvalidInputException("Covariance matrix rows must match weights");
		}
		ValidateListEntryNoNull(matrix_value_validity, row0, "Covariance matrix values must not be NULL");
		const double w0 = weights[w_offset];
		return w0 * matrix_values[row0.offset] * w0;
	}
	if (n >= 2 && n <= 4) {
		for (idx_t r = 0; r < n; r++) {
			auto row_entry = matrix_rows[matrix_entry.offset + r];
			if (row_entry.length != n) {
				throw InvalidInputException("Covariance matrix rows must match weights");
			}
			ValidateListEntryNoNull(matrix_value_validity, row_entry, "Covariance matrix values must not be NULL");
		}
		const double w0 = weights[w_offset];
		const double w1 = weights[w_offset + 1];
		auto row0 = matrix_rows[matrix_entry.offset];
		auto row1 = matrix_rows[matrix_entry.offset + 1];
		double total = w0 * (matrix_values[row0.offset] * w0 + matrix_values[row0.offset + 1] * w1) +
		               w1 * (matrix_values[row1.offset] * w0 + matrix_values[row1.offset + 1] * w1);
		if (n == 2) {
			return total;
		}
		const double w2 = weights[w_offset + 2];
		auto row2 = matrix_rows[matrix_entry.offset + 2];
		total += w0 * matrix_values[row0.offset + 2] * w2 + w1 * matrix_values[row1.offset + 2] * w2 +
		         w2 * (matrix_values[row2.offset] * w0 + matrix_values[row2.offset + 1] * w1 +
		               matrix_values[row2.offset + 2] * w2);
		if (n == 3) {
			return total;
		}
		const double w3 = weights[w_offset + 3];
		auto row3 = matrix_rows[matrix_entry.offset + 3];
		total += w0 * matrix_values[row0.offset + 3] * w3 + w1 * matrix_values[row1.offset + 3] * w3 +
		         w2 * matrix_values[row2.offset + 3] * w3 +
		         w3 * (matrix_values[row3.offset] * w0 + matrix_values[row3.offset + 1] * w1 +
		               matrix_values[row3.offset + 2] * w2 + matrix_values[row3.offset + 3] * w3);
		return total;
	}
	double total = 0.0;
	double total_c = 0.0;
	for (idx_t r = 0; r < n; r++) {
		auto row_entry = matrix_rows[matrix_entry.offset + r];
		if (row_entry.length != n) {
			throw InvalidInputException("Covariance matrix rows must match weights");
		}
		ValidateListEntryNoNull(matrix_value_validity, row_entry, "Covariance matrix values must not be NULL");
		double sigma = 0.0;
		double sigma_c = 0.0;
		for (idx_t c = 0; c < row_entry.length; c++) {
			double prod = matrix_values[row_entry.offset + c] * weights[w_offset + c];
			double y = prod - sigma_c;
			double t = sigma + y;
			sigma_c = (t - sigma) - y;
			sigma = t;
		}
		double prod = weights[w_offset + r] * sigma;
		double y = prod - total_c;
		double t = total + y;
		total_c = (t - total) - y;
		total = t;
	}
	return total;
}

static vector<double> NormalizeSum(const vector<double> &x) {
	double sum = std::accumulate(x.begin(), x.end(), 0.0);
	if (sum == 0.0) {
		throw InvalidInputException("Cannot normalize a zero-sum vector");
	}
	vector<double> result = x;
	for (auto &v : result) {
		v /= sum;
	}
	return result;
}

static double LinearInterpolateList(const double *x, const list_entry_t &x_entry, const double *y,
                                    const list_entry_t &y_entry, double target) {
	if (x_entry.length != y_entry.length || x_entry.length == 0) {
		throw InvalidInputException("Curve input lists must be non-empty and have equal length");
	}
	const auto x_offset = x_entry.offset;
	const auto y_offset = y_entry.offset;
	if (x_entry.length == 1 || target <= x[x_offset]) {
		return y[y_offset];
	}
	for (idx_t i = 1; i < x_entry.length; i++) {
		if (target <= x[x_offset + i]) {
			double width = x[x_offset + i] - x[x_offset + i - 1];
			if (width == 0.0) {
				return y[y_offset + i];
			}
			double weight = (target - x[x_offset + i - 1]) / width;
			return y[y_offset + i - 1] + weight * (y[y_offset + i] - y[y_offset + i - 1]);
		}
	}
	return y[y_offset + x_entry.length - 1];
}

static double CashflowNPV(double rate, const double *cashflows, const list_entry_t &entry) {
	double result = 0.0;
	double discount = 1.0;
	double period_df = 1.0 / (1.0 + rate);
	for (idx_t i = 0; i < entry.length; i++) {
		result += cashflows[entry.offset + i] * discount;
		discount *= period_df;
	}
	return result;
}

static double CashflowXNPV(double rate, const double *cashflows, const list_entry_t &cashflow_entry,
                           const date_t *dates, const list_entry_t &date_entry) {
	if (cashflow_entry.length != date_entry.length || cashflow_entry.length == 0) {
		throw InvalidInputException("XNPV/XIRR cashflow and date lists must be non-empty and have equal length");
	}
	double result = 0.0;
	auto start = dates[date_entry.offset];
	for (idx_t i = 0; i < cashflow_entry.length; i++) {
		double years = double(dates[date_entry.offset + i].days - start.days) / 365.0;
		result += cashflows[cashflow_entry.offset + i] / std::pow(1.0 + rate, years);
	}
	return result;
}

static double SolveRateBisection(const std::function<double(double)> &fn) {
	double lo = -0.999999;
	double hi = 10.0;
	double flo = fn(lo);
	double fhi = fn(hi);
	for (int expand = 0; flo * fhi > 0.0 && expand < 10; expand++) {
		hi *= 2.0;
		fhi = fn(hi);
	}
	if (flo * fhi > 0.0) {
		throw InvalidInputException("Could not bracket rate root");
	}
	for (int i = 0; i < 200; i++) {
		double mid = 0.5 * (lo + hi);
		double fmid = fn(mid);
		if (std::fabs(fmid) < 1e-10) {
			return mid;
		}
		if (flo * fmid <= 0.0) {
			hi = mid;
			fhi = fmid;
			(void)fhi;
		} else {
			lo = mid;
			flo = fmid;
		}
	}
	return 0.5 * (lo + hi);
}

static double DotList(const double *x, const list_entry_t &x_entry, const double *y, const list_entry_t &y_entry) {
	if (x_entry.length != y_entry.length) {
		throw InvalidInputException("Vector lengths must match");
	}
	const auto n = x_entry.length;
	const auto x_offset = x_entry.offset;
	const auto y_offset = y_entry.offset;
	if (n == 1) {
		return x[x_offset] * y[y_offset];
	}
	if (n == 2) {
		return x[x_offset] * y[y_offset] + x[x_offset + 1] * y[y_offset + 1];
	}
	if (n == 3) {
		return x[x_offset] * y[y_offset] + x[x_offset + 1] * y[y_offset + 1] + x[x_offset + 2] * y[y_offset + 2];
	}
	if (n == 4) {
		return x[x_offset] * y[y_offset] + x[x_offset + 1] * y[y_offset + 1] + x[x_offset + 2] * y[y_offset + 2] +
		       x[x_offset + 3] * y[y_offset + 3];
	}
	double sum = 0.0;
	double c = 0.0;
	for (idx_t i = 0; i < n; i++) {
		double prod = x[x_offset + i] * y[y_offset + i];
		double yk = prod - c;
		double t = sum + yk;
		c = (t - sum) - yk;
		sum = t;
	}
	return sum;
}

static double SumList(const double *x, const list_entry_t &entry) {
	const auto offset = entry.offset;
	if (entry.length == 1) {
		return x[offset];
	}
	if (entry.length == 2) {
		return x[offset] + x[offset + 1];
	}
	if (entry.length == 3) {
		return x[offset] + x[offset + 1] + x[offset + 2];
	}
	if (entry.length == 4) {
		return x[offset] + x[offset + 1] + x[offset + 2] + x[offset + 3];
	}
	double sum = 0.0;
	for (idx_t i = 0; i < entry.length; i++) {
		sum += x[offset + i];
	}
	return sum;
}

#if __has_include("duckdb/common/identifier.hpp")
static Identifier FinanceFunctionName(const string &name) {
	return Identifier(name);
}
#else
static const string &FinanceFunctionName(const string &name) {
	return name;
}
#endif

static void AddScalar(ExtensionLoader &loader, const string &name, vector<LogicalType> args, LogicalType ret,
                      scalar_function_t func) {
	ScalarFunction scalar(FinanceFunctionName(name), std::move(args), std::move(ret), std::move(func));
	scalar.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	loader.RegisterFunction(std::move(scalar));
}

static void AddOverload(ScalarFunctionSet &set, vector<LogicalType> args, LogicalType ret, scalar_function_t func) {
	ScalarFunction scalar(std::move(args), std::move(ret), std::move(func));
	scalar.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	set.AddFunction(std::move(scalar));
}

static void RegisterOptionFunction(ExtensionLoader &loader, const string &name, scalar_function_t func) {
	ScalarFunctionSet set(FinanceFunctionName(name));
	AddOverload(set, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                  FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), func);
	AddOverload(set, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                  FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), func);
	loader.RegisterFunction(std::move(set));
}

static void RegisterOptionFunctionWithScale(ExtensionLoader &loader, const string &name, scalar_function_t func) {
	ScalarFunctionSet set(FinanceFunctionName(name));
	AddOverload(set, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                  FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), func);
	AddOverload(set, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                  FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), func);
	AddOverload(set, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                  FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), func);
	loader.RegisterFunction(std::move(set));
}
