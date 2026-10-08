constexpr double INV_SQRT_2PI = 0.398942280401432677939946059934381868;
constexpr double SQRT_2 = 1.414213562373095048801688724209698079;
constexpr double FIN_PI = 3.141592653589793238462643383279502884;
constexpr double FIN_LN_SQRT_2PI = 0.918938533204672741780329736405617640;
constexpr double FIN_NAN = std::numeric_limits<double>::quiet_NaN();
constexpr double FIN_INF = std::numeric_limits<double>::infinity();

// Error policy (0.3.0):
// * Invalid configuration strings (option kind, day count, compounding, units, calendars, ...) raise an
//   InvalidInputException. The registration wrappers prefix the message with the SQL function name.
// * Per-row domain failures (expired option, no root, non-finite input) return NaN, which the executors turn
//   into NULL. Kernels must never throw for domain failures: exceptions cost ~100x a normal row.

static bool IsFinite(double value) {
	return std::isfinite(value);
}

static bool IsAsciiSpace(char c) {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

static char LowerAscii(char c) {
	return c >= 'A' && c <= 'Z' ? char(c - 'A' + 'a') : c;
}

//! Lower-case and drop spaces, hyphens and underscores: "Semi-Annual" -> "semiannual".
static string NormalizeCompact(const string &input) {
	string result;
	result.reserve(input.size());
	for (auto c : input) {
		if (IsAsciiSpace(c) || c == '-' || c == '_') {
			continue;
		}
		result.push_back(LowerAscii(c));
	}
	return result;
}

//===--------------------------------------------------------------------===//
// Configuration parsers. These throw on unknown values (configuration errors).
//===--------------------------------------------------------------------===//

static bool ParseCallKind(const string &kind) {
	auto normalized = NormalizeCompact(kind);
	if (normalized == "call" || normalized == "c") {
		return true;
	}
	if (normalized == "put" || normalized == "p") {
		return false;
	}
	throw InvalidInputException("unknown option kind '%s'; expected 'call', 'put', 'c', or 'p'", kind);
}

static string ParseOptionKind(const string &kind) {
	return ParseCallKind(kind) ? "call" : "put";
}

enum class ExerciseStyle : uint8_t { EUROPEAN, AMERICAN };

static ExerciseStyle ParseExerciseStyleEnum(const string &style) {
	auto normalized = NormalizeCompact(style);
	if (normalized == "european" || normalized == "euro" || normalized == "eu") {
		return ExerciseStyle::EUROPEAN;
	}
	if (normalized == "american" || normalized == "amer" || normalized == "us") {
		return ExerciseStyle::AMERICAN;
	}
	throw InvalidInputException("unknown exercise style '%s'; expected 'european' or 'american' (Bermudan exercise "
	                            "is not supported)",
	                            style);
}

static string ParseExerciseStyle(const string &style) {
	return ParseExerciseStyleEnum(style) == ExerciseStyle::AMERICAN ? "american" : "european";
}

static string ParseReturnMethod(const string &method) {
	auto normalized = NormalizeCompact(method);
	if (normalized == "simple" || normalized == "simp" || normalized == "arithmetic") {
		return "simple";
	}
	if (normalized == "log" || normalized == "ln" || normalized == "continuous") {
		return "log";
	}
	throw InvalidInputException("unknown return method '%s'; expected 'simple' or 'log'", method);
}

enum class Compounding : uint8_t { CONTINUOUS, SIMPLE, PERIODIC, SEMIANNUAL, QUARTERLY, MONTHLY, DAILY };

static Compounding ParseCompoundingEnum(const string &compounding) {
	auto normalized = NormalizeCompact(compounding);
	if (normalized == "continuous" || normalized == "cont" || normalized == "cc" || normalized == "continuously") {
		return Compounding::CONTINUOUS;
	}
	if (normalized == "simple") {
		return Compounding::SIMPLE;
	}
	if (normalized == "periodic" || normalized == "annual" || normalized == "annually" || normalized == "yearly") {
		return Compounding::PERIODIC;
	}
	if (normalized == "semiannual" || normalized == "semiannually" || normalized == "semi") {
		return Compounding::SEMIANNUAL;
	}
	if (normalized == "quarterly" || normalized == "quarter") {
		return Compounding::QUARTERLY;
	}
	if (normalized == "monthly" || normalized == "month") {
		return Compounding::MONTHLY;
	}
	if (normalized == "daily" || normalized == "day") {
		return Compounding::DAILY;
	}
	throw InvalidInputException("unknown compounding convention '%s'; expected continuous, simple, periodic, "
	                            "semiannual, quarterly, monthly, or daily",
	                            compounding);
}

static const char *CompoundingName(Compounding compounding) {
	switch (compounding) {
	case Compounding::CONTINUOUS:
		return "continuous";
	case Compounding::SIMPLE:
		return "simple";
	case Compounding::PERIODIC:
		return "periodic";
	case Compounding::SEMIANNUAL:
		return "semiannual";
	case Compounding::QUARTERLY:
		return "quarterly";
	case Compounding::MONTHLY:
		return "monthly";
	default:
		return "daily";
	}
}

static string ParseCompounding(const string &compounding) {
	return CompoundingName(ParseCompoundingEnum(compounding));
}

//! Periods per year for the named periodic conventions; PERIODIC uses the caller's frequency.
static int64_t CompoundingFrequency(Compounding compounding, int64_t fallback) {
	switch (compounding) {
	case Compounding::SEMIANNUAL:
		return 2;
	case Compounding::QUARTERLY:
		return 4;
	case Compounding::MONTHLY:
		return 12;
	case Compounding::DAILY:
		return 365;
	default:
		return fallback;
	}
}

enum class DayCount : uint8_t { ACT_365F, ACT_360, ACT_ACT_ISDA, ACT_ACT_ICMA, THIRTY_360_BOND, THIRTY_360_US, THIRTY_E_360 };

static DayCount ParseDayCountEnum(const string &day_count) {
	auto n = NormalizeCompact(day_count);
	// Strip optional parentheses so "Actual/365 (Fixed)" and "ACT/ACT (ISDA)" are accepted.
	string normalized;
	for (auto c : n) {
		if (c != '(' && c != ')') {
			normalized.push_back(c);
		}
	}
	if (normalized == "act/365f" || normalized == "act/365fixed" || normalized == "actual/365fixed" ||
	    normalized == "act365f" || normalized == "actual365fixed" || normalized == "act/365" ||
	    normalized == "actual/365" || normalized == "act365" || normalized == "english") {
		return DayCount::ACT_365F;
	}
	if (normalized == "act/360" || normalized == "actual/360" || normalized == "act360" || normalized == "french") {
		return DayCount::ACT_360;
	}
	if (normalized == "act/act" || normalized == "actual/actual" || normalized == "actact" ||
	    normalized == "act/actisda" || normalized == "actual/actualisda" || normalized == "actactisda") {
		return DayCount::ACT_ACT_ISDA;
	}
	if (normalized == "act/acticma" || normalized == "actual/actualicma" || normalized == "act/actisma" ||
	    normalized == "actual/actualisma" || normalized == "actacticma" || normalized == "icma") {
		return DayCount::ACT_ACT_ICMA;
	}
	if (normalized == "30/360" || normalized == "bondbasis" || normalized == "360/360" ||
	    normalized == "30/360isda" || normalized == "30a/360") {
		return DayCount::THIRTY_360_BOND;
	}
	if (normalized == "30u/360" || normalized == "30/360us" || normalized == "30/360sia" || normalized == "30us/360") {
		return DayCount::THIRTY_360_US;
	}
	if (normalized == "30e/360" || normalized == "eurobondbasis" || normalized == "30/360icma" ||
	    normalized == "30e/360icma") {
		return DayCount::THIRTY_E_360;
	}
	throw InvalidInputException("unknown day-count convention '%s'; expected ACT/365F, ACT/360, ACT/ACT, "
	                            "ACT/ACT ICMA, 30/360, 30U/360, or 30E/360",
	                            day_count);
}

static const char *DayCountName(DayCount day_count) {
	switch (day_count) {
	case DayCount::ACT_365F:
		return "ACT/365F";
	case DayCount::ACT_360:
		return "ACT/360";
	case DayCount::ACT_ACT_ISDA:
		return "ACT/ACT";
	case DayCount::ACT_ACT_ICMA:
		return "ACT/ACT ICMA";
	case DayCount::THIRTY_360_BOND:
		return "30/360";
	case DayCount::THIRTY_360_US:
		return "30U/360";
	default:
		return "30E/360";
	}
}

static string ParseDayCount(const string &day_count) {
	return DayCountName(ParseDayCountEnum(day_count));
}

//! Greek scaling. Vega and rho: 'raw' = per 1.00 change (default), 'market' = per 1 percentage point (/100).
//! Theta: 'year' = per year (default), 'day' = per calendar day (/365), 'trading_day' = per trading day (/252).
static double ParseVegaRhoScale(const string &unit) {
	auto normalized = NormalizeCompact(unit);
	if (normalized == "raw" || normalized == "unit" || normalized == "annual" || normalized == "decimal") {
		return 1.0;
	}
	if (normalized == "market" || normalized == "percent" || normalized == "pct" || normalized == "point" ||
	    normalized == "1%") {
		return 0.01;
	}
	throw InvalidInputException("unknown Greek unit '%s'; expected 'raw' (per 1.00) or 'market' (per 1%%)", unit);
}

static double ParseThetaScale(const string &unit) {
	auto normalized = NormalizeCompact(unit);
	if (normalized == "year" || normalized == "annual" || normalized == "raw" || normalized == "yearly") {
		return 1.0;
	}
	if (normalized == "day" || normalized == "calendarday" || normalized == "daily") {
		return 1.0 / 365.0;
	}
	if (normalized == "tradingday" || normalized == "businessday") {
		return 1.0 / 252.0;
	}
	throw InvalidInputException("unknown theta unit '%s'; expected 'year', 'day' (/365), or 'trading_day' (/252)",
	                            unit);
}

enum class TickMode : uint8_t { NEAREST, UP, DOWN };

static TickMode ParseTickMode(const string &mode) {
	auto normalized = NormalizeCompact(mode);
	if (normalized == "nearest" || normalized == "round") {
		return TickMode::NEAREST;
	}
	if (normalized == "up" || normalized == "ceil" || normalized == "ceiling") {
		return TickMode::UP;
	}
	if (normalized == "down" || normalized == "floor") {
		return TickMode::DOWN;
	}
	throw InvalidInputException("unknown tick rounding mode '%s'; expected 'nearest', 'up', or 'down'", mode);
}

enum class BusinessCalendar : uint8_t { WEEKDAY, NYSE };

static BusinessCalendar ParseCalendar(const string &calendar) {
	auto normalized = NormalizeCompact(calendar);
	if (normalized == "weekday" || normalized == "weekdays" || normalized == "monfri") {
		return BusinessCalendar::WEEKDAY;
	}
	if (normalized == "nyse" || normalized == "xnys" || normalized == "nyseequity") {
		return BusinessCalendar::NYSE;
	}
	throw InvalidInputException("unknown calendar '%s'; supported calendars are 'weekday' (Monday-Friday, no "
	                            "holidays) and 'NYSE'",
	                            calendar);
}

enum class SessionZone : uint8_t { EXCHANGE, UTC, NEW_YORK };

static SessionZone ParseSessionZone(const string &zone) {
	auto normalized = NormalizeCompact(zone);
	if (normalized == "utc" || normalized == "etc/utc" || normalized == "gmt" || normalized == "z" ||
	    normalized == "etc/gmt" || normalized == "zulu") {
		return SessionZone::UTC;
	}
	if (normalized == "america/newyork" || normalized == "us/eastern" || normalized == "est5edt" ||
	    normalized == "newyork") {
		return SessionZone::NEW_YORK;
	}
	if (normalized == "exchange" || normalized == "local") {
		return SessionZone::EXCHANGE;
	}
	throw InvalidInputException("unsupported time zone '%s'; supported zones are 'America/New_York' and 'UTC' "
	                            "(or 'exchange' for the calendar's own zone)",
	                            zone);
}

enum class BarrierKind : uint8_t { DOWN_IN, DOWN_OUT, UP_IN, UP_OUT };

static BarrierKind ParseBarrierKind(const string &kind) {
	auto normalized = NormalizeCompact(kind);
	if (normalized == "downin" || normalized == "di") {
		return BarrierKind::DOWN_IN;
	}
	if (normalized == "downout" || normalized == "do") {
		return BarrierKind::DOWN_OUT;
	}
	if (normalized == "upin" || normalized == "ui") {
		return BarrierKind::UP_IN;
	}
	if (normalized == "upout" || normalized == "uo") {
		return BarrierKind::UP_OUT;
	}
	throw InvalidInputException("unknown barrier kind '%s'; expected down-in, down-out, up-in, or up-out", kind);
}

enum class BinomialTree : uint8_t { CRR, JR };

static BinomialTree ParseBinomialTree(const string &tree) {
	auto normalized = NormalizeCompact(tree);
	if (normalized == "crr" || normalized == "coxrossrubinstein") {
		return BinomialTree::CRR;
	}
	if (normalized == "jr" || normalized == "jarrowrudd") {
		return BinomialTree::JR;
	}
	throw InvalidInputException("unknown binomial tree '%s'; expected 'crr' or 'jr'", tree);
}

enum class AnnuityTiming : uint8_t { END, BEGIN };

static AnnuityTiming ParseAnnuityTiming(const string &when) {
	auto normalized = NormalizeCompact(when);
	if (normalized == "end" || normalized == "0" || normalized == "arrears") {
		return AnnuityTiming::END;
	}
	if (normalized == "begin" || normalized == "start" || normalized == "1" || normalized == "due") {
		return AnnuityTiming::BEGIN;
	}
	throw InvalidInputException("unknown annuity payment timing '%s'; expected 'end' or 'begin'", when);
}

enum class DurationKind : uint8_t { MACAULAY, MODIFIED };

static DurationKind ParseDurationKind(const string &kind) {
	auto normalized = NormalizeCompact(kind);
	if (normalized == "macaulay" || normalized == "mac") {
		return DurationKind::MACAULAY;
	}
	if (normalized == "modified" || normalized == "mod") {
		return DurationKind::MODIFIED;
	}
	throw InvalidInputException("unknown bond duration kind '%s'; expected 'macaulay' or 'modified'", kind);
}

enum class PSDMethod : uint8_t { CLIP, HIGHAM };

static PSDMethod ParsePSDMethod(const string &method) {
	auto normalized = NormalizeCompact(method);
	if (normalized == "clip" || normalized == "eigen" || normalized == "eigenvalue" || normalized == "eigclip" ||
	    normalized == "nearest" || normalized == "covariance") {
		return PSDMethod::CLIP;
	}
	if (normalized == "higham" || normalized == "correlation" || normalized == "corr") {
		return PSDMethod::HIGHAM;
	}
	throw InvalidInputException("unknown nearest-PSD method '%s'; expected 'clip' (eigenvalue clipping) or "
	                            "'higham' (nearest correlation matrix)",
	                            method);
}

static DayCount ParseDayCountNoPeriod(const string &day_count) {
	auto result = ParseDayCountEnum(day_count);
	if (result == DayCount::ACT_ACT_ICMA) {
		throw InvalidInputException("day count 'ACT/ACT ICMA' needs a coupon period; use it with "
		                            "fin_accrued_interest or choose ACT/ACT (ISDA)");
	}
	return result;
}

//===--------------------------------------------------------------------===//
// Distributions. Domain failures return NaN.
//===--------------------------------------------------------------------===//

static double NormPDF(double x) {
	return INV_SQRT_2PI * std::exp(-0.5 * x * x);
}

static double NormCDF(double x) {
	return 0.5 * std::erfc(-x / SQRT_2);
}

static double NormInv(double p) {
	if (!(p > 0.0 && p < 1.0)) {
		return FIN_NAN;
	}
	// Peter J. Acklam's rational approximation followed by one Halley step.
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
		x = (((((c1 * q + c2) * q + c3) * q + c4) * q + c5) * q + c6) / ((((d1 * q + d2) * q + d3) * q + d4) * q + 1.0);
	} else if (p <= phigh) {
		q = p - 0.5;
		const double r = q * q;
		x = (((((a1 * r + a2) * r + a3) * r + a4) * r + a5) * r + a6) * q /
		    (((((b1 * r + b2) * r + b3) * r + b4) * r + b5) * r + 1.0);
	} else {
		q = std::sqrt(-2.0 * std::log1p(-p));
		x = -(((((c1 * q + c2) * q + c3) * q + c4) * q + c5) * q + c6) / ((((d1 * q + d2) * q + d3) * q + d4) * q + 1.0);
	}
	// Halley refinement against the tail that is represented accurately.
	const double err = p > 0.5 ? -(0.5 * std::erfc(x / SQRT_2) - (1.0 - p)) : NormCDF(x) - p;
	const double u = err / NormPDF(x);
	return x - u / (1.0 + 0.5 * x * u);
}

