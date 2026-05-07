#include "finance/finance_extension.hpp"

#include "duckdb/common/exception.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/common/types/date.hpp"
#include "duckdb/common/types/time.hpp"
#include "duckdb/common/types/timestamp.hpp"
#include "duckdb/common/types/value.hpp"
#include "duckdb/common/vector/list_vector.hpp"
#include "duckdb/common/vector/struct_vector.hpp"
#include "duckdb/common/vector_operations/binary_executor.hpp"
#include "duckdb/common/vector_operations/ternary_executor.hpp"
#include "duckdb/common/vector_operations/unary_executor.hpp"
#include "duckdb/function/scalar_function.hpp"

#include <algorithm>
#include <cmath>
#include <functional>
#include <limits>
#include <numeric>

namespace duckdb {
namespace {

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
			args.data[col].ToUnifiedFormat(args.size(), formats[col]);
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

static void FinanceVersionFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	result.SetVectorType(VectorType::CONSTANT_VECTOR);
#ifdef EXT_VERSION_FINANCE
	auto version = EXT_VERSION_FINANCE;
#else
	auto version = "finance-dev";
#endif
	ConstantVector::GetData<string_t>(result)[0] = StringVector::AddString(result, version);
}

static void UnaryDoubleFunction(DataChunk &args, ExpressionState &, Vector &result, double (*func)(double)) {
	UnaryExecutor::Execute<double, double>(args.data[0], result, args.size(), [&](double x) -> optional<double> {
		try {
			auto v = func(x);
			if (!std::isfinite(v)) {
				return nullopt;
			}
			return v;
		} catch (const std::exception &) {
			return nullopt;
		}
	});
}

static void BinaryDoubleFunction(DataChunk &args, ExpressionState &, Vector &result,
                                 double (*func)(double, double)) {
	BinaryExecutor::Execute<double, double, double>(
	    args.data[0], args.data[1], result, args.size(), [&](double a, double b) -> optional<double> {
		    try {
			    auto v = func(a, b);
			    if (!std::isfinite(v)) {
				    return nullopt;
			    }
			    return v;
		    } catch (const std::exception &) {
			    return nullopt;
		    }
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
		return std::round(scaled) * tick;
	});
}

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
		if (!(nper > 0.0)) {
			throw InvalidInputException("nper must be positive");
		}
		double due = (when == "begin" || when == "start" || when == "1") ? 1.0 : 0.0;
		if (std::fabs(rate) < 1e-14) {
			return -(pv + fv) / nper;
		}
		double factor = std::pow(1.0 + rate, nper);
		return -(rate * (fv + factor * pv)) / ((1.0 + rate * due) * (factor - 1.0));
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
	children.emplace_back("delta", LogicalType::DOUBLE);
	children.emplace_back("gamma", LogicalType::DOUBLE);
	children.emplace_back("vega", LogicalType::DOUBLE);
	children.emplace_back("theta", LogicalType::DOUBLE);
	children.emplace_back("rho", LogicalType::DOUBLE);
	return LogicalType::STRUCT(std::move(children));
}

static LogicalType BSMAllType() {
	child_list_t<LogicalType> children;
	children.emplace_back("price", LogicalType::DOUBLE);
	children.emplace_back("delta", LogicalType::DOUBLE);
	children.emplace_back("gamma", LogicalType::DOUBLE);
	children.emplace_back("vega", LogicalType::DOUBLE);
	children.emplace_back("theta", LogicalType::DOUBLE);
	children.emplace_back("rho", LogicalType::DOUBLE);
	children.emplace_back("d1", LogicalType::DOUBLE);
	children.emplace_back("d2", LogicalType::DOUBLE);
	children.emplace_back("intrinsic", LogicalType::DOUBLE);
	children.emplace_back("time_value", LogicalType::DOUBLE);
	return LogicalType::STRUCT(std::move(children));
}

static void BSMGreeksFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	auto delta = FlatVector::GetDataMutable<double>(children[0]);
	auto gamma = FlatVector::GetDataMutable<double>(children[1]);
	auto vega = FlatVector::GetDataMutable<double>(children[2]);
	auto theta = FlatVector::GetDataMutable<double>(children[3]);
	auto rho = FlatVector::GetDataMutable<double>(children[4]);
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
		out.push_back(FlatVector::GetDataMutable<double>(child));
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
	auto delta = FlatVector::GetDataMutable<double>(children[0]);
	auto gamma = FlatVector::GetDataMutable<double>(children[1]);
	auto vega = FlatVector::GetDataMutable<double>(children[2]);
	auto theta = FlatVector::GetDataMutable<double>(children[3]);
	auto rho = FlatVector::GetDataMutable<double>(children[4]);
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
	auto delta = FlatVector::GetDataMutable<double>(children[0]);
	auto gamma = FlatVector::GetDataMutable<double>(children[1]);
	auto vega = FlatVector::GetDataMutable<double>(children[2]);
	auto theta = FlatVector::GetDataMutable<double>(children[3]);
	auto rho = FlatVector::GetDataMutable<double>(children[4]);
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

static void PriceTransformFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		if (name == "avg") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row) + input.GetDouble(2, row) +
			        input.GetDouble(3, row)) /
			       4.0;
		}
		if (name == "typ") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row) + input.GetDouble(2, row)) / 3.0;
		}
		if (name == "median") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row)) / 2.0;
		}
		return (input.GetDouble(0, row) + input.GetDouble(1, row) + 2.0 * input.GetDouble(2, row)) / 4.0;
	});
}

static void MicrostructureFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		if (name == "mid") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row)) / 2.0;
		}
		if (name == "spread") {
			return input.GetDouble(1, row) - input.GetDouble(0, row);
		}
		if (name == "spread_bps") {
			double mid = (input.GetDouble(0, row) + input.GetDouble(1, row)) / 2.0;
			return (input.GetDouble(1, row) - input.GetDouble(0, row)) / mid * 10000.0;
		}
		if (name == "microprice") {
			double bid_px = input.GetDouble(0, row);
			double bid_size = input.GetDouble(1, row);
			double ask_px = input.GetDouble(2, row);
			double ask_size = input.GetDouble(3, row);
			return (ask_px * bid_size + bid_px * ask_size) / (bid_size + ask_size);
		}
		double bid_size = input.GetDouble(0, row);
		double ask_size = input.GetDouble(1, row);
		return (bid_size - ask_size) / (bid_size + ask_size);
	});
}

static void TradeSignFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double price = input.GetDouble(0, row);
		double bid = input.GetDouble(1, row);
		double ask = input.GetDouble(2, row);
		if (price >= ask) {
			return 1.0;
		}
		if (price <= bid) {
			return -1.0;
		}
		if (args.ColumnCount() >= 4 && !input.IsNull(3, row)) {
			double prev = input.GetDouble(3, row);
			if (price > prev) {
				return 1.0;
			}
			if (price < prev) {
				return -1.0;
			}
		}
		return 0.0;
	});
}