//! Stirling-series remainder lgamma(a) - [(a - 0.5) ln a - a + ln sqrt(2 pi)], accurate for large a.
static double StirlingError(double a) {
	if (a < 15.0) {
		return std::lgamma(a) - ((a - 0.5) * std::log(a) - a + FIN_LN_SQRT_2PI);
	}
	const double inv = 1.0 / a;
	const double inv2 = inv * inv;
	return inv * (1.0 / 12.0 - inv2 * (1.0 / 360.0 - inv2 * (1.0 / 1260.0 - inv2 * (1.0 / 1680.0))));
}

//! lgamma(a + b) - lgamma(a) without catastrophic cancellation when a is large.
static double LogGammaDiff(double a, double b) {
	if (a < 15.0 || a + b < 15.0) {
		return std::lgamma(a + b) - std::lgamma(a);
	}
	return (a - 0.5) * std::log1p(b / a) + b * std::log(a + b) - b + StirlingError(a + b) - StirlingError(a);
}

//! ln(B(a, b)) = lgamma(a) + lgamma(b) - lgamma(a + b), stable when one argument is large.
static double LogBeta(double a, double b) {
	if (a < b) {
		std::swap(a, b);
	}
	// a >= b
	return std::lgamma(b) - LogGammaDiff(a, b);
}

//! Continued fraction for the incomplete beta function (Lentz). Returns NaN when it does not converge.
static double Betacf(double a, double b, double x) {
	const int max_iter = 300 + int(std::min(1e7, 20.0 * std::sqrt(std::max(a, b))));
	constexpr double EPS = 1e-15;
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
	for (int m = 1; m <= max_iter; m++) {
		double m2 = 2.0 * m;
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
			return h;
		}
	}
	return FIN_NAN;
}

//! Regularized incomplete beta I_x(a, b) where y = 1 - x is supplied separately to keep precision.
//! log_x and log_y may be supplied (accurately computed) by the caller; NaN means "compute from x and y".
static double RegularizedBeta(double a, double b, double x, double y, double log_beta, double log_x = FIN_NAN,
                              double log_y = FIN_NAN) {
	if (!(x >= 0.0) || !(x <= 1.0) || !(a > 0.0) || !(b > 0.0)) {
		return FIN_NAN;
	}
	if ((x == 0.0 && !std::isfinite(log_x)) || (y == 0.0 && !std::isfinite(log_y))) {
		return x == 0.0 ? 0.0 : 1.0;
	}
	if (std::isnan(log_x)) {
		log_x = std::log(x);
	}
	if (std::isnan(log_y)) {
		log_y = std::log(y);
	}
	double log_bt = a * log_x + b * log_y - log_beta;
	double bt = std::exp(log_bt);
	if (x < (a + 1.0) / (a + b + 2.0)) {
		return bt * Betacf(a, b, x) / a;
	}
	return 1.0 - bt * Betacf(b, a, y) / b;
}

//! x^a e^{-x} / Gamma(a), computed with a Stirling-corrected exponent so large shapes keep precision.
static double GammaPrefactor(double a, double x) {
	if (x == 0.0) {
		return 0.0;
	}
	if (a < 15.0) {
		return std::exp(a * std::log(x) - x - std::lgamma(a));
	}
	const double s = (x - a) / a;
	// a * (log(x / a) - s): log1p keeps precision near x = a; away from it use logs directly.
	const double core = std::fabs(s) < 0.5 ? a * (std::log1p(s) - s) : a * (std::log(x) - std::log(a)) - (x - a);
	return std::exp(core - StirlingError(a)) * std::sqrt(a) * INV_SQRT_2PI;
}

struct GammaTails {
	double lower;
	double upper;
};

//! Regularized lower and upper incomplete gamma P(a, x) and Q(a, x); the smaller tail is computed directly.
static GammaTails RegularizedGamma(double a, double x) {
	if (!(a > 0.0) || !(x >= 0.0) || std::isnan(x)) {
		return {FIN_NAN, FIN_NAN};
	}
	if (x == 0.0) {
		return {0.0, 1.0};
	}
	if (std::isinf(x)) {
		return {1.0, 0.0};
	}
	const int max_iter = 300 + int(std::min(1e7, 20.0 * std::sqrt(a)));
	constexpr double EPS = 1e-15;
	constexpr double FPMIN = 1e-300;
	const double prefactor = GammaPrefactor(a, x);
	if (x < a + 1.0) {
		double ap = a;
		double sum = 1.0 / a;
		double del = sum;
		for (int n = 1; n <= max_iter; n++) {
			ap += 1.0;
			del *= x / ap;
			sum += del;
			if (std::fabs(del) < std::fabs(sum) * EPS) {
				double lower = sum * prefactor;
				return {lower, 1.0 - lower};
			}
		}
		return {FIN_NAN, FIN_NAN};
	}
	double b = x + 1.0 - a;
	double c = 1.0 / FPMIN;
	double d = 1.0 / b;
	double h = d;
	for (int i = 1; i <= max_iter; i++) {
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
			double upper = prefactor * h;
			return {1.0 - upper, upper};
		}
	}
	return {FIN_NAN, FIN_NAN};
}

//! Student-t with precomputed constants: log B(df/2, 1/2) and the density normaliser.
struct StudentT {
	explicit StudentT(double df_p) : df(df_p) {
		log_beta = LogBeta(0.5 * df, 0.5);
		log_norm = -0.5 * std::log(df) - log_beta;
	}
	//! Lower tail P(T <= x) for x <= 0.
	double LowerTail(double x) const {
		if (x == 0.0) {
			return 0.5;
		}
		const double ax = std::fabs(x);
		double t;
		double one_minus_t;
		double log_t;
		double log_one_minus_t;
		if (ax > 1e150) {
			const double z = std::sqrt(df) / ax;
			t = z * z / (1.0 + z * z);
			one_minus_t = 1.0 / (1.0 + z * z);
			log_t = 2.0 * std::log(z) - std::log1p(z * z);
			log_one_minus_t = -std::log1p(z * z);
		} else {
			const double ratio = ax * ax / df;
			const double denom = df + ax * ax;
			t = df / denom;
			one_minus_t = ax * ax / denom;
			log_t = -std::log1p(ratio);
			log_one_minus_t = std::log(ratio) - std::log1p(ratio);
		}
		return 0.5 * RegularizedBeta(0.5 * df, 0.5, t, one_minus_t, log_beta, log_t, log_one_minus_t);
	}
	double LogPDF(double x) const {
		const double ax = std::fabs(x);
		double log_kernel = ax > 1e150 ? 2.0 * (std::log(ax) - 0.5 * std::log(df)) : std::log1p(ax * ax / df);
		return log_norm - 0.5 * (df + 1.0) * log_kernel;
	}
	double df;
	double log_beta;
	double log_norm;
};

static double StudentTCDF(double x, double df) {
	if (std::isnan(x) || !(df > 0.0)) {
		return FIN_NAN;
	}
	if (std::isinf(df)) {
		return NormCDF(x);
	}
	if (std::isinf(x)) {
		return x > 0.0 ? 1.0 : 0.0;
	}
	const double lower = StudentT(df).LowerTail(-std::fabs(x));
	return x > 0.0 ? 1.0 - lower : lower;
}

static double Chi2CDF(double x, double df) {
	if (std::isnan(x) || !(df > 0.0) || std::isinf(df)) {
		return FIN_NAN;
	}
	if (x <= 0.0) {
		return 0.0;
	}
	return RegularizedGamma(0.5 * df, 0.5 * x).lower;
}

struct LogTailValue {
	double log_tail;
	double derivative;
};

//! Safeguarded Newton iteration on g(x) = log(tail(x)) - log(target) inside the bracket [lo, hi].
//! `increasing` says whether the tail grows with x; `geometric` bisects on a log scale when the bracket
//! spans orders of magnitude. `first` is the already computed evaluation at x0.
template <class EVAL>
static double SolveLogTail(EVAL eval, double target_log, double x0, LogTailValue first, double lo, double hi,
                           bool increasing) {
	double x = x0;
	LogTailValue value = first;
	for (idx_t iter = 0; iter < 200; iter++) {
		double g = value.log_tail - target_log;
		if (std::isnan(g)) {
			return FIN_NAN;
		}
		if (std::fabs(g) <= 1e-15) {
			return x;
		}
		bool above = increasing ? g > 0.0 : g < 0.0;
		if (above) {
			hi = x;
		} else {
			lo = x;
		}
		double next = x - g / value.derivative;
		if (!(std::isfinite(next) && next > lo && next < hi)) {
			if (lo > 0.0 && hi / lo > 4.0) {
				next = std::sqrt(lo * hi);
			} else if (hi < 0.0 && lo / hi > 4.0) {
				next = -std::sqrt(lo * hi);
			} else {
				next = 0.5 * (lo + hi);
			}
		}
		if (std::fabs(next - x) <= 2e-16 * std::fabs(x) || hi - lo <= 2e-16 * std::max(std::fabs(lo), std::fabs(hi))) {
			return next;
		}
		x = next;
		value = eval(x);
	}
	return x;
}

static double StudentTInv(double p, double df) {
	if (!(p > 0.0 && p < 1.0) || !(df > 0.0)) {
		return FIN_NAN;
	}
	if (std::isinf(df)) {
		return NormInv(p);
	}
	if (p > 0.5) {
		return -StudentTInv(1.0 - p, df);
	}
	if (p == 0.5) {
		return 0.0;
	}
	if (df == 1.0) {
		return -1.0 / std::tan(FIN_PI * p);
	}
	if (df == 2.0) {
		return (2.0 * p - 1.0) / std::sqrt(2.0 * p * (1.0 - p));
	}
	const StudentT dist(df);
	auto eval = [&](double x) {
		double log_lower = std::log(dist.LowerTail(x));
		return LogTailValue {log_lower, std::exp(dist.LogPDF(x) - log_lower)};
	};
	const double target = std::log(p);
	// Initial guess: Cornish-Fisher expansion around the normal quantile, or the power-law tail
	// P(T < x) ~ c df^((df-1)/2) |x|^-df when that fits better (small df, far tails).
	const double z = NormInv(p);
	const double z2 = z * z;
	double x0 = z + (z2 * z + z) / (4.0 * df) + (5.0 * z2 * z2 * z + 16.0 * z2 * z + 3.0 * z) / (96.0 * df * df);
	if (!(x0 < 0.0) || !std::isfinite(x0)) {
		x0 = z;
	}
	LogTailValue v0 = eval(x0);
	const double tail = -std::exp((dist.log_norm + 0.5 * (df + 1.0) * std::log(df) - std::log(df) - target) / df);
	if (std::fabs(v0.log_tail - target) > 1e-3 && std::isfinite(tail) && tail < 0.0) {
		LogTailValue vt = eval(tail);
		if (std::fabs(vt.log_tail - target) < std::fabs(v0.log_tail - target)) {
			x0 = tail;
			v0 = vt;
		}
	}
	// Bracket the root; the lower tail increases with x and hi = 0 has tail 0.5 > p.
	double lo = x0;
	double hi = 0.0;
	LogTailValue v_lo = v0;
	double factor = 2.0;
	for (idx_t i = 0; i < 64 && v_lo.log_tail > target; i++) {
		hi = lo;
		lo *= factor;
		factor *= factor;
		if (!std::isfinite(lo)) {
			lo = -std::numeric_limits<double>::max();
		}
		v_lo = eval(lo);
		if (lo == -std::numeric_limits<double>::max()) {
			break;
		}
	}
	if (!(v_lo.log_tail <= target)) {
		return FIN_NAN;
	}
	if (lo != x0) {
		x0 = lo;
		v0 = v_lo;
	}
	return SolveLogTail(eval, target, x0, v0, lo, hi, true);
}

static double Chi2Inv(double p, double df) {
	if (!(p > 0.0 && p < 1.0) || !(df > 0.0) || std::isinf(df)) {
		return FIN_NAN;
	}
	const double a = 0.5 * df;
	const bool upper = p > 0.5;
	const double target = upper ? std::log1p(-p) : std::log(p);
	auto eval = [&](double y) {
		auto tails = RegularizedGamma(a, y);
		double tail = upper ? tails.upper : tails.lower;
		double pdf = GammaPrefactor(a, y) / y;
		return LogTailValue {std::log(tail), (upper ? -pdf : pdf) / tail};
	};
	// Wilson-Hilferty starting point (in units of y = x / 2), falling back to the small-x power law.
	const double z = NormInv(p);
	const double h = 2.0 / (9.0 * df);
	const double wh = 1.0 - h + z * std::sqrt(h);
	double y0 = wh > 0.0 ? a * wh * wh * wh : FIN_NAN;
	const double small = std::exp((std::log(p) + std::lgamma(a + 1.0)) / a);
	if (!(y0 > 0.0) || !std::isfinite(y0) || (!upper && small < y0 && small < 0.5 * a)) {
		y0 = small;
	}
	if (!(y0 > 0.0) || !std::isfinite(y0)) {
		y0 = std::max(a, 1e-300);
	}
	LogTailValue v0 = eval(y0);
	// g(y) = log tail - target is increasing in y for the lower tail and decreasing for the upper tail.
	auto below_root = [&](const LogTailValue &v) { return upper ? v.log_tail >= target : v.log_tail <= target; };
	double lo = y0;
	double hi = y0;
	LogTailValue v = v0;
	double factor = 2.0;
	if (below_root(v0)) {
		for (idx_t i = 0; i < 64; i++) {
			hi *= factor;
			factor *= factor;
			if (!std::isfinite(hi)) {
				return FIN_NAN;
			}
			v = eval(hi);
			if (!below_root(v)) {
				break;
			}
			lo = hi;
		}
	} else {
		for (idx_t i = 0; i < 64; i++) {
			lo /= factor;
			factor *= factor;
			if (!(lo > 0.0)) {
				lo = std::numeric_limits<double>::min();
			}
			v = eval(lo);
			if (below_root(v)) {
				break;
			}
			if (lo <= std::numeric_limits<double>::min()) {
				// The quantile underflows double precision.
				return 0.0;
			}
			hi = lo;
		}
	}
	auto y = SolveLogTail(eval, target, y0, v0, lo, hi, !upper);
	return 2.0 * y;
}

//===--------------------------------------------------------------------===//
// Day counts, discounting, bonds
//===--------------------------------------------------------------------===//

static bool IsLastDayOfFebruary(int32_t year, int32_t month, int32_t day) {
	return month == 2 && day == Date::MonthDays(year, month);
}

static double YearFrac(date_t start, date_t end, DayCount day_count) {
	if (!Date::IsFinite(start) || !Date::IsFinite(end)) {
		return FIN_NAN;
	}
	const int64_t days = int64_t(end.days) - int64_t(start.days);
	switch (day_count) {
	case DayCount::ACT_365F:
		return double(days) / 365.0;
	case DayCount::ACT_360:
		return double(days) / 360.0;
	case DayCount::ACT_ACT_ISDA:
	case DayCount::ACT_ACT_ICMA: {
		if (end.days < start.days) {
			return -YearFrac(end, start, day_count);
		}
		int32_t sy, sm, sd;
		int32_t ey, em, ed;
		Date::Convert(start, sy, sm, sd);
		Date::Convert(end, ey, em, ed);
		if (sy == ey) {
			return double(days) / (Date::IsLeapYear(sy) ? 366.0 : 365.0);
		}
		double result = 0.0;
		auto start_next_year = Date::FromDate(sy + 1, 1, 1);
		result += double(int64_t(start_next_year.days) - start.days) / (Date::IsLeapYear(sy) ? 366.0 : 365.0);
		result += double(ey) - double(sy) - 1.0;
		auto end_year_start = Date::FromDate(ey, 1, 1);
		result += double(int64_t(end.days) - end_year_start.days) / (Date::IsLeapYear(ey) ? 366.0 : 365.0);
		return result;
	}
	default:
		break;
	}
	int32_t sy, sm, sd;
	int32_t ey, em, ed;
	Date::Convert(start, sy, sm, sd);
	Date::Convert(end, ey, em, ed);
	if (day_count == DayCount::THIRTY_E_360) {
		sd = std::min(sd, 30);
		ed = std::min(ed, 30);
	} else if (day_count == DayCount::THIRTY_360_US) {
		// SIA / 30U/360: end-of-February rules, then the 31st rules.
		const bool start_feb_end = IsLastDayOfFebruary(sy, sm, sd);
		if (start_feb_end && IsLastDayOfFebruary(ey, em, ed)) {
			ed = 30;
		}
		if (start_feb_end) {
			sd = 30;
		}
		if (ed == 31 && sd >= 30) {
			ed = 30;
		}
		if (sd == 31) {
			sd = 30;
		}
	} else {
		// 30/360 Bond Basis (ISDA 2006 4.16(f)).
		if (sd == 31) {
			sd = 30;
		}
		if (ed == 31 && sd == 30) {
			ed = 30;
		}
	}
	return double((int64_t(ey) - sy) * 360 + (int64_t(em) - sm) * 30 + (int64_t(ed) - sd)) / 360.0;
}

//! Accrued coupon interest between the last coupon date and settlement.
static double AccruedInterest(date_t settle, date_t last, date_t next, double rate, double face, DayCount day_count) {
	if (!Date::IsFinite(settle) || !Date::IsFinite(last) || !Date::IsFinite(next) || !IsFinite(rate) ||
	    !IsFinite(face) || !(next.days > last.days) || settle.days < last.days || settle.days > next.days) {
		return FIN_NAN;
	}
	if (day_count == DayCount::ACT_ACT_ICMA) {
		int32_t ly, lm, ld;
		int32_t ny, nm, nd;
		Date::Convert(last, ly, lm, ld);
		Date::Convert(next, ny, nm, nd);
		double months = double((int64_t(ny) - ly) * 12 + (int64_t(nm) - lm)) + double(nd - ld) / 30.0;
		double frequency = std::max(1.0, std::round(12.0 / std::max(months, 1.0)));
		double fraction = double(int64_t(settle.days) - last.days) / double(int64_t(next.days) - last.days);
		return face * rate / frequency * fraction;
	}
	return face * rate * YearFrac(last, settle, day_count);
}

static double DiscountFactor(double rate, double ttm, Compounding compounding, int64_t frequency) {
	if (!IsFinite(rate) || !IsFinite(ttm) || ttm < 0.0) {
		return FIN_NAN;
	}
	if (compounding == Compounding::CONTINUOUS) {
		return std::exp(-rate * ttm);
	}
	if (compounding == Compounding::SIMPLE) {
		double base = 1.0 + rate * ttm;
		return base > 0.0 ? 1.0 / base : FIN_NAN;
	}
	frequency = CompoundingFrequency(compounding, frequency);
	if (frequency <= 0) {
		return FIN_NAN;
	}
	double f = double(frequency);
	if (!(1.0 + rate / f > 0.0)) {
		return FIN_NAN;
	}
	return std::exp(-f * ttm * std::log1p(rate / f));
}

static double RateFromDiscount(double df, double ttm, Compounding compounding, int64_t frequency) {
	if (!IsFinite(df) || !IsFinite(ttm) || !(df > 0.0) || !(ttm > 0.0)) {
		return FIN_NAN;
	}
	if (compounding == Compounding::CONTINUOUS) {
		return -std::log(df) / ttm;
	}
	if (compounding == Compounding::SIMPLE) {
		return (1.0 / df - 1.0) / ttm;
	}
	frequency = CompoundingFrequency(compounding, frequency);
	if (frequency <= 0) {
		return FIN_NAN;
	}
	double f = double(frequency);
	return f * std::expm1(-std::log(df) / (f * ttm));
}

static double ForwardRate(double df1, double df2, double t1, double t2, Compounding compounding) {
	if (!IsFinite(df1) || !IsFinite(df2) || !IsFinite(t1) || !IsFinite(t2) || !(df1 > 0.0) || !(df2 > 0.0) ||
	    !(t2 > t1)) {
		return FIN_NAN;
	}
	return RateFromDiscount(df2 / df1, t2 - t1, compounding, 1);
}

//! Number of coupon periods, or -1 for invalid input.
static int64_t BondPeriods(double coupon_rate, double ytm, double maturity_years, int64_t frequency, double face) {
	if (!IsFinite(coupon_rate) || !IsFinite(ytm) || !IsFinite(maturity_years) || !IsFinite(face) ||
	    !(maturity_years > 0.0) || frequency <= 0 || frequency > 1000000 || !(face > 0.0) ||
	    !(1.0 + ytm / double(frequency) > 0.0)) {
		return -1;
	}
	double periods = std::round(maturity_years * double(frequency));
	if (!IsFinite(periods) || periods < 1.0 || periods >= double(std::numeric_limits<int32_t>::max())) {
		return -1;
	}
	return static_cast<int64_t>(periods);
}

static double BondPriceForPeriods(double coupon_rate, double ytm, int64_t periods, int64_t frequency, double face) {
	double f = double(frequency);
	double coupon = face * coupon_rate / f;
	double period_rate = ytm / f;
	if (period_rate == 0.0) {
		return face + coupon * double(periods);
	}
	// Sum the geometric coupon series in O(1); expm1 preserves small yields.
	double log_discount = -double(periods) * std::log1p(period_rate);
	double redemption = face * std::exp(log_discount);
	return coupon == 0.0 ? redemption : redemption + coupon * (-std::expm1(log_discount) / period_rate);
}

static double BondPrice(double coupon_rate, double ytm, double maturity_years, int64_t frequency, double face) {
	auto periods = BondPeriods(coupon_rate, ytm, maturity_years, frequency, face);
	if (periods < 0) {
		return FIN_NAN;
	}
	return BondPriceForPeriods(coupon_rate, ytm, periods, frequency, face);
}

struct BondDiscountSums {
	double discount;
	double sum;
	double first;
	double second;
	double periods;
};

static BondDiscountSums AppendBondDiscountSums(const BondDiscountSums &a, const BondDiscountSums &b) {
	return {a.discount * b.discount, a.sum + a.discount * b.sum, a.first + a.discount * (b.first + a.periods * b.sum),
	        a.second + a.discount * (b.second + 2.0 * a.periods * b.first + a.periods * (a.periods + 1.0) * b.sum),
	        a.periods + b.periods};
}

static BondDiscountSums SumBondDiscounts(double period_df, int64_t periods) {
	// Positive geometric moments avoid cancellation near zero yield. Doubling
	// computes sum(q^i), sum(i*q^i), and sum(i*(i+1)*q^i) in O(log periods).
	BondDiscountSums result {1.0, 0.0, 0.0, 0.0, 0.0};
	BondDiscountSums block {period_df, period_df, period_df, 2.0 * period_df, 1.0};
	while (periods > 0) {
		if (periods & 1) {
			result = AppendBondDiscountSums(result, block);
		}
		periods >>= 1;
		if (periods) {
			block = AppendBondDiscountSums(block, block);
		}
	}
	return result;
}

//! dP/dy of the bond price at yield ytm.
static double BondPriceDerivative(double coupon_rate, double ytm, int64_t periods, int64_t frequency, double face) {
	double f = double(frequency);
	double coupon = face * coupon_rate / f;
	double v = 1.0 / (1.0 + ytm / f);
	auto sums = SumBondDiscounts(v, periods);
	return -(v / f) * (coupon * sums.first + face * double(periods) * sums.discount);
}

//! Yield to maturity by safeguarded Newton iteration on the closed-form price.
static double BondYTM(double price, double coupon_rate, double maturity_years, int64_t frequency, double face) {
	auto periods = BondPeriods(coupon_rate, 0.0, maturity_years, frequency, face);
	if (periods < 0 || !IsFinite(price) || !(price > 0.0) || coupon_rate < 0.0) {
		return FIN_NAN;
	}
	const double f = double(frequency);
	auto price_at = [&](double y) { return BondPriceForPeriods(coupon_rate, y, periods, frequency, face); };
	// Price decreases in yield. Bracket the root.
	double lo = std::nextafter(-f, 0.0);
	double hi = 1.0;
	while (price_at(hi) > price && IsFinite(hi * 2.0)) {
		hi *= 2.0;
	}
	double p_lo = price_at(lo);
	double p_hi = price_at(hi);
	if (!(p_lo >= price) || !(p_hi <= price)) {
		return FIN_NAN;
	}
	// Approximate yield as a starting point.
	double years = double(periods) / f;
	double y = (face * coupon_rate + (face - price) / years) / (0.5 * (face + price));
	if (!(y > lo && y < hi)) {
		y = std::min(std::max(0.05, lo + 0.5 * (std::min(hi, 1.0) - lo)), hi);
	}
	for (idx_t i = 0; i < 200; i++) {
		double p = price_at(y);
		if (!IsFinite(p)) {
			hi = y;
			y = 0.5 * (lo + hi);
			continue;
		}
		double diff = p - price;
		if (std::fabs(diff) <= 1e-13 * price) {
			return y;
		}
		if (diff > 0.0) {
			lo = y;
		} else {
			hi = y;
		}
		double derivative = BondPriceDerivative(coupon_rate, y, periods, frequency, face);
		double next = y - diff / derivative;
		if (!IsFinite(next) || !(next > lo && next < hi)) {
			next = 0.5 * (lo + hi);
		}
		if (std::fabs(next - y) <= 1e-15 * std::max(1.0, std::fabs(y))) {
			return next;
		}
		y = next;
	}
	return FIN_NAN;
}

static double BondDuration(double coupon_rate, double ytm, double maturity_years, int64_t frequency, double face,
                           DurationKind kind) {
	auto periods = BondPeriods(coupon_rate, ytm, maturity_years, frequency, face);
	if (periods < 0) {
		return FIN_NAN;
	}
	double f = double(frequency);
	double coupon = face * coupon_rate / f;
	double price = BondPriceForPeriods(coupon_rate, ytm, periods, frequency, face);
	double period_df = 1.0 / (1.0 + ytm / f);
	auto sums = SumBondDiscounts(period_df, periods);
	double weighted = (coupon * sums.first + face * double(periods) * sums.discount) / f;
	double macaulay = weighted / price;
	return kind == DurationKind::MODIFIED ? macaulay / (1.0 + ytm / f) : macaulay;
}

static double BondConvexity(double coupon_rate, double ytm, double maturity_years, int64_t frequency, double face) {
	auto periods = BondPeriods(coupon_rate, ytm, maturity_years, frequency, face);
	if (periods < 0) {
		return FIN_NAN;
	}
	double f = double(frequency);
	double coupon = face * coupon_rate / f;
	double price = BondPriceForPeriods(coupon_rate, ytm, periods, frequency, face);
	double period_df = 1.0 / (1.0 + ytm / f);
	auto sums = SumBondDiscounts(period_df, periods);
	double convexity = period_df * period_df *
	                   (coupon * sums.second + face * double(periods) * (double(periods) + 1.0) * sums.discount);
	return convexity / (price * f * f);
}

//===--------------------------------------------------------------------===//
// Business calendars
//===--------------------------------------------------------------------===//

static bool IsWeekday(date_t date) {
	auto iso_day = Date::ExtractISODayOfTheWeek(date);
	return iso_day >= 1 && iso_day <= 5;
}