static vector<double> ReadDoubleList(Vector &list_vec, const list_entry_t &entry) {
	auto list_size = ListVector::GetListSize(list_vec);
	auto &child = ListVector::GetChildMutable(list_vec);
	child.Flatten(list_size);
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
	inner_vec.Flatten(outer_size);
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

static void CashflowListFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<double>(result);
	PreparedInputs input(args);
	idx_t cf_col = name == "npv" ? 1 : 0;
	auto cashflow_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[cf_col]);
	auto &cashflow_child = ListVector::GetChildMutable(args.data[cf_col]);
	auto cashflow_size = ListVector::GetListSize(args.data[cf_col]);
	cashflow_child.Flatten(cashflow_size);
	auto &cashflow_validity = FlatVector::Validity(cashflow_child);
	auto cashflow_values = FlatVector::GetData<double>(cashflow_child);
	const list_entry_t *date_entries = nullptr;
	const date_t *date_values = nullptr;
	const ValidityMask *date_validity = nullptr;
	if (name == "xirr") {
		date_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
		auto &date_child = ListVector::GetChildMutable(args.data[1]);
		auto date_size = ListVector::GetListSize(args.data[1]);
		date_child.Flatten(date_size);
		date_validity = &FlatVector::Validity(date_child);
		date_values = FlatVector::GetData<date_t>(date_child);
	}
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
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
				output[row] = SolveRateBisection(
				    [&](double rate) { return CashflowNPV(rate, cashflow_values, cashflow_entry); });
			} else if (name == "mirr") {
				double finance_rate = input.GetDouble(1, row);
				double reinvest_rate = input.GetDouble(2, row);
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
				auto date_idx = input.formats[1].sel->get_index(row);
				auto date_entry = date_entries[date_idx];
				ValidateListEntryNoNull(*date_validity, date_entry,
				                        "Finance date-list functions do not accept NULL list elements");
				output[row] = SolveRateBisection(
				    [&](double rate) { return CashflowXNPV(rate, cashflow_values, cashflow_entry, date_values, date_entry); });
			}
			if (!std::isfinite(output[row])) {
				FlatVector::SetNull(result, row, true);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void NPVWithTimesFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<double>(result);
	PreparedInputs input(args);
	auto cashflow_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto time_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto &cashflow_child = ListVector::GetChildMutable(args.data[0]);
	auto &time_child = ListVector::GetChildMutable(args.data[1]);
	auto cashflow_size = ListVector::GetListSize(args.data[0]);
	auto time_size = ListVector::GetListSize(args.data[1]);
	cashflow_child.Flatten(cashflow_size);
	time_child.Flatten(time_size);
	auto &cashflow_validity = FlatVector::Validity(cashflow_child);
	auto &time_validity = FlatVector::Validity(time_child);
	auto cashflow_values = FlatVector::GetData<double>(cashflow_child);
	auto time_values = FlatVector::GetData<double>(time_child);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
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
				FlatVector::SetNull(result, row, true);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void CurveListFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<double>(result);
	PreparedInputs input(args);
	auto x_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto y_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto &x_child = ListVector::GetChildMutable(args.data[0]);
	auto &y_child = ListVector::GetChildMutable(args.data[1]);
	auto x_size = ListVector::GetListSize(args.data[0]);
	auto y_size = ListVector::GetListSize(args.data[1]);
	x_child.Flatten(x_size);
	y_child.Flatten(y_size);
	auto &x_validity = FlatVector::Validity(x_child);
	auto &y_validity = FlatVector::Validity(y_child);
	auto x_values = FlatVector::GetData<double>(x_child);
	auto y_values = FlatVector::GetData<double>(y_child);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto x_idx = input.formats[0].sel->get_index(row);
			auto y_idx = input.formats[1].sel->get_index(row);
			ValidateListEntryNoNull(x_validity, x_entries[x_idx], "Curve list functions do not accept NULL list elements");
			ValidateListEntryNoNull(y_validity, y_entries[y_idx], "Curve list functions do not accept NULL list elements");
			double target = input.GetDouble(2, row);
			double interpolated = LinearInterpolateList(x_values, x_entries[x_idx], y_values, y_entries[y_idx], target);
			output[row] = name == "discount" ? std::exp(-interpolated * target) : interpolated;
			if (!std::isfinite(output[row])) {
				FlatVector::SetNull(result, row, true);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void SwapRateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<double>(result);
	PreparedInputs input(args);
	auto maturity_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto discount_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto &maturity_child = ListVector::GetChildMutable(args.data[0]);
	auto &discount_child = ListVector::GetChildMutable(args.data[1]);
	auto maturity_size = ListVector::GetListSize(args.data[0]);
	auto discount_size = ListVector::GetListSize(args.data[1]);
	maturity_child.Flatten(maturity_size);
	discount_child.Flatten(discount_size);
	auto &maturity_validity = FlatVector::Validity(maturity_child);
	auto &discount_validity = FlatVector::Validity(discount_child);
	auto maturities = FlatVector::GetData<double>(maturity_child);
	auto discounts = FlatVector::GetData<double>(discount_child);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
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
				FlatVector::SetNull(result, row, true);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void ListScalarFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	auto count = args.size();
	PreparedInputs input(args);
	auto entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto &child = ListVector::GetChildMutable(args.data[0]);
	auto list_size = ListVector::GetListSize(args.data[0]);
	child.Flatten(list_size);
	auto &validity = FlatVector::Validity(child);
	auto values = FlatVector::GetData<double>(child);
	vector<vector<double>> output_lists(count);
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output_double =
	    result.GetType().id() == LogicalTypeId::DOUBLE ? FlatVector::GetDataMutable<double>(result) : nullptr;
	for (idx_t row = 0; row < count; row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto entry_idx = input.formats[0].sel->get_index(row);
			auto entry = entries[entry_idx];
			ValidateListEntryNoNull(validity, entry, "Finance list functions do not accept NULL list elements");
			if (name == "sum" || name == "mean") {
				if (entry.length == 0) {
					throw InvalidInputException("Vector must not be empty");
				}
				double sum = SumList(values, entry);
				output_double[row] = name == "sum" ? sum : sum / double(entry.length);
			} else if (name == "inverse_vol") {
				vector<double> inv;
				inv.reserve(entry.length);
				for (idx_t i = 0; i < entry.length; i++) {
					auto v = values[entry.offset + i];
					if (!(v > 0.0)) {
						throw InvalidInputException("Volatilities must be positive");
					}
					inv.push_back(1.0 / v);
				}
				output_lists[row] = NormalizeSum(inv);
			} else if (name == "normalize") {
				auto x = ReadDoubleList(args.data[0], entry);
				output_lists[row] = NormalizeSum(x);
			} else if (name == "scale") {
				double a = input.GetDouble(1, row);
				vector<double> out;
				out.reserve(entry.length);
				for (idx_t i = 0; i < entry.length; i++) {
					out.push_back(values[entry.offset + i] * a);
				}
				output_lists[row] = std::move(out);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	if (result.GetType().id() == LogicalTypeId::LIST) {
		WriteDoubleLists(result, output_lists, count);
	}
}

static void BinaryListFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	auto count = args.size();
	PreparedInputs input(args);
	auto left_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto right_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto &left_child = ListVector::GetChildMutable(args.data[0]);
	auto &right_child = ListVector::GetChildMutable(args.data[1]);
	auto left_size = ListVector::GetListSize(args.data[0]);
	auto right_size = ListVector::GetListSize(args.data[1]);
	left_child.Flatten(left_size);
	right_child.Flatten(right_size);
	auto &left_validity = FlatVector::Validity(left_child);
	auto &right_validity = FlatVector::Validity(right_child);
	auto left_values = FlatVector::GetData<double>(left_child);
	auto right_values = FlatVector::GetData<double>(right_child);
	vector<vector<double>> output_lists(count);
	auto output_double =
	    result.GetType().id() == LogicalTypeId::DOUBLE ? FlatVector::GetDataMutable<double>(result) : nullptr;
	for (idx_t row = 0; row < count; row++) {
		if (input.IsNull(0, row) || input.IsNull(1, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto left_idx = input.formats[0].sel->get_index(row);
			auto right_idx = input.formats[1].sel->get_index(row);
			auto left_entry = left_entries[left_idx];
			auto right_entry = right_entries[right_idx];
			if (left_entry.length != right_entry.length) {
				throw InvalidInputException("Vector lengths must match");
			}
			ValidateListEntryNoNull(left_validity, left_entry, "Finance list functions do not accept NULL list elements");
			ValidateListEntryNoNull(right_validity, right_entry, "Finance list functions do not accept NULL list elements");
			if (name == "dot") {
				output_double[row] = DotList(left_values, left_entry, right_values, right_entry);
			} else if (name == "turnover") {
				double turnover = 0.0;
				for (idx_t i = 0; i < left_entry.length; i++) {
					turnover += std::fabs(right_values[right_entry.offset + i] - left_values[left_entry.offset + i]);
				}
				output_double[row] = 0.5 * turnover;
			} else {
				vector<double> out(left_entry.length);
				for (idx_t i = 0; i < left_entry.length; i++) {
					auto l = left_values[left_entry.offset + i];
					auto r = right_values[right_entry.offset + i];
					out[i] = name == "add" ? l + r : l - r;
				}
				output_lists[row] = std::move(out);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	if (result.GetType().id() == LogicalTypeId::LIST) {
		WriteDoubleLists(result, output_lists, count);
	}
}

static void EqualWeightsFunction(DataChunk &args, ExpressionState &, Vector &result) {
	PreparedInputs input(args);
	vector<vector<double>> output_lists(args.size());
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto n = args.data[0].GetType().id() == LogicalTypeId::BIGINT ? input.GetInt64(0, row)
			                                                              : input.GetInt32(0, row);
			if (n <= 0) {
				throw InvalidInputException("n must be positive");
			}
			output_lists[row] = EqualWeights(NumericCast<idx_t>(n));
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	WriteDoubleLists(result, output_lists, args.size());
}

static void PortfolioScalarFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<double>(result);
	PreparedInputs input(args);
	auto weight_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto &weight_child = ListVector::GetChildMutable(args.data[0]);
	auto weight_size = ListVector::GetListSize(args.data[0]);
	weight_child.Flatten(weight_size);
	auto &weight_validity = FlatVector::Validity(weight_child);
	auto weights = FlatVector::GetData<double>(weight_child);

	if (name == "return" || name == "expected_return") {
		auto return_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
		auto &return_child = ListVector::GetChildMutable(args.data[1]);
		auto return_size = ListVector::GetListSize(args.data[1]);
		return_child.Flatten(return_size);
		auto &return_validity = FlatVector::Validity(return_child);
		auto returns = FlatVector::GetData<double>(return_child);
		for (idx_t row = 0; row < args.size(); row++) {
			if (input.HasNull(row)) {
				FlatVector::SetNull(result, row, true);
				continue;
			}
			try {
				auto w_idx = input.formats[0].sel->get_index(row);
				auto r_idx = input.formats[1].sel->get_index(row);
				auto weight_entry = weight_entries[w_idx];
				auto return_entry = return_entries[r_idx];
				ValidateListEntryNoNull(weight_validity, weight_entry, "Portfolio weight lists do not accept NULL elements");
				ValidateListEntryNoNull(return_validity, return_entry, "Portfolio return lists do not accept NULL elements");
				output[row] = DotList(weights, weight_entry, returns, return_entry);
			} catch (const std::exception &) {
				FlatVector::SetNull(result, row, true);
			}
		}
		return;
	}

	auto matrix_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto &matrix_rows_vec = ListVector::GetChildMutable(args.data[1]);
	auto matrix_row_count = ListVector::GetListSize(args.data[1]);
	matrix_rows_vec.Flatten(matrix_row_count);
	auto &matrix_row_validity = FlatVector::Validity(matrix_rows_vec);
	auto matrix_rows = FlatVector::GetData<list_entry_t>(matrix_rows_vec);
	auto &matrix_values_vec = ListVector::GetChildMutable(matrix_rows_vec);
	auto matrix_value_count = ListVector::GetListSize(matrix_rows_vec);
	matrix_values_vec.Flatten(matrix_value_count);
	auto &matrix_value_validity = FlatVector::Validity(matrix_values_vec);
	auto matrix_values = FlatVector::GetData<double>(matrix_values_vec);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto w_idx = input.formats[0].sel->get_index(row);
			auto m_idx = input.formats[1].sel->get_index(row);
			auto weight_entry = weight_entries[w_idx];
			auto matrix_entry = matrix_entries[m_idx];
			ValidateListEntryNoNull(weight_validity, weight_entry, "Portfolio weight lists do not accept NULL elements");
			ValidateListEntryNoNull(matrix_row_validity, matrix_entry, "Covariance matrix rows must not be NULL");
			double var = PortfolioVarianceList(weights, weight_entry, matrix_rows, matrix_values,
			                                   matrix_entry, matrix_value_validity);
			if (name == "variance") {
				output[row] = var;
			} else if (name == "vol") {
				output[row] = std::sqrt(std::max(0.0, var));
			} else {
				throw InvalidInputException("Unknown portfolio scalar function");
			}
			if (!std::isfinite(output[row])) {
				FlatVector::SetNull(result, row, true);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void PortfolioSharpeFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<double>(result);
	PreparedInputs input(args);
	auto weight_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto mu_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto matrix_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[2]);
	auto &weight_child = ListVector::GetChildMutable(args.data[0]);
	auto &mu_child = ListVector::GetChildMutable(args.data[1]);
	auto &matrix_rows_vec = ListVector::GetChildMutable(args.data[2]);
	auto weight_size = ListVector::GetListSize(args.data[0]);
	auto mu_size = ListVector::GetListSize(args.data[1]);
	auto matrix_row_count = ListVector::GetListSize(args.data[2]);
	weight_child.Flatten(weight_size);
	mu_child.Flatten(mu_size);
	matrix_rows_vec.Flatten(matrix_row_count);
	auto &weight_validity = FlatVector::Validity(weight_child);
	auto &mu_validity = FlatVector::Validity(mu_child);
	auto &matrix_row_validity = FlatVector::Validity(matrix_rows_vec);
	auto weights = FlatVector::GetData<double>(weight_child);
	auto mu = FlatVector::GetData<double>(mu_child);
	auto matrix_rows = FlatVector::GetData<list_entry_t>(matrix_rows_vec);
	auto &matrix_values_vec = ListVector::GetChildMutable(matrix_rows_vec);
	auto matrix_value_count = ListVector::GetListSize(matrix_rows_vec);
	matrix_values_vec.Flatten(matrix_value_count);
	auto &matrix_value_validity = FlatVector::Validity(matrix_values_vec);
	auto matrix_values = FlatVector::GetData<double>(matrix_values_vec);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto w_idx = input.formats[0].sel->get_index(row);
			auto mu_idx = input.formats[1].sel->get_index(row);
			auto m_idx = input.formats[2].sel->get_index(row);
			auto weight_entry = weight_entries[w_idx];
			auto mu_entry = mu_entries[mu_idx];
			auto matrix_entry = matrix_entries[m_idx];
			ValidateListEntryNoNull(weight_validity, weight_entry, "Portfolio inputs do not accept NULL list elements");
			ValidateListEntryNoNull(mu_validity, mu_entry, "Portfolio inputs do not accept NULL list elements");
			ValidateListEntryNoNull(matrix_row_validity, matrix_entry, "Portfolio inputs do not accept NULL list elements");
			auto expected = DotList(weights, weight_entry, mu, mu_entry);
			auto vol = std::sqrt(std::max(0.0, PortfolioVarianceList(weights, weight_entry, matrix_rows, matrix_values,
			                                                          matrix_entry, matrix_value_validity)));
			auto risk_free = args.ColumnCount() >= 4 ? input.GetDouble(3, row) : 0.0;
			output[row] = (expected - risk_free) / vol;
			if (!std::isfinite(output[row])) {
				FlatVector::SetNull(result, row, true);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void MatrixShapeFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	auto rows_out = FlatVector::GetDataMutable<int64_t>(children[0]);
	auto cols_out = FlatVector::GetDataMutable<int64_t>(children[1]);
	auto entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto idx = input.formats[0].sel->get_index(row);
			auto matrix = ReadDoubleMatrix(args.data[0], entries[idx]);
			rows_out[row] = matrix.size();
			cols_out[row] = matrix.empty() ? 0 : matrix[0].size();
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void MatrixFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	PreparedInputs input(args);
	auto count = args.size();
	vector<vector<double>> output_rows(count);
	auto entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	for (idx_t row = 0; row < count; row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto idx = input.formats[0].sel->get_index(row);
			auto matrix = ReadDoubleMatrix(args.data[0], entries[idx]);
			if (name == "vecmul") {
				auto v_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
				auto v_idx = input.formats[1].sel->get_index(row);
				auto v = ReadDoubleList(args.data[1], v_entries[v_idx]);
				output_rows[row] = MatrixVecMul(matrix, v);
			} else if (name == "transpose") {
				if (matrix.empty()) {
					output_rows[row] = {};
				} else {
					vector<double> flattened;
					for (idx_t c = 0; c < matrix[0].size(); c++) {
						for (idx_t r = 0; r < matrix.size(); r++) {
							flattened.push_back(matrix[r][c]);
						}
					}
					output_rows[row] = std::move(flattened);
				}
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	WriteDoubleLists(result, output_rows, count);
}

static void MatrixNestedFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	PreparedInputs input(args);
	auto count = args.size();
	vector<vector<vector<double>>> output_matrices(count);
	auto entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	for (idx_t row = 0; row < count; row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto idx = input.formats[0].sel->get_index(row);
			auto matrix = ReadDoubleMatrix(args.data[0], entries[idx]);
			if (name == "transpose") {
				output_matrices[row] = MatrixTranspose(matrix);
			} else if (name == "cholesky") {
				output_matrices[row] = MatrixCholesky(matrix);
			} else {
				output_matrices[row] = NearestPSD(matrix);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	WriteDoubleMatrices(result, output_matrices, count);
}

static void MatrixMulFunction(DataChunk &args, ExpressionState &, Vector &result) {
	PreparedInputs input(args);
	auto count = args.size();
	vector<vector<vector<double>>> output_matrices(count);
	auto left_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto right_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	for (idx_t row = 0; row < count; row++) {
		if (input.IsNull(0, row) || input.IsNull(1, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto left_idx = input.formats[0].sel->get_index(row);
			auto right_idx = input.formats[1].sel->get_index(row);
			auto left = ReadDoubleMatrix(args.data[0], left_entries[left_idx]);
			auto right = ReadDoubleMatrix(args.data[1], right_entries[right_idx]);
			output_matrices[row] = MatrixMul(left, right);
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	WriteDoubleMatrices(result, output_matrices, count);
}

static void MatrixIsPsdFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		auto entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
		auto idx = input.formats[0].sel->get_index(row);
		auto matrix = ReadDoubleMatrix(args.data[0], entries[idx]);
		auto tolerance = args.ColumnCount() >= 2 ? input.GetDouble(1, row) : 1e-10;
		return MatrixIsPSD(matrix, tolerance);
	});
}

static void ValidateOhlcFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	auto ok = FlatVector::GetDataMutable<bool>(children[0]);
	auto reason = FlatVector::GetDataMutable<string_t>(children[1]);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row, 4)) {
			ok[row] = false;
			reason[row] = StringVector::AddString(children[1], "null input");
			continue;
		}
		double o = input.GetDouble(0, row);
		double h = input.GetDouble(1, row);
		double l = input.GetDouble(2, row);
		double c = input.GetDouble(3, row);
		if (!IsFinite(o) || !IsFinite(h) || !IsFinite(l) || !IsFinite(c)) {
			ok[row] = false;
			reason[row] = StringVector::AddString(children[1], "non-finite price");
		} else if (h < std::max({o, l, c})) {
			ok[row] = false;
			reason[row] = StringVector::AddString(children[1], "high below open/low/close");
		} else if (l > std::min({o, h, c})) {
			ok[row] = false;
			reason[row] = StringVector::AddString(children[1], "low above open/high/close");
		} else {
			ok[row] = true;
			reason[row] = StringVector::AddString(children[1], "ok");
		}
	}
}

static LogicalType ValidationType() {
	child_list_t<LogicalType> children;
	children.emplace_back("ok", LogicalType::BOOLEAN);
	children.emplace_back("reason", LogicalType::VARCHAR);
	return LogicalType::STRUCT(std::move(children));
}

static void ValidateReturnFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		double max_abs = args.ColumnCount() >= 2 ? input.GetDouble(1, row) : 1.0;
		double r = input.GetDouble(0, row);
		return IsFinite(r) && std::fabs(r) <= max_abs && r > -1.0;
	});
}

static void IsFiniteFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [](const PreparedInputs &input, idx_t row) { return std::isfinite(input.GetDouble(0, row)); });
}