//! Day of month of the n-th (1-based) ISO weekday `iso_dow` in year/month.
static int32_t NthWeekdayOfMonth(int32_t year, int32_t month, int32_t iso_dow, int32_t n) {
	auto first = Date::FromDate(year, month, 1);
	auto first_dow = Date::ExtractISODayOfTheWeek(first);
	int32_t offset = (iso_dow - first_dow + 7) % 7;
	return 1 + offset + 7 * (n - 1);
}

static int32_t LastWeekdayOfMonth(int32_t year, int32_t month, int32_t iso_dow) {
	int32_t days = Date::MonthDays(year, month);
	auto last = Date::FromDate(year, month, days);
	auto last_dow = Date::ExtractISODayOfTheWeek(last);
	return days - (last_dow - iso_dow + 7) % 7;
}

//! Gregorian Easter Sunday (anonymous Gregorian algorithm).
static date_t EasterSunday(int32_t year) {
	int32_t a = year % 19;
	int32_t b = year / 100;
	int32_t c = year % 100;
	int32_t d = b / 4;
	int32_t e = b % 4;
	int32_t f = (b + 8) / 25;
	int32_t g = (b - f + 1) / 3;
	int32_t h = (19 * a + b - d - g + 15) % 30;
	int32_t i = c / 4;
	int32_t k = c % 4;
	int32_t l = (32 + 2 * e + 2 * i - h - k) % 7;
	int32_t m = (a + 11 * h + 22 * l) / 451;
	int32_t month = (h + l - 7 * m + 114) / 31;
	int32_t day = ((h + l - 7 * m + 114) % 31) + 1;
	return Date::FromDate(year, month, day);
}

//! Saturday holidays move to Friday, Sunday holidays to Monday.
static date_t ObservedHoliday(int32_t year, int32_t month, int32_t day) {
	auto date = Date::FromDate(year, month, day);
	auto dow = Date::ExtractISODayOfTheWeek(date);
	if (dow == 6) {
		return date_t(date.days - 1);
	}
	if (dow == 7) {
		return date_t(date.days + 1);
	}
	return date;
}

//! Weekday NYSE full-day closures for a year (rule-based holidays plus known special closures since 1985).
static idx_t NyseHolidays(int32_t year, date_t *out) {
	idx_t n = 0;
	auto add = [&](date_t d) {
		if (IsWeekday(d)) {
			out[n++] = d;
		}
	};
	// New Year's Day: Sunday moves to Monday; a Saturday New Year's Day is not observed on Dec 31.
	{
		auto ny = Date::FromDate(year, 1, 1);
		auto dow = Date::ExtractISODayOfTheWeek(ny);
		if (dow == 7) {
			add(date_t(ny.days + 1));
		} else if (dow != 6) {
			add(ny);
		}
	}
	if (year >= 1998) {
		add(Date::FromDate(year, 1, NthWeekdayOfMonth(year, 1, 1, 3))); // Martin Luther King Jr. Day
	}
	add(Date::FromDate(year, 2, NthWeekdayOfMonth(year, 2, 1, 3))); // Washington's Birthday
	add(date_t(EasterSunday(year).days - 2));                        // Good Friday
	add(Date::FromDate(year, 5, LastWeekdayOfMonth(year, 5, 1)));    // Memorial Day
	if (year >= 2022) {
		add(ObservedHoliday(year, 6, 19)); // Juneteenth
	}
	add(ObservedHoliday(year, 7, 4));                                 // Independence Day
	add(Date::FromDate(year, 9, NthWeekdayOfMonth(year, 9, 1, 1)));  // Labor Day
	add(Date::FromDate(year, 11, NthWeekdayOfMonth(year, 11, 4, 4))); // Thanksgiving
	add(ObservedHoliday(year, 12, 25));                               // Christmas
	// Unscheduled closures (weather, national days of mourning, 9/11).
	static const int32_t SPECIAL[][3] = {{1985, 9, 27},  {1994, 4, 27},  {2001, 9, 11},  {2001, 9, 12},
	                                     {2001, 9, 13},  {2001, 9, 14},  {2004, 6, 11},  {2007, 1, 2},
	                                     {2012, 10, 29}, {2012, 10, 30}, {2018, 12, 5},  {2025, 1, 9}};
	for (auto &special : SPECIAL) {
		if (special[0] == year) {
			add(Date::FromDate(special[0], special[1], special[2]));
		}
	}
	return n;
}

static bool IsNyseHoliday(date_t date) {
	int32_t y, m, d;
	Date::Convert(date, y, m, d);
	date_t holidays[24];
	auto n = NyseHolidays(y, holidays);
	for (idx_t i = 0; i < n; i++) {
		if (holidays[i] == date) {
			return true;
		}
	}
	return false;
}

//! Scheduled NYSE 13:00 early closes: July 3 (Mon-Thu), the day after Thanksgiving, December 24 (Mon-Thu).
static bool IsNyseEarlyClose(date_t date) {
	int32_t y, m, d;
	Date::Convert(date, y, m, d);
	auto dow = Date::ExtractISODayOfTheWeek(date);
	if (m == 7 && d == 3 && dow >= 1 && dow <= 4) {
		return true;
	}
	if (m == 12 && d == 24 && dow >= 1 && dow <= 4) {
		return true;
	}
	if (m == 11 && dow == 5 && d == NthWeekdayOfMonth(y, 11, 4, 4) + 1) {
		return true;
	}
	return false;
}

static bool IsBusinessDay(date_t date, BusinessCalendar calendar) {
	if (!IsWeekday(date)) {
		return false;
	}
	return calendar == BusinessCalendar::WEEKDAY || !IsNyseHoliday(date);
}

//! Weekdays in the half-open range [start, end) with start <= end.
static int64_t WeekdaysForward(date_t start, date_t end) {
	auto days = int64_t(end.days) - int64_t(start.days);
	auto full_weeks = days / 7;
	auto remaining_days = days % 7;
	int64_t business_days = full_weeks * 5;
	auto start_day = Date::ExtractISODayOfTheWeek(start);
	for (int64_t offset = 0; offset < remaining_days; offset++) {
		auto iso_day = (start_day - 1 + offset) % 7 + 1;
		if (iso_day <= 5) {
			business_days++;
		}
	}
	return business_days;
}

//! Weekday NYSE holidays with lower <= date < upper.
static int64_t NyseHolidaysInRange(date_t lower, date_t upper) {
	if (!(lower.days < upper.days)) {
		return 0;
	}
	int32_t ly, lm, ld;
	int32_t uy, um, ud;
	Date::Convert(lower, ly, lm, ld);
	Date::Convert(date_t(upper.days - 1), uy, um, ud);
	int64_t count = 0;
	date_t holidays[24];
	for (int32_t year = ly; year <= uy; year++) {
		auto n = NyseHolidays(year, holidays);
		for (idx_t i = 0; i < n; i++) {
			if (holidays[i].days >= lower.days && holidays[i].days < upper.days) {
				count++;
			}
		}
	}
	return count;
}

static int64_t BusinessDaysForward(date_t start, date_t end, BusinessCalendar calendar) {
	auto weekdays = WeekdaysForward(start, end);
	if (calendar == BusinessCalendar::WEEKDAY) {
		return weekdays;
	}
	return weekdays - NyseHolidaysInRange(start, end);
}

//! Move n >= 0 weekdays from `day` in `direction`; false when the result leaves the DATE range.
static bool AdvanceWeekdays(int64_t &day, int64_t n, int direction) {
	constexpr int64_t MAX_DAY = int64_t(std::numeric_limits<int32_t>::max()) - 1;
	auto available = direction > 0 ? MAX_DAY - day : day + MAX_DAY;
	if (n > available) {
		return false;
	}
	auto in_range = [&](int64_t value) { return value > -MAX_DAY && value < MAX_DAY; };
	auto remaining = n;
	if (remaining > 0) {
		// Reach the first weekday, skip full weeks, then walk at most six days.
		do {
			day += direction;
			if (!in_range(day)) {
				return false;
			}
		} while (!IsWeekday(date_t(int32_t(day))));
		remaining--;
		day += direction * (remaining / 5) * 7;
		if (!in_range(day)) {
			return false;
		}
		remaining %= 5;
		while (remaining > 0) {
			day += direction;
			if (!in_range(day)) {
				return false;
			}
			if (IsWeekday(date_t(int32_t(day)))) {
				remaining--;
			}
		}
	}
	return Date::IsFinite(date_t(int32_t(day)));
}

static bool AdvanceBusinessDays(date_t start, int64_t n, int direction, BusinessCalendar calendar, date_t &out) {
	if (!Date::IsFinite(start) || n < 0) {
		return false;
	}
	int64_t day = start.days;
	if (!AdvanceWeekdays(day, n, direction)) {
		return false;
	}
	if (calendar == BusinessCalendar::NYSE) {
		// Holidays skipped inside each segment push the target further out until a segment has none.
		int64_t previous = start.days;
		for (idx_t guard = 0; guard < 100000; guard++) {
			int64_t holidays = direction > 0 ? NyseHolidaysInRange(date_t(int32_t(previous + 1)), date_t(int32_t(day + 1)))
			                                 : NyseHolidaysInRange(date_t(int32_t(day)), date_t(int32_t(previous)));
			if (holidays == 0) {
				break;
			}
			previous = day;
			if (!AdvanceWeekdays(day, holidays, direction)) {
				return false;
			}
		}
	}
	out = date_t(int32_t(day));
	return Date::IsFinite(out);
}

//===--------------------------------------------------------------------===//
// Session clock: America/New_York daylight-saving rules (1967 onward) and exchange-local conversion.
//===--------------------------------------------------------------------===//

constexpr int64_t MICROS_PER_HOUR = 3600LL * 1000000LL;
constexpr int64_t MICROS_PER_DAY = 24LL * MICROS_PER_HOUR;

static int64_t FloorDiv(int64_t a, int64_t b) {
	int64_t q = a / b;
	if ((a % b != 0) && ((a < 0) != (b < 0))) {
		q--;
	}
	return q;
}

//! UTC microseconds of the DST start/end transitions for America/New_York in a year; false if no DST rule.
static bool NewYorkDstWindow(int32_t year, int64_t &start_utc, int64_t &end_utc) {
	int32_t start_month, start_day, end_month, end_day;
	if (year >= 2007) {
		start_month = 3;
		start_day = NthWeekdayOfMonth(year, 3, 7, 2);
		end_month = 11;
		end_day = NthWeekdayOfMonth(year, 11, 7, 1);
	} else if (year >= 1987) {
		start_month = 4;
		start_day = NthWeekdayOfMonth(year, 4, 7, 1);
		end_month = 10;
		end_day = LastWeekdayOfMonth(year, 10, 7);
	} else if (year >= 1967) {
		start_month = 4;
		start_day = LastWeekdayOfMonth(year, 4, 7);
		end_month = 10;
		end_day = LastWeekdayOfMonth(year, 10, 7);
	} else {
		return false;
	}
	// 02:00 EST = 07:00 UTC; 02:00 EDT = 06:00 UTC.
	start_utc = int64_t(Date::FromDate(year, start_month, start_day).days) * MICROS_PER_DAY + 7 * MICROS_PER_HOUR;
	end_utc = int64_t(Date::FromDate(year, end_month, end_day).days) * MICROS_PER_DAY + 6 * MICROS_PER_HOUR;
	return true;
}

static int64_t NewYorkOffsetForUtc(int64_t utc_micros) {
	auto days = FloorDiv(utc_micros, MICROS_PER_DAY);
	if (days < -1000000 || days > 1000000) {
		return -5 * MICROS_PER_HOUR;
	}
	int32_t y, m, d;
	Date::Convert(date_t(int32_t(days)), y, m, d);
	int64_t start, end;
	if (NewYorkDstWindow(y, start, end) && utc_micros >= start && utc_micros < end) {
		return -4 * MICROS_PER_HOUR;
	}
	return -5 * MICROS_PER_HOUR;
}

static int64_t ZoneOffsetForUtc(SessionZone zone, int64_t utc_micros) {
	return zone == SessionZone::NEW_YORK ? NewYorkOffsetForUtc(utc_micros) : 0;
}

//! Interpret a wall-clock time in `zone` as UTC (skipped/repeated hours resolve to standard time first).
static int64_t ZoneLocalToUtc(SessionZone zone, int64_t local_micros) {
	if (zone != SessionZone::NEW_YORK) {
		return local_micros;
	}
	int64_t guess = local_micros + 5 * MICROS_PER_HOUR;
	return local_micros - NewYorkOffsetForUtc(guess);
}

static SessionZone CalendarZone(BusinessCalendar calendar) {
	return calendar == BusinessCalendar::NYSE ? SessionZone::NEW_YORK : SessionZone::UTC;
}

//! Exchange-local wall clock (micros) for a timestamp. `input_zone` describes how the input is to be read;
//! EXCHANGE means the input already is exchange-local wall-clock time.
static int64_t ToExchangeLocal(int64_t micros, SessionZone input_zone, BusinessCalendar calendar) {
	auto exchange_zone = CalendarZone(calendar);
	if (input_zone == SessionZone::EXCHANGE || input_zone == exchange_zone) {
		return micros;
	}
	auto utc = ZoneLocalToUtc(input_zone, micros);
	return utc + ZoneOffsetForUtc(exchange_zone, utc);
}

static bool IsRegularSession(int64_t local_micros, BusinessCalendar calendar) {
	auto days = FloorDiv(local_micros, MICROS_PER_DAY);
	auto time_of_day = local_micros - days * MICROS_PER_DAY;
	auto date = date_t(int32_t(days));
	if (!IsBusinessDay(date, calendar)) {
		return false;
	}
	const int64_t open = 9 * MICROS_PER_HOUR + 30 * 60LL * 1000000LL;
	int64_t close = 16 * MICROS_PER_HOUR;
	if (calendar == BusinessCalendar::NYSE && IsNyseEarlyClose(date)) {
		close = 13 * MICROS_PER_HOUR;
	}
	return time_of_day >= open && time_of_day < close;
}

//===--------------------------------------------------------------------===//
// Option models. Domain failures return NaN (or false for kernels).
//===--------------------------------------------------------------------===//

static double OptionPayoff(bool call, double spot, double strike) {
	if (!IsFinite(spot) || !IsFinite(strike)) {
		return FIN_NAN;
	}
	return call ? std::max(spot - strike, 0.0) : std::max(strike - spot, 0.0);
}

static double ForwardPrice(double spot, double ttm, double rate, double dividend_yield) {
	if (!IsFinite(spot) || !IsFinite(ttm) || !(spot >= 0.0) || ttm < 0.0 || !IsFinite(rate) ||
	    !IsFinite(dividend_yield)) {
		return FIN_NAN;
	}
	return spot * std::exp((rate - dividend_yield) * ttm);
}