static void IsPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool allow_zero = args.ColumnCount() >= 2 ? input.GetBool(1, row) : true;
		double x = input.GetDouble(0, row);
		return IsFinite(x) && (allow_zero ? x >= 0.0 : x > 0.0);
	});
}

static void IsRateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool allow_negative = args.ColumnCount() >= 2 ? input.GetBool(1, row) : true;
		double x = input.GetDouble(0, row);
		return IsFinite(x) && (allow_negative || x >= 0.0);
	});
}

static void IsVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [](const PreparedInputs &input, idx_t row) { return IsFinite(input.GetDouble(0, row)) && input.GetDouble(0, row) >= 0.0; });
}

static void IsOutlierZScoreFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		double threshold = args.ColumnCount() >= 4 ? input.GetDouble(3, row) : 3.0;
		double stddev = input.GetDouble(2, row);
		if (!(stddev > 0.0)) {
			return false;
		}
		return std::fabs((input.GetDouble(0, row) - input.GetDouble(1, row)) / stddev) > threshold;
	});
}

static void ParseOptionKindFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) { return ParseOptionKind(input.GetString(0, row)); });
}

static void ParseExerciseStyleFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) { return ParseExerciseStyle(input.GetString(0, row)); });
}

static void ParseDayCountFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) { return ParseDayCount(input.GetString(0, row)); });
}