struct OptionRow {
	bool call;
	double spot;
	double strike;
	double ttm;
	double rate;
	double vol;
	double dividend_yield;
};

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

//! Finite inputs with spot > 0, strike > 0, ttm >= 0, vol >= 0.
static bool ValidBSMInputs(const OptionRow &o) {
	return IsFinite(o.spot) && IsFinite(o.strike) && IsFinite(o.ttm) && IsFinite(o.rate) && IsFinite(o.vol) &&
	       IsFinite(o.dividend_yield) && o.spot > 0.0 && o.strike > 0.0 && o.ttm >= 0.0 && o.vol >= 0.0;
}

//! Kernel for a live option (ttm > 0, vol > 0). Returns false otherwise.
static bool MakeBSMKernel(const OptionRow &o, BSMKernel &k) {
	if (!ValidBSMInputs(o) || !(o.ttm > 0.0) || !(o.vol > 0.0)) {
		return false;
	}
	k.spot = o.spot;
	k.strike = o.strike;
	k.ttm = o.ttm;
	k.rate = o.rate;
	k.vol = o.vol;
	k.dividend_yield = o.dividend_yield;
	k.sqrt_ttm = std::sqrt(o.ttm);
	k.st = o.vol * k.sqrt_ttm;
	k.d1 = (std::log(o.spot / o.strike) + (o.rate - o.dividend_yield + 0.5 * o.vol * o.vol) * o.ttm) / k.st;
	k.d2 = k.d1 - k.st;
	k.df_rate = std::exp(-o.rate * o.ttm);
	k.df_dividend = std::exp(-o.dividend_yield * o.ttm);
	k.pdf_d1 = NormPDF(k.d1);
	return IsFinite(k.d1) && IsFinite(k.d2);
}

static double BSMPriceFromKernel(bool call, const BSMKernel &k) {
	if (call) {
		return k.spot * k.df_dividend * NormCDF(k.d1) - k.strike * k.df_rate * NormCDF(k.d2);
	}
	return k.strike * k.df_rate * NormCDF(-k.d2) - k.spot * k.df_dividend * NormCDF(-k.d1);
}

static double BSMDeltaFromKernel(bool call, const BSMKernel &k) {
	return call ? k.df_dividend * NormCDF(k.d1) : -k.df_dividend * NormCDF(-k.d1);
}

static double BSMGammaFromKernel(const BSMKernel &k) {
	return k.df_dividend * k.pdf_d1 / (k.spot * k.st);
}

static double BSMVegaFromKernel(const BSMKernel &k) {
	return k.spot * k.df_dividend * k.pdf_d1 * k.sqrt_ttm;
}

//! Theta = dV/dt in calendar time (= -dV/dT), per year.
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

//! Deterministic forward at expiry when ttm == 0 or vol == 0: +1 ITM, -1 OTM, 0 at the money.
static int ExpiryMoneyness(const OptionRow &o) {
	double forward = o.spot * std::exp((o.rate - o.dividend_yield) * o.ttm);
	double diff = o.call ? forward - o.strike : o.strike - forward;
	if (std::fabs(diff) <= 1e-14 * std::max(forward, o.strike)) {
		return 0;
	}
	return diff > 0.0 ? 1 : -1;
}

static double BSMPrice(const OptionRow &o) {
	if (!ValidBSMInputs(o)) {
		return FIN_NAN;
	}
	if (o.ttm == 0.0 || o.vol == 0.0) {
		double forward_intrinsic = o.call ? o.spot * std::exp(-o.dividend_yield * o.ttm) - o.strike * std::exp(-o.rate * o.ttm)
		                                  : o.strike * std::exp(-o.rate * o.ttm) - o.spot * std::exp(-o.dividend_yield * o.ttm);
		return std::max(forward_intrinsic, 0.0);
	}
	BSMKernel k;
	if (!MakeBSMKernel(o, k)) {
		return FIN_NAN;
	}
	return BSMPriceFromKernel(o.call, k);
}

//! Risk-neutral probability of finishing in the money, N(d2) / N(-d2); deterministic limit at expiry.
static double BSMProbITM(const OptionRow &o) {
	if (!ValidBSMInputs(o)) {
		return FIN_NAN;
	}
	if (o.ttm == 0.0 || o.vol == 0.0) {
		auto m = ExpiryMoneyness(o);
		return m > 0 ? 1.0 : m < 0 ? 0.0 : 0.5;
	}
	BSMKernel k;
	if (!MakeBSMKernel(o, k)) {
		return FIN_NAN;
	}
	return o.call ? NormCDF(k.d2) : NormCDF(-k.d2);
}

//! Probability that the spot touches the strike before expiry under the risk-neutral GBM
//! (reflection principle). 'call' = barrier above spot, 'put' = barrier below; 1 when already crossed.
static double BSMProbTouch(const OptionRow &o) {
	if (!ValidBSMInputs(o)) {
		return FIN_NAN;
	}
	const bool crossed = o.call ? o.spot >= o.strike : o.spot <= o.strike;
	if (crossed) {
		return 1.0;
	}
	const double h = std::log(o.strike / o.spot);
	const double mu = o.rate - o.dividend_yield - 0.5 * o.vol * o.vol;
	if (o.ttm == 0.0) {
		return 0.0;
	}
	if (o.vol == 0.0) {
		double drift = (o.rate - o.dividend_yield) * o.ttm;
		return (o.call ? drift >= h : drift <= h) ? 1.0 : 0.0;
	}
	const double st = o.vol * std::sqrt(o.ttm);
	const double mt = mu * o.ttm;
	const double log_scale = 2.0 * mu * h / (o.vol * o.vol);
	auto reflected = [&](double z) {
		double n = NormCDF(z);
		return n > 0.0 ? std::exp(log_scale + std::log(n)) : 0.0;
	};
	double p;
	if (o.call) {
		p = NormCDF((-h + mt) / st) + reflected((-h - mt) / st);
	} else {
		p = NormCDF((h - mt) / st) + reflected((h + mt) / st);
	}
	if (!IsFinite(p)) {
		return FIN_NAN;
	}
	return std::min(1.0, std::max(0.0, p));
}

//! Cash-or-nothing digital paying `payout` if in the money at expiry.
static double DigitalPrice(const OptionRow &o, double payout) {
	if (!IsFinite(payout)) {
		return FIN_NAN;
	}
	double prob = BSMProbITM(o);
	return payout * std::exp(-o.rate * o.ttm) * prob;
}

static double AssetOrNothingPrice(const OptionRow &o) {
	if (!ValidBSMInputs(o)) {
		return FIN_NAN;
	}
	double df_q = std::exp(-o.dividend_yield * o.ttm);
	if (o.ttm == 0.0 || o.vol == 0.0) {
		auto m = ExpiryMoneyness(o);
		return o.spot * df_q * (m > 0 ? 1.0 : m < 0 ? 0.0 : 0.5);
	}
	BSMKernel k;
	if (!MakeBSMKernel(o, k)) {
		return FIN_NAN;
	}
	return o.spot * df_q * (o.call ? NormCDF(k.d1) : NormCDF(-k.d1));
}

//! Kemna-Vorst continuously sampled geometric-average-price option.
static double AsianGeometricPrice(const OptionRow &o) {
	if (!ValidBSMInputs(o)) {
		return FIN_NAN;
	}
	double sigma_g = o.vol / std::sqrt(3.0);
	double b_g = 0.5 * (o.rate - o.dividend_yield - 0.5 * o.vol * o.vol) + 0.5 * sigma_g * sigma_g;
	double df = std::exp(-o.rate * o.ttm);
	double forward = o.spot * std::exp(b_g * o.ttm);
	double st = sigma_g * std::sqrt(o.ttm);
	if (!(st > 0.0)) {
		return df * std::max(o.call ? forward - o.strike : o.strike - forward, 0.0);
	}
	double d1 = (std::log(o.spot / o.strike) + (b_g + 0.5 * sigma_g * sigma_g) * o.ttm) / st;
	double d2 = d1 - st;
	return o.call ? df * (forward * NormCDF(d1) - o.strike * NormCDF(d2))
	              : df * (o.strike * NormCDF(-d2) - forward * NormCDF(-d1));
}

enum class HigherGreek : uint8_t { VANNA, VOMMA, SPEED, ZOMMA, ULTIMA, CHARM, COLOR, ELASTICITY };

//! Higher-order BSM Greeks. Time derivatives (charm, color) are in calendar time like theta (= -d/dT).
static double BSMHigherGreek(const OptionRow &o, HigherGreek greek) {
	BSMKernel k;
	if (!MakeBSMKernel(o, k)) {
		return FIN_NAN;
	}
	const double vol = o.vol;
	const double q = o.dividend_yield;
	const double gamma = BSMGammaFromKernel(k);
	const double vega = BSMVegaFromKernel(k);
	switch (greek) {
	case HigherGreek::VANNA:
		return -k.df_dividend * k.pdf_d1 * k.d2 / vol;
	case HigherGreek::VOMMA:
		return vega * k.d1 * k.d2 / vol;
	case HigherGreek::SPEED:
		return -gamma / o.spot * (k.d1 / k.st + 1.0);
	case HigherGreek::ZOMMA:
		return gamma * (k.d1 * k.d2 - 1.0) / vol;
	case HigherGreek::ULTIMA:
		return -vega / (vol * vol) * (k.d1 * k.d2 * (1.0 - k.d1 * k.d2) + k.d1 * k.d1 + k.d2 * k.d2);
	case HigherGreek::CHARM: {
		double term = (2.0 * (o.rate - q) * o.ttm - k.d2 * k.st) / (2.0 * o.ttm * k.st);
		if (o.call) {
			return q * k.df_dividend * NormCDF(k.d1) - k.df_dividend * k.pdf_d1 * term;
		}
		return -q * k.df_dividend * NormCDF(-k.d1) - k.df_dividend * k.pdf_d1 * term;
	}
	case HigherGreek::COLOR:
		// Calendar-time decay of gamma, -dGamma/dT, matching the theta and charm sign convention.
		return k.df_dividend * k.pdf_d1 / (2.0 * o.spot * o.ttm * k.st) *
		       (2.0 * q * o.ttm + 1.0 + k.d1 * (2.0 * (o.rate - q) * o.ttm - k.d2 * k.st) / k.st);
	case HigherGreek::ELASTICITY: {
		double price = BSMPriceFromKernel(o.call, k);
		return BSMDeltaFromKernel(o.call, k) * o.spot / price;
	}
	default:
		return FIN_NAN;
	}
}

//! Safeguarded Newton/bisection implied-volatility solver shared by BSM, Black-76 and Bachelier.
//! `price_fn(vol)` returns {price, vega}. Converges when |price - target| <= tolerance (absolute), when the
//! Newton update is below 1e-14 relative to the volatility, or when the bracket collapses; the relative stop
//! keeps very large notionals (spot >= 1e9) from spinning on an unreachable absolute tolerance.
//! `max_iter` is capped at 1000.
template <class FUNC>
static double ImpliedVolSolve(const FUNC &price_fn, double target, double guess, double tolerance, int64_t max_iter) {
	if (!IsFinite(target) || !IsFinite(guess) || guess < 0.0 || !IsFinite(tolerance) || target < 0.0 ||
	    !(tolerance > 0.0) || max_iter <= 0) {
		return FIN_NAN;
	}
	max_iter = std::min<int64_t>(max_iter, 1000);
	const double abs_tol = tolerance;
	double lo = 0.0;
	double low_price = price_fn(0.0).first;
	if (!IsFinite(low_price) || target < low_price - abs_tol) {
		return FIN_NAN;
	}
	if (std::fabs(target - low_price) <= abs_tol) {
		return 0.0;
	}
	double hi = std::max(1.0, 2.0 * guess);
	for (idx_t i = 0; i < 64 && price_fn(hi).first < target; i++) {
		lo = hi;
		hi *= 4.0;
		if (!IsFinite(hi) || hi > 1e8) {
			return FIN_NAN;
		}
	}
	double vol = guess > lo && guess < hi ? guess : lo + 0.5 * (hi - lo);
	for (int64_t i = 0; i < max_iter; i++) {
		auto evaluated = price_fn(vol);
		double value = evaluated.first;
		if (!IsFinite(value)) {
			hi = vol;
			vol = lo + 0.5 * (hi - lo);
			continue;
		}
		double diff = value - target;
		if (std::fabs(diff) <= abs_tol) {
			return vol;
		}
		if (diff < 0.0) {
			lo = vol;
		} else {
			hi = vol;
		}
		double next = vol - diff / evaluated.second;
		if (!(IsFinite(next) && next > lo && next < hi)) {
			next = lo + 0.5 * (hi - lo);
		}
		if (hi - lo <= 4e-16 * hi || std::fabs(next - vol) <= 1e-14 * vol) {
			return next;
		}
		vol = next;
	}
	return FIN_NAN;
}

static double BSMImpliedVol(const OptionRow &o, double price, double guess, double tolerance, int64_t max_iter) {
	OptionRow base = o;
	base.vol = 0.0;
	if (!ValidBSMInputs(base) || !(o.ttm > 0.0) || !IsFinite(price) || !(price >= 0.0)) {
		return FIN_NAN;
	}
	double upper_bound = o.call ? o.spot * std::exp(-o.dividend_yield * o.ttm) : o.strike * std::exp(-o.rate * o.ttm);
	if (!IsFinite(upper_bound) || !(price < upper_bound)) {
		return FIN_NAN;
	}
	BSMKernel kernel;
	OptionRow unit = o;
	unit.vol = 1.0;
	if (!MakeBSMKernel(unit, kernel)) {
		return FIN_NAN;
	}
	const double log_moneyness = std::log(o.spot / o.strike) + (o.rate - o.dividend_yield) * o.ttm;
	return ImpliedVolSolve(
	    [&](double vol) {
		    if (vol == 0.0) {
			    return std::make_pair(BSMPrice(base), 0.0);
		    }
		    kernel.vol = vol;
		    kernel.st = vol * kernel.sqrt_ttm;
		    kernel.d1 = log_moneyness / kernel.st + 0.5 * kernel.st;
		    kernel.d2 = kernel.d1 - kernel.st;
		    kernel.pdf_d1 = NormPDF(kernel.d1);
		    return std::make_pair(BSMPriceFromKernel(o.call, kernel), BSMVegaFromKernel(kernel));
	    },
	    price, guess, tolerance, max_iter);
}

static double Black76Price(bool call, double forward, double strike, double ttm, double rate, double vol) {
	if (!IsFinite(forward) || !IsFinite(strike) || !IsFinite(ttm) || !IsFinite(rate) || !IsFinite(vol) ||
	    !(forward > 0.0) || !(strike > 0.0) || !(ttm >= 0.0) || !(vol >= 0.0)) {
		return FIN_NAN;
	}
	if (ttm == 0.0 || vol == 0.0) {
		return std::exp(-rate * ttm) * OptionPayoff(call, forward, strike);
	}
	double st = vol * std::sqrt(ttm);
	double d1 = (std::log(forward / strike) + 0.5 * vol * vol * ttm) / st;
	double d2 = d1 - st;
	double df = std::exp(-rate * ttm);
	return call ? df * (forward * NormCDF(d1) - strike * NormCDF(d2)) : df * (strike * NormCDF(-d2) - forward * NormCDF(-d1));
}

static double BachelierPrice(bool call, double forward, double strike, double ttm, double rate, double normal_vol) {
	if (!IsFinite(forward) || !IsFinite(strike) || !IsFinite(ttm) || !IsFinite(rate) || !IsFinite(normal_vol) ||
	    !(ttm >= 0.0) || !(normal_vol >= 0.0)) {
		return FIN_NAN;
	}
	double df = std::exp(-rate * ttm);
	if (ttm == 0.0 || normal_vol == 0.0) {
		return df * OptionPayoff(call, forward, strike);
	}
	double stddev = normal_vol * std::sqrt(ttm);
	double d = (forward - strike) / stddev;
	double undiscounted =
	    call ? (forward - strike) * NormCDF(d) + stddev * NormPDF(d) : (strike - forward) * NormCDF(-d) + stddev * NormPDF(d);
	return df * undiscounted;
}

static double DeterministicBinomialPrice(bool call, double spot, double strike, double ttm, double rate,
                                         double dividend_yield, int64_t steps, bool american) {
	if (!american) {
		double terminal_spot = spot * std::exp((rate - dividend_yield) * ttm);
		return std::exp(-rate * ttm) * OptionPayoff(call, terminal_spot, strike);
	}
	double dt = ttm / double(steps);
	double spot_growth = std::exp((rate - dividend_yield) * dt);
	double discount_step = std::exp(-rate * dt);
	double path_spot = spot;
	double discount = 1.0;
	double best = OptionPayoff(call, path_spot, strike);
	for (int64_t step = 1; step <= steps; step++) {
		path_spot *= spot_growth;
		discount *= discount_step;
		best = std::max(best, discount * OptionPayoff(call, path_spot, strike));
	}
	return best;
}

constexpr int64_t MAX_BINOMIAL_STEPS = 100000;

//! CRR / Jarrow-Rudd binomial tree. `values` is a reusable buffer (no per-row allocation).
static double BinomialPrice(const OptionRow &o, int64_t steps, ExerciseStyle exercise, BinomialTree tree,
                            vector<double> &values) {
	if (!ValidBSMInputs(o) || steps <= 0 || steps > MAX_BINOMIAL_STEPS) {
		return FIN_NAN;
	}
	const bool call = o.call;
	const double spot = o.spot, strike = o.strike, ttm = o.ttm, rate = o.rate, vol = o.vol, q = o.dividend_yield;
	bool american = exercise == ExerciseStyle::AMERICAN;
	if (call && q <= 0.0 && rate >= 0.0 && tree == BinomialTree::CRR) {
		// Early exercise cannot improve a non-dividend CRR call with non-negative rates.
		american = false;
	}
	if (ttm == 0.0) {
		return OptionPayoff(call, spot, strike);
	}
	if (vol == 0.0) {
		return DeterministicBinomialPrice(call, spot, strike, ttm, rate, q, steps, american);
	}
	double dt = ttm / double(steps);
	double u;
	double d;
	double p;
	if (tree == BinomialTree::JR) {
		double drift = (rate - q - 0.5 * vol * vol) * dt;
		u = std::exp(drift + vol * std::sqrt(dt));
		d = std::exp(drift - vol * std::sqrt(dt));
		p = 0.5;
	} else {
		u = std::exp(vol * std::sqrt(dt));
		d = 1.0 / u;
		p = (std::exp((rate - q) * dt) - d) / (u - d);
	}
	if (!IsFinite(p) || p < 0.0 || p > 1.0) {
		return FIN_NAN;
	}
	values.resize(idx_t(steps) + 1);
	const double down_over_up = d / u;
	double s = spot * std::pow(u, double(steps));
	for (int64_t i = 0; i <= steps; i++) {
		values[i] = OptionPayoff(call, s, strike);
		s *= down_over_up;
	}
	double disc = std::exp(-rate * dt);
	if (!american) {
		if (p == 0.0 || p == 1.0) {
			return std::exp(-rate * ttm) * values[p == 0.0 ? steps : 0];
		}
		// A European payoff needs only the terminal distribution. Relative binomial weights expanded from
		// the mode avoid tiny endpoint masses and reduce backward induction from O(steps^2) to O(steps).
		auto mode = std::min(steps, int64_t(std::floor((double(steps) + 1.0) * (1.0 - p))));
		auto scale = *std::max_element(values.begin(), values.begin() + steps + 1);
		if (scale == 0.0) {
			return 0.0;
		}
		double weighted = values[mode] / scale;
		double mass = 1.0;
		double weight = 1.0;
		for (int64_t i = mode; i < steps; i++) {
			weight *= (double(steps - i) / double(i + 1)) * ((1.0 - p) / p);
			weighted += weight * (values[i + 1] / scale);
			mass += weight;
		}
		weight = 1.0;
		for (int64_t i = mode; i > 0; i--) {
			weight *= (double(i) / double(steps - i + 1)) * (p / (1.0 - p));
			weighted += weight * (values[i - 1] / scale);
			mass += weight;
		}
		return std::exp(-rate * ttm) * (weighted / mass) * scale;
	}
	double american_start = spot * std::pow(u, double(steps - 1));
	double up_weight = disc * p;
	double down_weight = disc * (1.0 - p);
	for (int64_t step = steps - 1; step >= 0; step--) {
		double american_spot = american_start;
		for (int64_t i = 0; i <= step; i++) {
			double continuation = up_weight * values[i] + down_weight * values[i + 1];
			values[i] = std::max(continuation, OptionPayoff(call, american_spot, strike));
			american_spot *= down_over_up;
		}
		american_start /= u;
	}
	return values[0];
}

static double SABRVol(double forward, double strike, double ttm, double alpha, double beta, double rho, double nu,
                      double shift) {
	forward += shift;
	strike += shift;
	if (!IsFinite(forward) || !IsFinite(strike) || !IsFinite(ttm) || !IsFinite(alpha) || !IsFinite(beta) ||
	    !IsFinite(rho) || !IsFinite(nu) || !(forward > 0.0) || !(strike > 0.0) || !(alpha > 0.0) || beta < 0.0 ||
	    beta > 1.0 || std::fabs(rho) >= 1.0 || nu < 0.0 || ttm < 0.0) {
		return FIN_NAN;
	}
	double one_minus_beta = 1.0 - beta;
	if (std::fabs(forward - strike) < 1e-12) {
		double fk_beta = std::pow(forward, one_minus_beta);
		double correction = ((one_minus_beta * one_minus_beta * alpha * alpha) / (24.0 * fk_beta * fk_beta) +
		                     (rho * beta * nu * alpha) / (4.0 * fk_beta) + (2.0 - 3.0 * rho * rho) * nu * nu / 24.0) *
		                    ttm;
		return alpha / fk_beta * (1.0 + correction);
	}
	double fk = forward * strike;
	double log_fk = std::log(forward / strike);
	double fk_beta = std::pow(fk, 0.5 * one_minus_beta);
	double z = (nu / alpha) * fk_beta * log_fk;
	double z_over_xz;
	if (std::fabs(z) < 1e-4) {
		// Taylor-expand the removable z/x(z) singularity to avoid cancellation near zero.
		z_over_xz = 1.0 - 0.5 * rho * z + (2.0 - 3.0 * rho * rho) * z * z / 12.0;
	} else {
		double xz = std::log((std::sqrt(1.0 - 2.0 * rho * z + z * z) + z - rho) / (1.0 - rho));
		z_over_xz = z / xz;
	}
	double denom = fk_beta * (1.0 + one_minus_beta * one_minus_beta * log_fk * log_fk / 24.0 +
	                          std::pow(one_minus_beta, 4) * std::pow(log_fk, 4) / 1920.0);
	double correction = ((one_minus_beta * one_minus_beta * alpha * alpha) / (24.0 * fk_beta * fk_beta) +
	                     (rho * beta * nu * alpha) / (4.0 * fk_beta) + (2.0 - 3.0 * rho * rho) * nu * nu / 24.0) *
	                    ttm;
	return (alpha / denom) * z_over_xz * (1.0 + correction);
}

static double SviTotalVariance(double k, double a, double b, double rho, double m, double sigma) {
	if (!(b >= 0.0) || !(std::fabs(rho) < 1.0) || !(sigma > 0.0)) {
		return FIN_NAN;
	}
	return a + b * (rho * (k - m) + std::sqrt((k - m) * (k - m) + sigma * sigma));
}

//===--------------------------------------------------------------------===//
// Vectorized execution helpers
//===--------------------------------------------------------------------===//

struct PreparedInputs {
	explicit PreparedInputs(DataChunk &args) : formats(args.ColumnCount()), physical(args.ColumnCount()) {
		for (idx_t col = 0; col < args.ColumnCount(); col++) {
			FinanceToUnifiedFormat(args.data[col], args.size(), formats[col]);
			physical[col] = args.data[col].GetType().InternalType();
			if (formats[col].validity.CanHaveNull()) {
				nullable_cols.push_back(col);
			}
		}
	}
	vector<UnifiedVectorFormat> formats;
	vector<PhysicalType> physical;
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

	//! Integer argument registered as INTEGER or BIGINT.
	int64_t GetInteger(idx_t col, idx_t row) const {
		return physical[col] == PhysicalType::INT32 ? int64_t(GetInt32(col, row)) : GetInt64(col, row);
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

	string_t GetStringT(idx_t col, idx_t row) const {
		auto &format = formats[col];
		auto idx = format.sel->get_index(row);
		auto data = UnifiedVectorFormat::GetData<string_t>(format);
		return data[idx];
	}

	string GetString(idx_t col, idx_t row) const {
		return GetStringT(col, row).GetString();
	}
};

//! Small cache of parsed string values (a few distinct values per column, e.g. 'call' / 'put').
template <class T>
struct ParsedStringCache {
	static constexpr idx_t SLOTS = 4;
	template <class PARSE>
	const T &Get(const string_t &str, PARSE parse) {
		auto size = str.GetSize();
		auto data = str.GetData();
		for (idx_t i = 0; i < used; i++) {
			if (keys[i].size() == size && memcmp(keys[i].data(), data, size) == 0) {
				return values[i];
			}
		}
		idx_t slot = used < SLOTS ? used++ : (next_evict++ % SLOTS);
		keys[slot].assign(data, size);
		values[slot] = parse(keys[slot]);
		return values[slot];
	}
	array<string, SLOTS> keys;
	array<T, SLOTS> values;
	idx_t used = 0;
	idx_t next_evict = 0;
};

//! A VARCHAR configuration argument parsed once per chunk when constant, and otherwise through a small
//! per-chunk cache of distinct values. Unknown values raise InvalidInputException (configuration error).
template <class T>
class ConfigArg {
public:
	using Parser = T (*)(const string &);

	ConfigArg(DataChunk &args, idx_t col, Parser parse_p, T fallback) : parse(parse_p), column(col), value(fallback) {
		if (col >= args.ColumnCount()) {
			fixed = true;
			return;
		}
		auto &vec = args.data[col];
		if (vec.GetVectorType() == VectorType::CONSTANT_VECTOR) {
			fixed = true;
			if (!ConstantVector::IsNull(vec)) {
				value = parse(ConstantVector::GetData<string_t>(vec)[0].GetString());
			}
		}
	}

	T Get(const PreparedInputs &input, idx_t row) {
		if (fixed) {
			return value;
		}
		return cache.Get(input.GetStringT(column, row), parse);
	}

private:
	Parser parse;
	idx_t column;
	T value;
	bool fixed = false;
	ParsedStringCache<T> cache;
};

static bool AllInputsConstant(DataChunk &args) {
	for (idx_t col = 0; col < args.ColumnCount(); col++) {
		if (args.data[col].GetVectorType() != VectorType::CONSTANT_VECTOR) {
			return false;
		}
	}
	return true;
}

static void SetResultVectorType(Vector &result, bool constant) {
	result.SetVectorType(constant ? VectorType::CONSTANT_VECTOR : VectorType::FLAT_VECTOR);
}

template <class T>
static T *GetResultData(Vector &result, bool constant) {
	return constant ? ConstantVector::GetData<T>(result) : FlatVector::GetDataMutable<T>(result);
}

static void SetResultNull(Vector &result, idx_t row, idx_t count, bool constant) {
	if (constant) {
		ConstantVector::SetNull(result, count);
	} else {
		FlatVector::SetNull(result, row, true);
	}
}

//! Row loop shared by scalar kernels. Rows with a NULL argument produce NULL; `assign` returns false to
//! produce NULL (non-finite results, domain failures). There is deliberately no per-row exception handler:
//! kernels signal domain failures through NaN, and exceptions are reserved for configuration errors.
template <class RESULT_TYPE, class FUNC, class ASSIGN>
static void ExecuteValue(DataChunk &args, Vector &result, FUNC func, ASSIGN assign) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<RESULT_TYPE>(result, constant);
	PreparedInputs inputs(args);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (inputs.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		if (!assign(result, output[row], func(inputs, row))) {
			SetResultNull(result, row, args.size(), constant);
		}
	}
}

template <class FUNC>
static void ExecuteDouble(DataChunk &args, Vector &result, FUNC func) {
	ExecuteValue<double>(args, result, func, [](Vector &, double &target, double value) {
		target = value;
		return std::isfinite(target);
	});
}

//! Boolean results use 0 / 1 and any other value (conventionally -1) for NULL.
template <class FUNC>
static void ExecuteBool(DataChunk &args, Vector &result, FUNC func) {
	ExecuteValue<bool>(args, result, func, [](Vector &, bool &target, int value) {
		target = value == 1;
		return value == 0 || value == 1;
	});
}

template <class FUNC>
static void ExecuteString(DataChunk &args, Vector &result, FUNC func) {
	// An empty string marks a NULL result.
	ExecuteValue<string_t>(args, result, func, [](Vector &result, string_t &target, const string &value) {
		if (value.empty()) {
			return false;
		}
		target = StringVector::AddString(result, value);
		return true;
	});
}

//===--------------------------------------------------------------------===//
// List and matrix helpers
//===--------------------------------------------------------------------===//