static void ParseCompoundingFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) { return ParseCompounding(input.GetString(0, row)); });
}

static void ParseReturnMethodFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) { return ParseReturnMethod(input.GetString(0, row)); });
}

static void NormalizeCurrencyFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) {
		auto currency = input.GetString(0, row);
		StringUtil::Trim(currency);
		currency = StringUtil::Upper(currency);
		if (currency.size() != 3) {
			throw InvalidInputException("Currency must be a three-letter code");
		}
		return currency;
	});
}

static void BusinessDayFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [](const PreparedInputs &input, idx_t row) { return IsBusinessDay(input.GetDate(0, row)); });
}

static void NextPrevBusinessDayFunction(DataChunk &args, ExpressionState &, Vector &result, int direction) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto out = FlatVector::GetDataMutable<date_t>(result);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		int n = args.ColumnCount() >= 3 ? input.GetInt32(2, row) : 1;
		if (n < 0) {
			throw InvalidInputException("business-day offset must be non-negative");
		}
		auto d = input.GetDate(0, row);
		for (int i = 0; i < n;) {
			d = d + direction;
			if (IsBusinessDay(d)) {
				i++;
			}
		}
		out[row] = d;
	}
}

static void BusinessDaysBetweenFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto out = FlatVector::GetDataMutable<int64_t>(result);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row) || input.IsNull(1, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		auto start = input.GetDate(0, row);
		auto end = input.GetDate(1, row);
		int direction = end.days >= start.days ? 1 : -1;
		int64_t count = 0;
		for (auto d = start; d.days != end.days; d = d + direction) {
			if (IsBusinessDay(d)) {
				count += direction;
			}
		}
		out[row] = count;
	}
}

static void SessionDateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto out = FlatVector::GetDataMutable<date_t>(result);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		out[row] = Timestamp::GetDate(input.GetTimestamp(0, row));
	}
}

static void RegularSessionFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto out = FlatVector::GetDataMutable<bool>(result);
	auto open_time = Time::FromTime(9, 30, 0);
	auto close_time = Time::FromTime(16, 0, 0);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		auto ts = input.GetTimestamp(0, row);
		auto date = Timestamp::GetDate(ts);
		auto time = Timestamp::GetTime(ts);
		out[row] = IsBusinessDay(date) && time >= open_time && time <= close_time;
	}
}

static void AddScalar(ExtensionLoader &loader, const string &name, vector<LogicalType> args, LogicalType ret,
                      scalar_function_t func) {
	ScalarFunction scalar(name, std::move(args), std::move(ret), std::move(func));
	scalar.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	loader.RegisterFunction(std::move(scalar));
}

static void AddOverload(ScalarFunctionSet &set, vector<LogicalType> args, LogicalType ret, scalar_function_t func) {
	ScalarFunction scalar(std::move(args), std::move(ret), std::move(func));
	scalar.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	set.AddFunction(std::move(scalar));
}

static void RegisterOptionFunction(ExtensionLoader &loader, const string &name, scalar_function_t func) {
	ScalarFunctionSet set(name);
	AddOverload(set, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                  LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, func);
	AddOverload(set, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                  LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, func);
	loader.RegisterFunction(std::move(set));
}

static void RegisterOptionFunctionWithScale(ExtensionLoader &loader, const string &name, scalar_function_t func) {
	ScalarFunctionSet set(name);
	AddOverload(set, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                  LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, func);
	AddOverload(set, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                  LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, func);
	AddOverload(set, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                  LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR},
	            LogicalType::DOUBLE, func);
	loader.RegisterFunction(std::move(set));
}

} // namespace