//! Flat view of a LIST(DOUBLE) argument.
struct DoubleListArg {
	DoubleListArg(DataChunk &args, const PreparedInputs &input, idx_t col_p) : col(col_p) {
		entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[col]);
		auto &child = ListVector::GetChildMutable(args.data[col]);
		FinanceFlatten(child, ListVector::GetListSize(args.data[col]));
		validity = &FlatVector::Validity(child);
		values = FlatVector::GetData<double>(child);
	}
	list_entry_t Entry(const PreparedInputs &input, idx_t row) const {
		return entries[input.formats[col].sel->get_index(row)];
	}
	bool HasNullElement(const list_entry_t &entry) const {
		if (!validity->CanHaveNull()) {
			return false;
		}
		for (idx_t i = 0; i < entry.length; i++) {
			if (!validity->RowIsValid(entry.offset + i)) {
				return true;
			}
		}
		return false;
	}
	idx_t col;
	const list_entry_t *entries;
	const ValidityMask *validity;
	const double *values;
};

//! Flat view of a LIST(LIST(DOUBLE)) matrix argument.
struct MatrixArg {
	MatrixArg(DataChunk &args, const PreparedInputs &input, idx_t col_p) : col(col_p) {
		entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[col]);
		auto &rows_vec = ListVector::GetChildMutable(args.data[col]);
		FinanceFlatten(rows_vec, ListVector::GetListSize(args.data[col]));
		row_validity = &FlatVector::Validity(rows_vec);
		rows = FlatVector::GetData<list_entry_t>(rows_vec);
		auto &values_vec = ListVector::GetChildMutable(rows_vec);
		FinanceFlatten(values_vec, ListVector::GetListSize(rows_vec));
		value_validity = &FlatVector::Validity(values_vec);
		values = FlatVector::GetData<double>(values_vec);
	}
	list_entry_t Entry(const PreparedInputs &input, idx_t row) const {
		return entries[input.formats[col].sel->get_index(row)];
	}
	//! Shape without copying values; false for NULL rows or ragged rows.
	bool Shape(const list_entry_t &entry, idx_t &n_rows, idx_t &n_cols) const {
		n_rows = entry.length;
		n_cols = 0;
		for (idx_t r = 0; r < entry.length; r++) {
			if (row_validity->CanHaveNull() && !row_validity->RowIsValid(entry.offset + r)) {
				return false;
			}
			auto len = rows[entry.offset + r].length;
			if (r == 0) {
				n_cols = len;
			} else if (len != n_cols) {
				return false;
			}
		}
		return true;
	}
	//! Copy into a dense row-major buffer; false for NULL rows/elements or ragged rows.
	bool Read(const list_entry_t &entry, idx_t &n_rows, idx_t &n_cols, vector<double> &out) const {
		if (!Shape(entry, n_rows, n_cols)) {
			return false;
		}
		out.resize(n_rows * n_cols);
		for (idx_t r = 0; r < n_rows; r++) {
			auto row_entry = rows[entry.offset + r];
			for (idx_t c = 0; c < n_cols; c++) {
				auto pos = row_entry.offset + c;
				if (value_validity->CanHaveNull() && !value_validity->RowIsValid(pos)) {
					return false;
				}
				out[r * n_cols + c] = values[pos];
			}
		}
		return true;
	}
	idx_t col;
	const list_entry_t *entries;
	const ValidityMask *row_validity;
	const list_entry_t *rows;
	const ValidityMask *value_validity;
	const double *values;
};

//! Appends LIST(DOUBLE) results directly into the result vector (no per-row containers).
struct ListResultWriter {
	ListResultWriter(Vector &result_p, bool constant_p) : result(result_p), constant(constant_p) {
		SetResultVectorType(result, constant);
		entries = GetResultData<list_entry_t>(result, constant);
	}
	double *Begin(idx_t n) {
		ListVector::Reserve(result, offset + n);
		auto &child = ListVector::GetChildMutable(result);
		return FlatVector::GetDataMutable<double>(child) + offset;
	}
	void Commit(idx_t row, idx_t n) {
		entries[row] = list_entry_t(offset, n);
		offset += n;
	}
	void SetNull(idx_t row, idx_t count) {
		entries[row] = list_entry_t(offset, 0);
		SetResultNull(result, row, count, constant);
	}
	void Finish() {
		ListVector::SetListSize(result, offset);
	}
	Vector &result;
	bool constant;
	list_entry_t *entries;
	idx_t offset = 0;
};

//! Appends LIST(LIST(DOUBLE)) matrix results directly into the result vector.
struct MatrixResultWriter {
	MatrixResultWriter(Vector &result_p, bool constant_p) : result(result_p), constant(constant_p) {
		SetResultVectorType(result, constant);
		entries = GetResultData<list_entry_t>(result, constant);
	}
	void Write(idx_t row, const double *data, idx_t n_rows, idx_t n_cols) {
		ListVector::Reserve(result, row_offset + n_rows);
		auto &row_vector = ListVector::GetChildMutable(result);
		ListVector::Reserve(row_vector, value_offset + n_rows * n_cols);
		auto row_entries = FlatVector::GetDataMutable<list_entry_t>(row_vector);
		auto &value_vector = ListVector::GetChildMutable(row_vector);
		auto values = FlatVector::GetDataMutable<double>(value_vector);
		entries[row] = list_entry_t(row_offset, n_rows);
		for (idx_t r = 0; r < n_rows; r++) {
			row_entries[row_offset + r] = list_entry_t(value_offset, n_cols);
			memcpy(values + value_offset, data + r * n_cols, n_cols * sizeof(double));
			value_offset += n_cols;
		}
		row_offset += n_rows;
	}
	void SetNull(idx_t row, idx_t count) {
		entries[row] = list_entry_t(row_offset, 0);
		SetResultNull(result, row, count, constant);
	}
	void Finish() {
		ListVector::SetListSize(result, row_offset);
		ListVector::SetListSize(ListVector::GetChildMutable(result), value_offset);
	}
	Vector &result;
	bool constant;
	list_entry_t *entries;
	idx_t row_offset = 0;
	idx_t value_offset = 0;
};

//! Compensated dot product (Ogita-Rump-Oishi Dot2): accuracy as if computed in twice the working precision.
static double CompensatedDot(const double *x, const double *y, idx_t n) {
	double sum = 0.0;
	double comp = 0.0;
	for (idx_t i = 0; i < n; i++) {
		double prod = x[i] * y[i];
		double prod_err = std::fma(x[i], y[i], -prod);
		double t = sum + prod;
		double z = t - sum;
		double sum_err = (sum - (t - z)) + (prod - z);
		sum = t;
		comp += sum_err + prod_err;
	}
	return sum + comp;
}

static double CompensatedSum(const double *x, idx_t n) {
	double sum = 0.0;
	double comp = 0.0;
	for (idx_t i = 0; i < n; i++) {
		double t = sum + x[i];
		double z = t - sum;
		comp += (sum - (t - z)) + (x[i] - z);
		sum = t;
	}
	return sum + comp;
}

//! Cyclic Jacobi eigen-decomposition of a symmetric n x n row-major matrix. On return `a` holds
//! the eigenvalues on its diagonal and `v` the eigenvectors in its columns. Returns false if it fails to converge.
static bool JacobiEigen(vector<double> &a, vector<double> &v, idx_t n) {
	v.assign(n * n, 0.0);
	for (idx_t i = 0; i < n; i++) {
		v[i * n + i] = 1.0;
	}
	for (idx_t sweep = 0; sweep < 100; sweep++) {
		double off = 0.0;
		double total = 0.0;
		for (idx_t p = 0; p < n; p++) {
			for (idx_t q = 0; q < n; q++) {
				double value = a[p * n + q] * a[p * n + q];
				total += value;
				if (p != q) {
					off += value;
				}
			}
		}
		if (off <= 1e-30 * total || off == 0.0) {
			return true;
		}
		for (idx_t p = 0; p + 1 < n; p++) {
			for (idx_t q = p + 1; q < n; q++) {
				double apq = a[p * n + q];
				if (apq == 0.0) {
					continue;
				}
				double app = a[p * n + p];
				double aqq = a[q * n + q];
				double theta = (aqq - app) / (2.0 * apq);
				double t = (theta >= 0.0 ? 1.0 : -1.0) / (std::fabs(theta) + std::sqrt(theta * theta + 1.0));
				if (!std::isfinite(t)) {
					t = 0.5 / theta;
				}
				double c = 1.0 / std::sqrt(t * t + 1.0);
				double s = t * c;
				for (idx_t k = 0; k < n; k++) {
					double akp = a[k * n + p];
					double akq = a[k * n + q];
					a[k * n + p] = c * akp - s * akq;
					a[k * n + q] = s * akp + c * akq;
				}
				for (idx_t k = 0; k < n; k++) {
					double apk = a[p * n + k];
					double aqk = a[q * n + k];
					a[p * n + k] = c * apk - s * aqk;
					a[q * n + k] = s * apk + c * aqk;
				}
				for (idx_t k = 0; k < n; k++) {
					double vkp = v[k * n + p];
					double vkq = v[k * n + q];
					v[k * n + p] = c * vkp - s * vkq;
					v[k * n + q] = s * vkp + c * vkq;
				}
			}
		}
	}
	return false;
}

static double MaxAbs(const vector<double> &m) {
	double scale = 0.0;
	for (auto value : m) {
		scale = std::max(scale, std::fabs(value));
	}
	return scale;
}

static bool AllFinite(const vector<double> &m) {
	for (auto value : m) {
		if (!IsFinite(value)) {
			return false;
		}
	}
	return true;
}

//! Symmetry test relative to the largest absolute entry.
static bool IsSymmetric(const vector<double> &m, idx_t n, double relative_tolerance) {
	double tol = relative_tolerance * MaxAbs(m);
	for (idx_t r = 0; r < n; r++) {
		for (idx_t c = r + 1; c < n; c++) {
			if (std::fabs(m[r * n + c] - m[c * n + r]) > tol) {
				return false;
			}
		}
	}
	return true;
}

//! PSD test: symmetric (relative tolerance) and min eigenvalue >= -tol * max |eigenvalue|.
static int MatrixIsPSD(vector<double> m, idx_t n, double relative_tolerance) {
	if (!IsFinite(relative_tolerance) || relative_tolerance < 0.0) {
		return -1;
	}
	if (n == 0 || !AllFinite(m)) {
		return -1;
	}
	if (!IsSymmetric(m, n, relative_tolerance)) {
		return 0;
	}
	for (idx_t r = 0; r < n; r++) {
		for (idx_t c = r + 1; c < n; c++) {
			double avg = 0.5 * (m[r * n + c] + m[c * n + r]);
			m[r * n + c] = avg;
			m[c * n + r] = avg;
		}
	}
	vector<double> v;
	if (!JacobiEigen(m, v, n)) {
		return -1;
	}
	double max_eig = 0.0;
	double min_eig = FIN_INF;
	for (idx_t i = 0; i < n; i++) {
		max_eig = std::max(max_eig, std::fabs(m[i * n + i]));
		min_eig = std::min(min_eig, m[i * n + i]);
	}
	return min_eig >= -relative_tolerance * max_eig ? 1 : 0;
}

//! Lower-triangular Cholesky factor of a symmetric PSD matrix; tolerances are relative to the largest diagonal.
static bool MatrixCholesky(const vector<double> &m, idx_t n, vector<double> &out) {
	if (n == 0 || !AllFinite(m) || !IsSymmetric(m, n, 1e-12)) {
		return false;
	}
	double scale = 0.0;
	for (idx_t i = 0; i < n; i++) {
		scale = std::max(scale, std::fabs(m[i * n + i]));
	}
	const double tol = 1e-12 * std::max(scale, std::numeric_limits<double>::min());
	out.assign(n * n, 0.0);
	for (idx_t i = 0; i < n; i++) {
		for (idx_t j = 0; j <= i; j++) {
			double sum = m[i * n + j];
			for (idx_t k = 0; k < j; k++) {
				sum -= out[i * n + k] * out[j * n + k];
			}
			if (i == j) {
				if (sum < -tol) {
					return false;
				}
				out[i * n + j] = std::sqrt(std::max(0.0, sum));
			} else if (out[j * n + j] == 0.0) {
				if (std::fabs(sum) > std::sqrt(tol * std::max(scale, 0.0)) + tol) {
					return false;
				}
				out[i * n + j] = 0.0;
			} else {
				out[i * n + j] = sum / out[j * n + j];
			}
		}
	}
	return true;
}

//! Project a symmetric matrix onto the PSD cone by clipping negative eigenvalues (Higham 1988).
static bool ClipEigenvalues(vector<double> &m, idx_t n) {
	vector<double> a = m;
	vector<double> v;
	if (!JacobiEigen(a, v, n)) {
		return false;
	}
	for (idx_t r = 0; r < n; r++) {
		for (idx_t c = r; c < n; c++) {
			double sum = 0.0;
			for (idx_t k = 0; k < n; k++) {
				double lambda = a[k * n + k];
				if (lambda > 0.0) {
					sum += v[r * n + k] * lambda * v[c * n + k];
				}
			}
			m[r * n + c] = sum;
			m[c * n + r] = sum;
		}
	}
	return true;
}

static bool NearestPSD(vector<double> &m, idx_t n, PSDMethod method) {
	if (n == 0 || !AllFinite(m)) {
		return false;
	}
	for (idx_t r = 0; r < n; r++) {
		for (idx_t c = r + 1; c < n; c++) {
			double avg = 0.5 * (m[r * n + c] + m[c * n + r]);
			m[r * n + c] = avg;
			m[c * n + r] = avg;
		}
	}
	if (method == PSDMethod::CLIP) {
		return ClipEigenvalues(m, n);
	}
	// Higham (2002) alternating projections with Dykstra's correction onto {PSD} and {unit diagonal}.
	vector<double> y = m;
	vector<double> correction(n * n, 0.0);
	vector<double> x(n * n);
	vector<double> r(n * n);
	for (idx_t iter = 0; iter < 200; iter++) {
		for (idx_t i = 0; i < n * n; i++) {
			r[i] = y[i] - correction[i];
		}
		x = r;
		if (!ClipEigenvalues(x, n)) {
			return false;
		}
		for (idx_t i = 0; i < n * n; i++) {
			correction[i] = x[i] - r[i];
		}
		double diff = 0.0;
		double norm = 0.0;
		for (idx_t i = 0; i < n * n; i++) {
			double previous = y[i];
			y[i] = x[i];
			if (i % (n + 1) == 0) {
				y[i] = 1.0;
			}
			diff += (y[i] - previous) * (y[i] - previous);
			norm += y[i] * y[i];
		}
		if (diff <= 1e-28 * norm) {
			break;
		}
	}
	// Final projection keeps the result PSD; rescale back to a unit diagonal.
	if (!ClipEigenvalues(y, n)) {
		return false;
	}
	for (idx_t i = 0; i < n; i++) {
		if (!(y[i * n + i] > 0.0)) {
			return false;
		}
	}
	for (idx_t rr = 0; rr < n; rr++) {
		for (idx_t c = 0; c < n; c++) {
			m[rr * n + c] = rr == c ? 1.0 : y[rr * n + c] / std::sqrt(y[rr * n + rr] * y[c * n + c]);
		}
	}
	return true;
}