void RegisterFinanceScalars(ExtensionLoader &loader) {
	loader.RegisterFunction(ScalarFunction("fin_version", {}, LogicalType::VARCHAR, FinanceVersionFunction));

	AddScalar(loader, "fin_norm_pdf", {LogicalType::DOUBLE}, LogicalType::DOUBLE, NormPDFFunction);
	AddScalar(loader, "fin_norm_cdf", {LogicalType::DOUBLE}, LogicalType::DOUBLE, NormCDFFunction);
	AddScalar(loader, "fin_norm_inv", {LogicalType::DOUBLE}, LogicalType::DOUBLE, NormInvFunction);
	AddScalar(loader, "fin_student_t_cdf", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          StudentTCdfFunction);
	AddScalar(loader, "fin_student_t_inv", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          StudentTInvFunction);
	AddScalar(loader, "fin_chi2_cdf", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, Chi2CdfFunction);
	AddScalar(loader, "fin_chi2_inv", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, Chi2InvFunction);

	ScalarFunctionSet safe_div("fin_safe_div");
	AddOverload(safe_div, {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, SafeDivFunction);
	AddOverload(safe_div, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            SafeDivFunction);
	loader.RegisterFunction(std::move(safe_div));
	AddScalar(loader, "fin_bps", {LogicalType::DOUBLE}, LogicalType::DOUBLE, BpsFunction);
	AddScalar(loader, "fin_from_bps", {LogicalType::DOUBLE}, LogicalType::DOUBLE, FromBpsFunction);
	AddScalar(loader, "fin_clip", {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          ClipFunction);
	ScalarFunctionSet round_tick("fin_round_to_tick");
	AddOverload(round_tick, {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, RoundToTickFunction);
	AddOverload(round_tick, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR}, LogicalType::DOUBLE,
	            RoundToTickFunction);
	loader.RegisterFunction(std::move(round_tick));

	ScalarFunctionSet yearfrac("fin_yearfrac");
	AddOverload(yearfrac, {LogicalType::DATE, LogicalType::DATE}, LogicalType::DOUBLE, YearFracFunction);
	AddOverload(yearfrac, {LogicalType::DATE, LogicalType::DATE, LogicalType::VARCHAR}, LogicalType::DOUBLE,
	            YearFracFunction);
	loader.RegisterFunction(std::move(yearfrac));

	ScalarFunctionSet discount("fin_discount_factor");
	AddOverload(discount, {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, DiscountFactorFunction);
	AddOverload(discount, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR}, LogicalType::DOUBLE,
	            DiscountFactorFunction);
	AddOverload(discount, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR, LogicalType::INTEGER},
	            LogicalType::DOUBLE, DiscountFactorFunction);
	loader.RegisterFunction(std::move(discount));

	ScalarFunctionSet rate_from_discount("fin_rate_from_discount");
	AddOverload(rate_from_discount, {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            RateFromDiscountFunction);
	AddOverload(rate_from_discount, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR}, LogicalType::DOUBLE,
	            RateFromDiscountFunction);
	AddOverload(rate_from_discount,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR, LogicalType::INTEGER},
	            LogicalType::DOUBLE, RateFromDiscountFunction);
	loader.RegisterFunction(std::move(rate_from_discount));
	ScalarFunctionSet forward_rate("fin_forward_rate");
	AddOverload(forward_rate,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, ForwardRateFunction);
	AddOverload(forward_rate,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::VARCHAR},
	            LogicalType::DOUBLE, ForwardRateFunction);
	loader.RegisterFunction(std::move(forward_rate));
	ScalarFunctionSet pv("fin_present_value");
	AddOverload(pv, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            PresentValueFunction);
	AddOverload(pv, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR},
	            LogicalType::DOUBLE, PresentValueFunction);
	loader.RegisterFunction(std::move(pv));
	ScalarFunctionSet fv("fin_future_value");
	AddOverload(fv, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            FutureValueFunction);
	AddOverload(fv, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR},
	            LogicalType::DOUBLE, FutureValueFunction);
	loader.RegisterFunction(std::move(fv));

	ScalarFunctionSet annuity("fin_annuity_payment");
	AddOverload(annuity, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            AnnuityPaymentFunction);
	AddOverload(annuity, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, AnnuityPaymentFunction);
	AddOverload(annuity,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::VARCHAR},
	            LogicalType::DOUBLE, AnnuityPaymentFunction);
	loader.RegisterFunction(std::move(annuity));

	ScalarFunctionSet bond_price("fin_bond_price");
	AddOverload(bond_price, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            BondPriceFunction);
	AddOverload(bond_price, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BondPriceFunction);
	AddOverload(bond_price,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BondPriceFunction);
	loader.RegisterFunction(std::move(bond_price));
	ScalarFunctionSet bond_ytm("fin_bond_ytm");
	AddOverload(bond_ytm, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            BondYTMFunction);
	AddOverload(bond_ytm, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BondYTMFunction);
	AddOverload(bond_ytm,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BondYTMFunction);
	loader.RegisterFunction(std::move(bond_ytm));
	ScalarFunctionSet duration("fin_bond_duration");
	AddOverload(duration, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            BondDurationFunction);
	AddOverload(duration, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BondDurationFunction);
	AddOverload(duration,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BondDurationFunction);
	AddOverload(duration,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE, LogicalType::VARCHAR},
	            LogicalType::DOUBLE, BondDurationFunction);
	loader.RegisterFunction(std::move(duration));
	ScalarFunctionSet convexity("fin_bond_convexity");
	AddOverload(convexity, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            BondConvexityFunction);
	AddOverload(convexity, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BondConvexityFunction);
	AddOverload(convexity,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BondConvexityFunction);
	loader.RegisterFunction(std::move(convexity));
	ScalarFunctionSet dv01("fin_dv01");
	AddOverload(dv01, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, DV01Function);
	AddOverload(dv01, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, DV01Function);
	AddOverload(dv01,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, DV01Function);
	loader.RegisterFunction(std::move(dv01));
	ScalarFunctionSet accrued("fin_accrued_interest");
	AddOverload(accrued, {LogicalType::DATE, LogicalType::DATE, LogicalType::DATE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, AccruedInterestFunction);
	AddOverload(accrued,
	            {LogicalType::DATE, LogicalType::DATE, LogicalType::DATE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, AccruedInterestFunction);
	AddOverload(accrued,
	            {LogicalType::DATE, LogicalType::DATE, LogicalType::DATE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::VARCHAR},
	            LogicalType::DOUBLE, AccruedInterestFunction);
	loader.RegisterFunction(std::move(accrued));
	auto list_double = LogicalType::LIST(LogicalType::DOUBLE);
	auto list_date = LogicalType::LIST(LogicalType::DATE);
	ScalarFunctionSet npv("fin_npv");
	AddOverload(npv, {LogicalType::DOUBLE, list_double}, LogicalType::DOUBLE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "npv"); });
	AddOverload(npv, {list_double, list_double, LogicalType::DOUBLE}, LogicalType::DOUBLE, NPVWithTimesFunction);
	AddOverload(npv, {list_double, list_double, LogicalType::DOUBLE, LogicalType::VARCHAR}, LogicalType::DOUBLE,
	            NPVWithTimesFunction);
	loader.RegisterFunction(std::move(npv));
	ScalarFunctionSet irr("fin_irr");
	AddOverload(irr, {list_double}, LogicalType::DOUBLE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "irr"); });
	AddOverload(irr, {list_double, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "irr"); });
	loader.RegisterFunction(std::move(irr));
	AddScalar(loader, "fin_mirr", {list_double, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "mirr"); });
	ScalarFunctionSet xirr("fin_xirr");
	AddOverload(xirr, {list_double, list_date}, LogicalType::DOUBLE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "xirr"); });
	AddOverload(xirr, {list_double, list_date, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "xirr"); });
	loader.RegisterFunction(std::move(xirr));
	AddScalar(loader, "fin_interpolate_curve", {list_double, list_double, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CurveListFunction(args, state, result, "zero"); });
	AddScalar(loader, "fin_curve_zero_rate", {list_double, list_double, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CurveListFunction(args, state, result, "zero"); });
	AddScalar(loader, "fin_curve_discount_factor", {list_double, list_double, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CurveListFunction(args, state, result, "discount"); });
	AddScalar(loader, "fin_swap_rate", {list_double, list_double}, LogicalType::DOUBLE, SwapRateFunction);
	AddScalar(loader, "fin_fra_rate",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &, Vector &result) {
		          ExecuteDouble(args, result, [](const PreparedInputs &input, idx_t row) {
			          double t1 = input.GetDouble(2, row);
			          double t2 = input.GetDouble(3, row);
			          if (!(t2 > t1)) {
				          throw InvalidInputException("fin_fra_rate requires t2 > t1");
			          }
			          return (input.GetDouble(1, row) * t2 - input.GetDouble(0, row) * t1) / (t2 - t1);
		          });
	          });

	AddScalar(loader, "fin_option_payoff", {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE, OptionPayoffFunction);
	ScalarFunctionSet forward_price("fin_forward_price");
	AddOverload(forward_price, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            ForwardPriceFunction);
	AddOverload(forward_price,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, ForwardPriceFunction);
	loader.RegisterFunction(std::move(forward_price));
	ScalarFunctionSet parity("fin_put_call_parity");
	AddOverload(parity,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, PutCallParityFunction);
	AddOverload(parity,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, PutCallParityFunction);
	loader.RegisterFunction(std::move(parity));
	ScalarFunctionSet d1("fin_bsm_d1");
	AddOverload(d1, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                 LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMD1Function);
	AddOverload(d1, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                 LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMD1Function);
	loader.RegisterFunction(std::move(d1));
	ScalarFunctionSet d2("fin_bsm_d2");
	AddOverload(d2, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                 LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMD2Function);
	AddOverload(d2, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                 LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMD2Function);
	loader.RegisterFunction(std::move(d2));
	RegisterOptionFunction(loader, "fin_bsm_price", BSMPriceFunction);
	RegisterOptionFunction(loader, "fin_bsm_delta", BSMDeltaFunction);
	ScalarFunctionSet gamma("fin_bsm_gamma");
	AddOverload(gamma, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                    LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMGammaFunction);
	AddOverload(gamma, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                    LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMGammaFunction);
	loader.RegisterFunction(std::move(gamma));
	RegisterOptionFunctionWithScale(loader, "fin_bsm_vega", BSMVegaFunction);
	RegisterOptionFunctionWithScale(loader, "fin_bsm_theta", BSMThetaFunction);
	RegisterOptionFunctionWithScale(loader, "fin_bsm_rho", BSMRhoFunction);
	ScalarFunctionSet greeks("fin_bsm_greeks");
	AddOverload(greeks,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            GreeksType(), BSMGreeksFunction);
	AddOverload(greeks,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            GreeksType(), BSMGreeksFunction);
	loader.RegisterFunction(std::move(greeks));
	ScalarFunctionSet all("fin_bsm_all");
	AddOverload(all,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            BSMAllType(), BSMAllFunction);
	AddOverload(all,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            BSMAllType(), BSMAllFunction);
	loader.RegisterFunction(std::move(all));
	ScalarFunctionSet iv("fin_bsm_implied_vol");
	AddOverload(iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMImpliedVolFunction);
	AddOverload(iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMImpliedVolFunction);
	AddOverload(iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMImpliedVolFunction);
	AddOverload(iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMImpliedVolFunction);
	AddOverload(iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BSMImpliedVolFunction);
	loader.RegisterFunction(std::move(iv));
	RegisterOptionFunction(loader, "fin_bsm_prob_itm", BSMProbITMFunction);
	RegisterOptionFunction(loader, "fin_bsm_prob_touch", BSMProbTouchFunction);
	RegisterOptionFunction(loader, "fin_bsm_elasticity", BSMElasticityFunction);
	RegisterOptionFunction(loader, "fin_bsm_vanna", BSMHigherGreekScalar("vanna"));
	RegisterOptionFunction(loader, "fin_bsm_vomma", BSMHigherGreekScalar("vomma"));
	RegisterOptionFunction(loader, "fin_bsm_speed", BSMHigherGreekScalar("speed"));
	RegisterOptionFunction(loader, "fin_bsm_zomma", BSMHigherGreekScalar("zomma"));
	RegisterOptionFunction(loader, "fin_bsm_ultima", BSMHigherGreekScalar("ultima"));
	RegisterOptionFunction(loader, "fin_bsm_charm", BSMHigherGreekScalar("charm"));
	RegisterOptionFunction(loader, "fin_bsm_color", BSMHigherGreekScalar("color"));
	ScalarFunctionSet price_dates("fin_bsm_price_dates");
	AddOverload(price_dates,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DATE,
	             LogicalType::DATE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMPriceDatesFunction);
	AddOverload(price_dates,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DATE,
	             LogicalType::DATE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMPriceDatesFunction);
	AddOverload(price_dates,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DATE,
	             LogicalType::DATE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::VARCHAR},
	            LogicalType::DOUBLE, BSMPriceDatesFunction);
	loader.RegisterFunction(std::move(price_dates));
	AddScalar(loader, "fin_black76_price",
	          {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE, Black76PriceFunction);
	AddScalar(loader, "fin_black76_greeks",
	          {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE},
	          GreeksType(), Black76GreeksFunction);
	ScalarFunctionSet black_iv("fin_black76_implied_vol");
	AddOverload(black_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, Black76ImpliedVolFunction);
	AddOverload(black_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, Black76ImpliedVolFunction);
	AddOverload(black_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, Black76ImpliedVolFunction);
	loader.RegisterFunction(std::move(black_iv));
	AddScalar(loader, "fin_bachelier_price",
	          {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE, BachelierPriceFunction);
	AddScalar(loader, "fin_bachelier_greeks",
	          {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE},
	          GreeksType(), BachelierGreeksFunction);
	ScalarFunctionSet bach_iv("fin_bachelier_implied_vol");
	AddOverload(bach_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BachelierImpliedVolFunction);
	AddOverload(bach_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BachelierImpliedVolFunction);
	AddOverload(bach_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BachelierImpliedVolFunction);
	loader.RegisterFunction(std::move(bach_iv));
	ScalarFunctionSet binomial("fin_binomial_price");
	AddOverload(binomial, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                       LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BinomialPriceFunction);
	AddOverload(binomial, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                       LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BinomialPriceFunction);
	AddOverload(binomial, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                       LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BinomialPriceFunction);
	AddOverload(binomial,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::VARCHAR},
	            LogicalType::DOUBLE, BinomialPriceFunction);
	AddOverload(binomial,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::VARCHAR, LogicalType::VARCHAR},
	            LogicalType::DOUBLE, BinomialPriceFunction);
	loader.RegisterFunction(std::move(binomial));
	ScalarFunctionSet digital("fin_digital_price");
	AddOverload(digital, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                      LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, DigitalPriceFunction);
	AddOverload(digital, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                      LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, DigitalPriceFunction);
	AddOverload(digital, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                      LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, DigitalPriceFunction);
	loader.RegisterFunction(std::move(digital));
	RegisterOptionFunction(loader, "fin_asset_or_nothing_price", AssetOrNothingPriceFunction);
	RegisterOptionFunction(loader, "fin_asian_geometric_price", AsianGeometricPriceFunction);
	ScalarFunctionSet barrier("fin_barrier_price");
	AddOverload(barrier,
	            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BarrierPriceFunction);
	AddOverload(barrier,
	            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BarrierPriceFunction);
	AddOverload(barrier,
	            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BarrierPriceFunction);
	loader.RegisterFunction(std::move(barrier));
	ScalarFunctionSet sabr("fin_sabr_vol");
	AddOverload(sabr,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, SABRVolFunction);
	AddOverload(sabr,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, SABRVolFunction);
	loader.RegisterFunction(std::move(sabr));
	AddScalar(loader, "fin_svi_total_variance",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE, SviTotalVarianceFunction);
	AddScalar(loader, "fin_svi_vol",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE, SviVolFunction);

	AddScalar(loader, "fin_avg_price",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "avg"); });
	AddScalar(loader, "fin_typ_price", {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "typ"); });
	AddScalar(loader, "fin_median_price", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "median"); });
	AddScalar(loader, "fin_weighted_close", {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "weighted"); });
	AddScalar(loader, "fin_mid", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "mid"); });
	AddScalar(loader, "fin_spread", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "spread"); });
	AddScalar(loader, "fin_spread_bps", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "spread_bps"); });
	AddScalar(loader, "fin_microprice",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "microprice"); });
	AddScalar(loader, "fin_order_imbalance", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "imbalance"); });
	AddScalar(loader, "fin_queue_imbalance", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "imbalance"); });
	ScalarFunctionSet trade_sign("fin_trade_sign");
	AddOverload(trade_sign, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            TradeSignFunction);
	AddOverload(trade_sign, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, TradeSignFunction);
	loader.RegisterFunction(std::move(trade_sign));

	auto double_list = LogicalType::LIST(LogicalType::DOUBLE);
	auto matrix_type = LogicalType::LIST(double_list);
	AddScalar(loader, "fin_dot", {double_list, double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "dot"); });
	AddScalar(loader, "fin_vector_sum", {double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "sum"); });
	AddScalar(loader, "fin_vector_mean", {double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "mean"); });
	AddScalar(loader, "fin_vector_scale", {double_list, LogicalType::DOUBLE}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "scale"); });
	AddScalar(loader, "fin_vector_add", {double_list, double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "add"); });
	AddScalar(loader, "fin_vector_sub", {double_list, double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "sub"); });
	AddScalar(loader, "fin_vector_normalize_sum", {double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "normalize"); });
	AddScalar(loader, "fin_turnover", {double_list, double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "turnover"); });
	ScalarFunctionSet equal_weights("fin_equal_weights");
	AddOverload(equal_weights, {LogicalType::INTEGER}, double_list, EqualWeightsFunction);
	AddOverload(equal_weights, {LogicalType::BIGINT}, double_list, EqualWeightsFunction);
	loader.RegisterFunction(std::move(equal_weights));
	AddScalar(loader, "fin_inverse_vol_weights", {double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "inverse_vol"); });
	child_list_t<LogicalType> shape_children;
	shape_children.emplace_back("rows", LogicalType::BIGINT);
	shape_children.emplace_back("cols", LogicalType::BIGINT);
	AddScalar(loader, "fin_matrix_shape", {matrix_type}, LogicalType::STRUCT(std::move(shape_children)), MatrixShapeFunction);
	AddScalar(loader, "fin_matrix_transpose", {matrix_type}, matrix_type,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "transpose"); });
	AddScalar(loader, "fin_matrix_vecmul", {matrix_type, double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixFunction(args, state, result, "vecmul"); });
	AddScalar(loader, "fin_matrix_mul", {matrix_type, matrix_type}, matrix_type, MatrixMulFunction);
	AddScalar(loader, "fin_matrix_cholesky", {matrix_type}, matrix_type,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "cholesky"); });
	ScalarFunctionSet matrix_psd("fin_matrix_is_psd");
	AddOverload(matrix_psd, {matrix_type}, LogicalType::BOOLEAN, MatrixIsPsdFunction);
	AddOverload(matrix_psd, {matrix_type, LogicalType::DOUBLE}, LogicalType::BOOLEAN, MatrixIsPsdFunction);
	loader.RegisterFunction(std::move(matrix_psd));
	ScalarFunctionSet nearest_psd("fin_nearest_psd");
	AddOverload(nearest_psd, {matrix_type}, matrix_type,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "nearest_psd"); });
	AddOverload(nearest_psd, {matrix_type, LogicalType::VARCHAR}, matrix_type,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "nearest_psd"); });
	loader.RegisterFunction(std::move(nearest_psd));
	AddScalar(loader, "fin_portfolio_return", {double_list, double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "dot"); });
	AddScalar(loader, "fin_portfolio_expected_return", {double_list, double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "dot"); });
	AddScalar(loader, "fin_portfolio_variance", {double_list, matrix_type}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PortfolioScalarFunction(args, state, result, "variance"); });
	AddScalar(loader, "fin_portfolio_vol", {double_list, matrix_type}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PortfolioScalarFunction(args, state, result, "vol"); });
	ScalarFunctionSet portfolio_sharpe("fin_portfolio_sharpe");
	AddOverload(portfolio_sharpe, {double_list, double_list, matrix_type}, LogicalType::DOUBLE, PortfolioSharpeFunction);
	AddOverload(portfolio_sharpe, {double_list, double_list, matrix_type, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            PortfolioSharpeFunction);
	loader.RegisterFunction(std::move(portfolio_sharpe));

	AddScalar(loader, "fin_validate_ohlc",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, ValidationType(),
	          ValidateOhlcFunction);
	ScalarFunctionSet valid_return("fin_validate_return");
	AddOverload(valid_return, {LogicalType::DOUBLE}, LogicalType::BOOLEAN, ValidateReturnFunction);
	AddOverload(valid_return, {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::BOOLEAN, ValidateReturnFunction);
	loader.RegisterFunction(std::move(valid_return));
	AddScalar(loader, "fin_is_finite", {LogicalType::DOUBLE}, LogicalType::BOOLEAN, IsFiniteFunction);
	ScalarFunctionSet is_price("fin_is_price");
	AddOverload(is_price, {LogicalType::DOUBLE}, LogicalType::BOOLEAN, IsPriceFunction);
	AddOverload(is_price, {LogicalType::DOUBLE, LogicalType::BOOLEAN}, LogicalType::BOOLEAN, IsPriceFunction);
	loader.RegisterFunction(std::move(is_price));
	ScalarFunctionSet is_rate("fin_is_rate");
	AddOverload(is_rate, {LogicalType::DOUBLE}, LogicalType::BOOLEAN, IsRateFunction);
	AddOverload(is_rate, {LogicalType::DOUBLE, LogicalType::BOOLEAN}, LogicalType::BOOLEAN, IsRateFunction);
	loader.RegisterFunction(std::move(is_rate));
	AddScalar(loader, "fin_is_vol", {LogicalType::DOUBLE}, LogicalType::BOOLEAN, IsVolFunction);
	ScalarFunctionSet outlier("fin_is_outlier_zscore");
	AddOverload(outlier, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::BOOLEAN,
	            IsOutlierZScoreFunction);
	AddOverload(outlier,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::BOOLEAN, IsOutlierZScoreFunction);
	loader.RegisterFunction(std::move(outlier));
	AddScalar(loader, "fin_parse_option_kind", {LogicalType::VARCHAR}, LogicalType::VARCHAR, ParseOptionKindFunction);
	AddScalar(loader, "fin_parse_exercise_style", {LogicalType::VARCHAR}, LogicalType::VARCHAR,
	          ParseExerciseStyleFunction);
	AddScalar(loader, "fin_parse_day_count", {LogicalType::VARCHAR}, LogicalType::VARCHAR, ParseDayCountFunction);
	AddScalar(loader, "fin_parse_compounding", {LogicalType::VARCHAR}, LogicalType::VARCHAR, ParseCompoundingFunction);
	AddScalar(loader, "fin_parse_return_method", {LogicalType::VARCHAR}, LogicalType::VARCHAR, ParseReturnMethodFunction);
	AddScalar(loader, "fin_normalize_currency", {LogicalType::VARCHAR}, LogicalType::VARCHAR, NormalizeCurrencyFunction);
	ScalarFunctionSet is_bd("fin_is_business_day");
	AddOverload(is_bd, {LogicalType::DATE}, LogicalType::BOOLEAN, BusinessDayFunction);
	AddOverload(is_bd, {LogicalType::DATE, LogicalType::VARCHAR}, LogicalType::BOOLEAN, BusinessDayFunction);
	loader.RegisterFunction(std::move(is_bd));
	ScalarFunctionSet next_bd("fin_next_business_day");
	AddOverload(next_bd, {LogicalType::DATE}, LogicalType::DATE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, 1); });
	AddOverload(next_bd, {LogicalType::DATE, LogicalType::VARCHAR, LogicalType::INTEGER}, LogicalType::DATE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, 1); });
	loader.RegisterFunction(std::move(next_bd));
	ScalarFunctionSet prev_bd("fin_prev_business_day");
	AddOverload(prev_bd, {LogicalType::DATE}, LogicalType::DATE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, -1); });
	AddOverload(prev_bd, {LogicalType::DATE, LogicalType::VARCHAR, LogicalType::INTEGER}, LogicalType::DATE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, -1); });
	loader.RegisterFunction(std::move(prev_bd));
	ScalarFunctionSet bd_between("fin_business_days_between");
	AddOverload(bd_between, {LogicalType::DATE, LogicalType::DATE}, LogicalType::BIGINT, BusinessDaysBetweenFunction);
	AddOverload(bd_between, {LogicalType::DATE, LogicalType::DATE, LogicalType::VARCHAR}, LogicalType::BIGINT,
	            BusinessDaysBetweenFunction);
	loader.RegisterFunction(std::move(bd_between));
	ScalarFunctionSet session_date("fin_session_date");
	AddOverload(session_date, {LogicalType::TIMESTAMP, LogicalType::VARCHAR}, LogicalType::DATE, SessionDateFunction);
	AddOverload(session_date, {LogicalType::TIMESTAMP, LogicalType::VARCHAR, LogicalType::VARCHAR}, LogicalType::DATE,
	            SessionDateFunction);
	loader.RegisterFunction(std::move(session_date));
	ScalarFunctionSet regular_session("fin_is_regular_session");
	AddOverload(regular_session, {LogicalType::TIMESTAMP, LogicalType::VARCHAR}, LogicalType::BOOLEAN,
	            RegularSessionFunction);
	AddOverload(regular_session, {LogicalType::TIMESTAMP, LogicalType::VARCHAR, LogicalType::VARCHAR},
	            LogicalType::BOOLEAN, RegularSessionFunction);
	loader.RegisterFunction(std::move(regular_session));
}

} // namespace duckdb