static double LinearInterpolateList(const double *x, const list_entry_t &x_entry, const double *y,
                                    const list_entry_t &y_entry, double target) {
	const auto x_offset = x_entry.offset;
	const auto y_offset = y_entry.offset;
	if (x_entry.length == 1 || target <= x[x_offset]) {
		return y[y_offset];
	}
	if (target >= x[x_offset + x_entry.length - 1]) {
		return y[y_offset + x_entry.length - 1];
	}
	auto begin = x + x_offset;
	auto upper = idx_t(std::lower_bound(begin, begin + x_entry.length, target) - begin);
	auto fraction = (target - begin[upper - 1]) / (begin[upper] - begin[upper - 1]);
	return (1.0 - fraction) * y[y_offset + upper - 1] + fraction * y[y_offset + upper];
}

struct RateEvaluation {
	double value;
	double derivative;
};

static double CashflowNPV(double rate, const double *cashflows, const list_entry_t &entry) {
	if (!IsFinite(rate) || rate <= -1.0) {
		return FIN_NAN;
	}
	double result = 0.0;
	double discount = 1.0;
	double period_df = 1.0 / (1.0 + rate);
	for (idx_t i = 0; i < entry.length; i++) {
		result += cashflows[entry.offset + i] * discount;
		discount *= period_df;
	}
	return result;
}

static RateEvaluation CashflowNPVEvaluation(double rate, const double *cashflows, const list_entry_t &entry,
                                            double scale) {
	double value = 0.0;
	double derivative = 0.0;
	double discount = 1.0;
	double period_df = 1.0 / (1.0 + rate);
	for (idx_t i = 0; i < entry.length; i++) {
		auto present_value = (cashflows[entry.offset + i] / scale) * discount;
		value += present_value;
		derivative -= double(i) * present_value * period_df;
		discount *= period_df;
	}
	return {value, derivative};
}

//! Largest absolute cashflow, or NaN when the flows are non-finite or lack a sign change.
static double IRRCashflowScale(const double *cashflows, const list_entry_t &entry) {
	bool has_positive = false;
	bool has_negative = false;
	double scale = 0.0;
	for (idx_t i = 0; i < entry.length; i++) {
		double value = cashflows[entry.offset + i];
		if (!std::isfinite(value)) {
			return FIN_NAN;
		}
		has_positive = has_positive || value > 0.0;
		has_negative = has_negative || value < 0.0;
		scale = std::max(scale, std::fabs(value));
	}
	return has_positive && has_negative ? scale : FIN_NAN;
}

static bool RateRootBracketed(double left, double right) {
	return left == 0.0 || right == 0.0 || std::signbit(left) != std::signbit(right);
}

template <class FUNC>
static double SolveBracketedRate(const FUNC &fn, double lo, double hi, double flo, double fhi) {
	if (flo == 0.0) {
		return lo;
	}
	if (fhi == 0.0) {
		return hi;
	}
	for (idx_t i = 0; i < 200; i++) {
		double mid = 0.5 * (lo + hi);
		double fmid = fn(mid).value;
		if (!std::isfinite(fmid)) {
			return FIN_NAN;
		}
		if (std::fabs(fmid) < 1e-14 || hi - lo < 1e-12 * std::max(1.0, std::fabs(mid))) {
			return mid;
		}
		if (RateRootBracketed(flo, fmid)) {
			hi = mid;
		} else {
			lo = mid;
			flo = fmid;
		}
	}
	return 0.5 * (lo + hi);
}

//! Newton from the caller's guess, then a safeguarded bracket search around it. NaN when no root is found.
template <class FUNC>
static double SolveRate(const FUNC &fn, double guess) {
	constexpr double MIN_RATE = -1.0 + 1e-12;
	constexpr double MAX_RATE = 1e12;
	if (!std::isfinite(guess) || guess <= MIN_RATE || guess > MAX_RATE) {
		return FIN_NAN;
	}
	// IRR and XIRR may have multiple valid roots. Start at the caller's guess so
	// the selected root follows the documented overload contract.
	double rate = guess;
	for (idx_t i = 0; i < 100; i++) {
		auto evaluated = fn(rate);
		double value = evaluated.value;
		if (!std::isfinite(value)) {
			break;
		}
		if (std::fabs(value) < 1e-14) {
			return rate;
		}
		double derivative = evaluated.derivative;
		if (!std::isfinite(derivative) || std::fabs(derivative) < 1e-14) {
			break;
		}
		double next = rate - value / derivative;
		if (!std::isfinite(next) || next <= MIN_RATE || next > MAX_RATE) {
			break;
		}
		rate = next;
	}

	// Fall back to a safeguarded bracket search around the guess. Searching in
	// log1p(rate) space covers rates close to -1 and large positive rates without
	// allowing an overflow-prone global bracket to hide an even number of roots.
	double center_value = fn(guess).value;
	double center = std::log1p(guess);
	double left_rate = guess;
	double right_rate = guess;
	double left_value = center_value;
	double right_value = center_value;
	constexpr double SEARCH_STEP = 0.05;
	constexpr idx_t DENSE_SEARCH_STEPS = 80;
	for (idx_t i = 1; i <= 100; i++) {
		double offset = SEARCH_STEP * static_cast<double>(i);
		if (i > DENSE_SEARCH_STEPS) {
			offset = SEARCH_STEP * static_cast<double>(DENSE_SEARCH_STEPS) *
			         std::pow(1.5, static_cast<double>(i - DENSE_SEARCH_STEPS));
		}
		double next_left = std::max(MIN_RATE, std::expm1(center - offset));
		double next_left_value = fn(next_left).value;
		if (std::isfinite(next_left_value) && std::isfinite(left_value) &&
		    RateRootBracketed(next_left_value, left_value)) {
			return SolveBracketedRate(fn, next_left, left_rate, next_left_value, left_value);
		}
		left_rate = next_left;
		left_value = next_left_value;

		double next_right = std::min(MAX_RATE, std::expm1(center + offset));
		double next_right_value = fn(next_right).value;
		if (std::isfinite(right_value) && std::isfinite(next_right_value) &&
		    RateRootBracketed(right_value, next_right_value)) {
			return SolveBracketedRate(fn, right_rate, next_right, right_value, next_right_value);
		}
		right_rate = next_right;
		right_value = next_right_value;
		if (left_rate == MIN_RATE && right_rate == MAX_RATE) {
			break;
		}
	}
	return FIN_NAN;
}

//===--------------------------------------------------------------------===//
// Registration helpers
//===--------------------------------------------------------------------===//

struct FinanceStructField {
	const char *name;
	LogicalTypeId type;
};

static LogicalType FinanceStructType(std::initializer_list<FinanceStructField> fields) {
	child_list_t<LogicalType> children;
	for (auto &field : fields) {
		children.emplace_back(field.name, FinanceLogicalType(field.type));
	}
	return LogicalType::STRUCT(std::move(children));
}

//! Prefix configuration errors with the SQL function name. Only reached on the error path.
static scalar_function_t WithFunctionName(const string &name, scalar_function_t func) {
	return [name, func](DataChunk &args, ExpressionState &state, Vector &result) {
		try {
			func(args, state, result);
		} catch (InvalidInputException &ex) {
			ErrorData error(ex);
			auto &message = error.RawMessage();
			if (StringUtil::StartsWith(message, name + ":")) {
				throw;
			}
			throw InvalidInputException("%s: %s", name, message);
		}
	};
}

//! Temporal overloads are declared as ANY with a high cast score so DATE (and TIMESTAMP for session functions)
//! keep winning for DATE values, NULLs and string literals; separate TIMESTAMP and TIMESTAMPTZ overloads would
//! make '2026-01-02' literals ambiguous. The score also tells the bind which shape the position expects.
static constexpr idx_t TEMPORAL_DATE_SCORE = 200;
static constexpr idx_t TEMPORAL_DATE_LIST_SCORE = 201;
static constexpr idx_t TEMPORAL_INSTANT_SCORE = 202;

static LogicalType TemporalAnyType(idx_t score) {
	return LogicalType::ANY_PARAMS(LogicalType::ANY, score);
}

static bool IsTemporalArgument(const LogicalType &type) {
	switch (type.id()) {
	case LogicalTypeId::DATE:
	case LogicalTypeId::TIMESTAMP:
	case LogicalTypeId::TIMESTAMP_TZ:
	case LogicalTypeId::TIMESTAMP_MS:
	case LogicalTypeId::TIMESTAMP_NS:
	case LogicalTypeId::TIMESTAMP_SEC:
		return true;
	default:
		return false;
	}
}

//! Resolve temporal ANY positions: DATE positions accept DATE/TIMESTAMP/TIMESTAMPTZ and bind as a cast to DATE
//! (TIMESTAMPTZ uses the session TimeZone through DuckDB's ICU cast), so kernels only ever see DATE values.
//! Instant positions accept TIMESTAMPTZ only.
static unique_ptr<FunctionData> BindTemporalArguments(ClientContext &, ScalarFunction &bound_function,
                                                      vector<unique_ptr<Expression>> &arguments) {
	for (idx_t i = 0; i < bound_function.arguments.size() && i < arguments.size(); i++) {
		auto &declared = bound_function.arguments[i];
		if (declared.id() != LogicalTypeId::ANY) {
			continue;
		}
		auto score = AnyType::GetCastScore(declared);
		auto &actual = arguments[i]->return_type;
		if (score == TEMPORAL_DATE_SCORE && IsTemporalArgument(actual)) {
			declared = FinanceLogicalType(LogicalTypeId::DATE);
		} else if (score == TEMPORAL_DATE_LIST_SCORE && actual.id() == LogicalTypeId::LIST &&
		           IsTemporalArgument(ListType::GetChildType(actual))) {
			declared = LogicalType::LIST(FinanceLogicalType(LogicalTypeId::DATE));
		} else if (score == TEMPORAL_INSTANT_SCORE && actual.id() == LogicalTypeId::TIMESTAMP_TZ) {
			declared = actual;
		} else {
			const char *expected = score == TEMPORAL_DATE_LIST_SCORE ? "a LIST of DATE, TIMESTAMP or TIMESTAMPTZ"
			                       : score == TEMPORAL_INSTANT_SCORE ? "TIMESTAMP or TIMESTAMPTZ"
			                                                         : "DATE, TIMESTAMP or TIMESTAMPTZ";
			throw BinderException("%s: argument %llu must be %s, got %s", bound_function.name, (unsigned long long)(i + 1),
			                      expected, actual.ToString());
		}
	}
	return nullptr;
}

static void AddScalar(ExtensionLoader &loader, const string &name, vector<LogicalType> args, LogicalType ret,
                      scalar_function_t func) {
	ScalarFunction scalar(FinanceFunctionName(name), std::move(args), std::move(ret), WithFunctionName(name, func));
	scalar.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	loader.RegisterFunction(std::move(scalar));
}

static void AddOverload(ScalarFunctionSet &set, vector<LogicalType> args, LogicalType ret, scalar_function_t func) {
	ScalarFunction scalar(std::move(args), std::move(ret), WithFunctionName(set.name, func));
	scalar.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	set.AddFunction(std::move(scalar));
}

//! Register a DATE-based overload plus one temporal variant (every DATE / LIST(DATE) position accepts
//! DATE, TIMESTAMP or TIMESTAMPTZ and is cast to DATE at bind time).
static void AddDateOverloads(ScalarFunctionSet &set, const vector<LogicalType> &args, LogicalType ret,
                             scalar_function_t func) {
	AddOverload(set, args, ret, func);
	auto variant = args;
	for (auto &arg : variant) {
		if (arg.id() == LogicalTypeId::DATE) {
			arg = TemporalAnyType(TEMPORAL_DATE_SCORE);
		} else if (arg.id() == LogicalTypeId::LIST && ListType::GetChildType(arg).id() == LogicalTypeId::DATE) {
			arg = TemporalAnyType(TEMPORAL_DATE_LIST_SCORE);
		}
	}
	ScalarFunction scalar(std::move(variant), ret, WithFunctionName(set.name, func));
	scalar.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	scalar.SetBindCallback(BindTemporalArguments);
	set.AddFunction(std::move(scalar));
}

//! Register a TIMESTAMP (wall-clock) overload plus a TIMESTAMPTZ (instant) variant of the first argument.
static void AddInstantOverloads(ScalarFunctionSet &set, const vector<LogicalType> &args, LogicalType ret,
                                scalar_function_t func) {
	AddOverload(set, args, ret, func);
	auto variant = args;
	variant[0] = TemporalAnyType(TEMPORAL_INSTANT_SCORE);
	ScalarFunction scalar(std::move(variant), ret, WithFunctionName(set.name, func));
	scalar.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	scalar.SetBindCallback(BindTemporalArguments);
	set.AddFunction(std::move(scalar));
}

static LogicalType OptionSpecType();

//! Register (kind, spot, strike, ttm, rate, vol[, optional...]) overloads plus option-spec overloads
//! (spec[, spec_optional...]).
static void RegisterOptionFunction(ExtensionLoader &loader, const string &name, scalar_function_t func,
                                   const vector<LogicalType> &optional_args = {FinanceLogicalType(LogicalTypeId::DOUBLE)},
                                   const vector<LogicalType> &spec_optional_args = {}) {
	ScalarFunctionSet set(FinanceFunctionName(name));
	vector<LogicalType> args = {
	    FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE),
	    FinanceLogicalType(LogicalTypeId::DOUBLE),  FinanceLogicalType(LogicalTypeId::DOUBLE),
	    FinanceLogicalType(LogicalTypeId::DOUBLE),  FinanceLogicalType(LogicalTypeId::DOUBLE)};
	AddOverload(set, args, FinanceLogicalType(LogicalTypeId::DOUBLE), func);
	for (auto &optional_arg : optional_args) {
		args.push_back(optional_arg);
		AddOverload(set, args, FinanceLogicalType(LogicalTypeId::DOUBLE), func);
	}
	vector<LogicalType> spec_args = {OptionSpecType()};
	AddOverload(set, spec_args, FinanceLogicalType(LogicalTypeId::DOUBLE), func);
	for (auto &optional_arg : spec_optional_args) {
		spec_args.push_back(optional_arg);
		AddOverload(set, spec_args, FinanceLogicalType(LogicalTypeId::DOUBLE), func);
	}
	loader.RegisterFunction(std::move(set));
}
