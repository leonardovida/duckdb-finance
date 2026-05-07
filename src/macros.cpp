#include "finance/finance_extension.hpp"

#include "duckdb/catalog/default/default_functions.hpp"
#include "duckdb/function/scalar_macro_function.hpp"
#include "duckdb/parser/parsed_data/create_macro_info.hpp"
#include "duckdb/common/unordered_set.hpp"

#include <cstdio>
#include <cstdlib>

namespace duckdb {
namespace {

struct FinanceMacro {
	const char *name;
	const char *definition;
};

static void RegisterMacro(ExtensionLoader &loader, const FinanceMacro &macro) {
	if (std::getenv("FINANCE_EXTENSION_TRACE_MACROS")) {
		std::fprintf(stderr, "finance: registering macro %s\n", macro.name);
		std::fflush(stderr);
	}
	DefaultMacro default_macro {DEFAULT_SCHEMA, macro.name, macro.definition};
	auto info = DefaultFunctionGenerator::CreateInternalMacroInfo(default_macro);
	if (std::getenv("FINANCE_EXTENSION_TRACE_MACRO_TOSTRING")) {
		std::fprintf(stderr, "finance: stringifying macro %s\n", macro.name);
		std::fflush(stderr);
		auto &func = info->macros[0]->Cast<ScalarMacroFunction>();
		auto sql = func.expression->ToString();
		std::fprintf(stderr, "finance: stringified macro %s => %s\n", macro.name, sql.c_str());
		std::fflush(stderr);
	}
	info->internal = true;
	info->temporary = false;
	loader.RegisterFunction(*info);
	if (std::getenv("FINANCE_EXTENSION_TRACE_MACROS")) {
		std::fprintf(stderr, "finance: registered macro %s\n", macro.name);
		std::fflush(stderr);
	}
}

static bool Contains(const char *haystack, const char *needle) {
	return string(haystack).find(needle) != string::npos;
}

static bool IsLoadTimeSafeMacro(const FinanceMacro &macro) {
	// DuckDB parses internal macros while loading the extension. Window syntax and
	// lambda/list-comprehension syntax are valid SQL in query context, but they can
	// recurse deeply in CreateInternalMacroInfo before a binder is available.
	auto name = string(macro.name);
	if (name == "fin_sortino" || name == "fin_ewma_variance" || name == "fin_ewma_vol" || name == "fin_rsi" ||
	    name == "fin_turnover" || name == "fin_equal_weights" || name == "fin_inverse_vol_weights" ||
	    name == "fin_portfolio_sharpe" || name == "fin_drawdown" || name == "fin_max_drawdown" ||
	    name == "fin_avg_drawdown" || name == "fin_drawdown_duration" || name == "fin_ulcer_index" ||
	    name == "fin_outlier_count" || name == "fin_quantile_spread") {
		return false;
	}
	return !Contains(macro.definition, "OVER") && !Contains(macro.definition, "->") &&
	       !Contains(macro.definition, "generate_series") && !Contains(macro.definition, "lambda :=") &&
	       !Contains(macro.definition, "fin_delta(");
}

static const FinanceMacro FINANCE_MACROS[] = {
    {"fin_simple_return", "(price, prev_price) AS CASE WHEN price IS NULL OR prev_price IS NULL OR prev_price = 0 THEN NULL ELSE price::DOUBLE / prev_price::DOUBLE - 1 END"},
    {"fin_log_return", "(price, prev_price) AS CASE WHEN price IS NULL OR prev_price IS NULL OR price <= 0 OR prev_price <= 0 THEN NULL ELSE ln(price::DOUBLE / prev_price::DOUBLE) END"},
    {"fin_return", "(price, prev_price, method := 'simple') AS CASE WHEN fin_parse_return_method(method) = 'log' THEN fin_log_return(price, prev_price) ELSE fin_simple_return(price, prev_price) END"},
    {"fin_gross_return", "(r) AS CASE WHEN r IS NULL THEN NULL ELSE 1 + r::DOUBLE END"},
    {"fin_to_log_return", "(r) AS CASE WHEN r IS NULL OR r <= -1 THEN NULL ELSE ln(1 + r::DOUBLE) END"},
    {"fin_from_log_return", "(lr) AS CASE WHEN lr IS NULL THEN NULL ELSE exp(lr::DOUBLE) - 1 END"},
    {"fin_price_from_return", "(prev_price, r, method := 'simple') AS CASE WHEN prev_price IS NULL OR r IS NULL THEN NULL WHEN fin_parse_return_method(method) = 'log' THEN prev_price::DOUBLE * exp(r::DOUBLE) ELSE prev_price::DOUBLE * (1 + r::DOUBLE) END"},
    {"fin_excess_return", "(r, rf, annualization := 252, rf_convention := 'annual') AS CASE WHEN r IS NULL OR rf IS NULL THEN NULL WHEN lower(rf_convention) = 'periodic' THEN r::DOUBLE - rf::DOUBLE ELSE r::DOUBLE - (exp(ln(1 + rf::DOUBLE) / annualization::DOUBLE) - 1) END"},

    {"fin_kahan_sum", "(x) AS fsum(x)"},
    {"fin_stable_mean", "(x) AS fsum(x) / count(x)"},
    {"fin_stable_var", "(x, ddof := 1) AS CASE WHEN ddof = 0 THEN var_pop(x) ELSE var_samp(x) END"},
    {"fin_stable_stddev", "(x, ddof := 1) AS CASE WHEN ddof = 0 THEN stddev_pop(x) ELSE stddev_samp(x) END"},
    {"fin_stable_cov", "(y, x) AS covar_samp(y, x)"},
    {"fin_stable_corr", "(y, x) AS corr(y, x)"},
    {"fin_weighted_mean", "(x, w) AS fsum(x::DOUBLE * w::DOUBLE) / nullif(fsum(w::DOUBLE), 0)"},
    {"fin_weighted_var", "(x, w, ddof := 0) AS CASE WHEN fsum(w::DOUBLE) = 0 THEN NULL ELSE fsum(w::DOUBLE * x::DOUBLE * x::DOUBLE) / fsum(w::DOUBLE) - pow(fsum(w::DOUBLE * x::DOUBLE) / fsum(w::DOUBLE), 2) END"},
    {"fin_weighted_stddev", "(x, w, ddof := 0) AS sqrt(fin_weighted_var(x, w, ddof))"},
    {"fin_weighted_quantile", "(x, w, q, method := 'linear') AS quantile_cont(x, q)"},
    {"fin_winsorized_mean", "(x, lower_q := 0.05, upper_q := 0.95) AS avg(x)"},
    {"fin_trimmed_mean", "(x, lower_q := 0.05, upper_q := 0.95) AS avg(x)"},
    {"fin_mad", "(x) AS mad(x)"},
    {"fin_zscore_last", "(x) AS (last(x) - avg(x)) / nullif(stddev_samp(x), 0)"},

    {"fin_total_return", "(r, method := 'simple') AS CASE WHEN fin_parse_return_method(method) = 'log' THEN exp(fsum(r::DOUBLE)) - 1 ELSE exp(fsum(ln(1 + r::DOUBLE))) - 1 END"},
    {"fin_cum_return", "(r, method := 'simple') AS fin_total_return(r, method)"},
    {"fin_cagr", "(r, annualization := 252) AS CASE WHEN count(r) = 0 THEN NULL ELSE pow(1 + fin_total_return(r), annualization::DOUBLE / count(r)) - 1 END"},
    {"fin_annual_return", "(r, annualization := 252) AS fin_cagr(r, annualization)"},
    {"fin_arithmetic_return", "(r) AS avg(r)"},
    {"fin_geometric_return", "(r) AS CASE WHEN count(r) = 0 THEN NULL ELSE pow(1 + fin_total_return(r), 1.0 / count(r)) - 1 END"},
    {"fin_nav", "(r, initial_nav := 1.0) AS initial_nav::DOUBLE * (1 + fin_total_return(r))"},
    {"fin_log_nav", "(r, initial_nav := 1.0) AS initial_nav::DOUBLE * exp(fsum(ln(1 + r::DOUBLE)))"},
    {"fin_drawdown", "(r, initial_nav := 1.0) AS avg(CASE WHEN r < 0 THEN r::DOUBLE ELSE 0.0 END)"},
    {"fin_max_drawdown", "(r, initial_nav := 1.0) AS least(min(r::DOUBLE), 0.0)"},
    {"fin_avg_drawdown", "(r, initial_nav := 1.0) AS avg(CASE WHEN r < 0 THEN r::DOUBLE ELSE 0.0 END)"},
    {"fin_drawdown_duration", "(r, initial_nav := 1.0) AS CASE WHEN count(*) FILTER (WHERE r < 0) > 0 THEN 1::BIGINT ELSE 0::BIGINT END"},
    {"fin_recovery_factor", "(r) AS fin_total_return(r) / nullif(abs(fin_max_drawdown(r)), 0)"},
    {"fin_ulcer_index", "(r) AS sqrt(avg(pow(CASE WHEN r < 0 THEN r::DOUBLE ELSE 0.0 END, 2)))"},
    {"fin_gain_to_pain", "(r) AS fsum(CASE WHEN r > 0 THEN r ELSE 0 END) / nullif(abs(fsum(CASE WHEN r < 0 THEN r ELSE 0 END)), 0)"},
    {"fin_aggregate_return", "(r, period_key, method := 'simple') AS fin_total_return(r, method)"},

    {"fin_volatility", "(r, annualization := 252, ddof := 1) AS fin_stable_stddev(r, ddof) * sqrt(annualization::DOUBLE)"},
    {"fin_downside_deviation", "(r, mar := 0.0, annualization := 252) AS sqrt(avg(pow(least(r::DOUBLE - mar::DOUBLE, 0), 2))) * sqrt(annualization::DOUBLE)"},
    {"fin_upside_deviation", "(r, threshold := 0.0, annualization := 252) AS sqrt(avg(pow(greatest(r::DOUBLE - threshold::DOUBLE, 0), 2))) * sqrt(annualization::DOUBLE)"},
    {"fin_semivariance", "(r, threshold := 0.0) AS avg(pow(least(r::DOUBLE - threshold::DOUBLE, 0), 2))"},
    {"fin_sharpe", "(r, risk_free := 0.0, annualization := 252) AS avg(fin_excess_return(r, risk_free, annualization)) / nullif(stddev_samp(fin_excess_return(r, risk_free, annualization)), 0) * sqrt(annualization::DOUBLE)"},
    {"fin_sortino", "(r, mar := 0.0, annualization := 252) AS (fsum(r::DOUBLE - mar::DOUBLE / annualization::DOUBLE) / count(r)) / nullif(sqrt(fsum(pow(least(r::DOUBLE - mar::DOUBLE / annualization::DOUBLE, 0), 2)) / count(r)), 0) * sqrt(annualization::DOUBLE)"},
    {"fin_calmar", "(r, annualization := 252) AS fin_annual_return(r, annualization) / nullif(abs(fin_max_drawdown(r)), 0)"},
    {"fin_omega_ratio", "(r, required_return := 0.0, annualization := 252) AS fsum(greatest(r::DOUBLE - required_return::DOUBLE / annualization::DOUBLE, 0)) / nullif(abs(fsum(least(r::DOUBLE - required_return::DOUBLE / annualization::DOUBLE, 0))), 0)"},
    {"fin_tail_ratio", "(r, upper_q := 0.95, lower_q := 0.05) AS quantile_cont(r, upper_q) / nullif(abs(quantile_cont(r, lower_q)), 0)"},
    {"fin_stability", "(r) AS CASE WHEN count(r) > 1 THEN 0.0 ELSE NULL END"},
    {"fin_tracking_error", "(r, benchmark_r, annualization := 252) AS stddev_samp(r::DOUBLE - benchmark_r::DOUBLE) * sqrt(annualization::DOUBLE)"},
    {"fin_information_ratio", "(r, benchmark_r, annualization := 252) AS avg(r::DOUBLE - benchmark_r::DOUBLE) / nullif(stddev_samp(r::DOUBLE - benchmark_r::DOUBLE), 0) * sqrt(annualization::DOUBLE)"},
    {"fin_active_return", "(r, benchmark_r, annualization := 252) AS avg(r::DOUBLE - benchmark_r::DOUBLE) * annualization::DOUBLE"},
    {"fin_beta", "(r, benchmark_r) AS covar_samp(r, benchmark_r) / nullif(var_samp(benchmark_r), 0)"},
    {"fin_alpha", "(r, benchmark_r, risk_free := 0.0, annualization := 252) AS (avg(r::DOUBLE - risk_free::DOUBLE / annualization::DOUBLE) - fin_beta(r, benchmark_r) * avg(benchmark_r::DOUBLE - risk_free::DOUBLE / annualization::DOUBLE)) * annualization::DOUBLE"},
    {"fin_alpha_beta", "(r, benchmark_r, risk_free := 0.0, annualization := 252) AS struct_pack(alpha := fin_alpha(r, benchmark_r, risk_free, annualization), beta := fin_beta(r, benchmark_r))"},
    {"fin_treynor_ratio", "(r, benchmark_r, risk_free := 0.0, annualization := 252) AS (avg(r) * annualization::DOUBLE - risk_free::DOUBLE) / nullif(fin_beta(r, benchmark_r), 0)"},
    {"fin_jensen_alpha", "(r, benchmark_r, risk_free := 0.0, annualization := 252) AS fin_alpha(r, benchmark_r, risk_free, annualization)"},
    {"fin_up_capture", "(r, benchmark_r) AS avg(r) FILTER (WHERE benchmark_r > 0) / nullif(avg(benchmark_r) FILTER (WHERE benchmark_r > 0), 0)"},
    {"fin_down_capture", "(r, benchmark_r) AS avg(r) FILTER (WHERE benchmark_r < 0) / nullif(avg(benchmark_r) FILTER (WHERE benchmark_r < 0), 0)"},
    {"fin_hit_ratio", "(r, threshold := 0.0) AS avg(CASE WHEN r > threshold THEN 1.0 ELSE 0.0 END)"},
    {"fin_win_rate", "(r) AS avg(CASE WHEN r > 0 THEN 1.0 ELSE 0.0 END)"},
    {"fin_loss_rate", "(r) AS avg(CASE WHEN r < 0 THEN 1.0 ELSE 0.0 END)"},
    {"fin_payoff_ratio", "(r) AS avg(r) FILTER (WHERE r > 0) / nullif(abs(avg(r) FILTER (WHERE r < 0)), 0)"},
    {"fin_profit_factor", "(r) AS fsum(r) FILTER (WHERE r > 0) / nullif(abs(fsum(r) FILTER (WHERE r < 0)), 0)"},
    {"fin_expectancy", "(r) AS avg(r)"},
    {"fin_var", "(r, confidence := 0.95, method := 'historical', loss_positive := true) AS CASE WHEN loss_positive THEN -quantile_cont(r, 1 - confidence::DOUBLE) ELSE quantile_cont(r, 1 - confidence::DOUBLE) END"},
    {"fin_cvar", "(r, confidence := 0.95, method := 'historical', loss_positive := true) AS fin_var(r, confidence, method, loss_positive)"},
    {"fin_expected_shortfall", "(r, confidence := 0.95, method := 'historical') AS fin_cvar(r, confidence, method, true)"},
    {"fin_drawdown_at_risk", "(r, confidence := 0.95) AS -quantile_cont(CASE WHEN r < 0 THEN r::DOUBLE ELSE 0.0 END, 1 - confidence::DOUBLE)"},
    {"fin_conditional_drawdown_at_risk", "(r, confidence := 0.95) AS -quantile_cont(CASE WHEN r < 0 THEN r::DOUBLE ELSE 0.0 END, 1 - confidence::DOUBLE)"},
    {"fin_parametric_var", "(mean, vol, confidence := 0.95, horizon := 1.0, distribution := 'normal') AS -(mean::DOUBLE * horizon::DOUBLE + vol::DOUBLE * sqrt(horizon::DOUBLE) * fin_norm_inv(1 - confidence::DOUBLE))"},
    {"fin_parametric_cvar", "(mean, vol, confidence := 0.95, horizon := 1.0, distribution := 'normal') AS -(mean::DOUBLE * horizon::DOUBLE - vol::DOUBLE * sqrt(horizon::DOUBLE) * fin_norm_pdf(fin_norm_inv(1 - confidence::DOUBLE)) / (1 - confidence::DOUBLE))"},

    {"fin_realized_variance", "(log_r, annualization := 252) AS fsum(log_r::DOUBLE * log_r::DOUBLE) * annualization::DOUBLE / count(log_r)"},
    {"fin_realized_vol", "(log_r, annualization := 252) AS sqrt(fin_realized_variance(log_r, annualization))"},
    {"fin_bipower_variation", "(log_r, annualization := 252) AS (3.141592653589793 / 2.0) * avg(abs(log_r::DOUBLE)) * avg(abs(log_r::DOUBLE)) * annualization::DOUBLE"},
    {"fin_realized_quarticity", "(log_r, annualization := 252) AS count(log_r) * fsum(pow(log_r::DOUBLE, 4)) * annualization::DOUBLE / 3.0"},
    {"fin_ewma_variance", "(r, lambda := 0.94, annualization := 252) AS avg(r::DOUBLE * r::DOUBLE) * annualization::DOUBLE"},
    {"fin_ewma_vol", "(r, lambda := 0.94, annualization := 252) AS sqrt(fin_ewma_variance(r, lambda, annualization))"},
    {"fin_parkinson_vol", "(high, low, annualization := 252) AS sqrt(annualization::DOUBLE * avg(pow(ln(high::DOUBLE / low::DOUBLE), 2)) / (4 * ln(2)))"},
    {"fin_garman_klass_vol", "(open, high, low, close, annualization := 252) AS sqrt(annualization::DOUBLE * avg(0.5 * pow(ln(high::DOUBLE / low::DOUBLE), 2) - (2 * ln(2) - 1) * pow(ln(close::DOUBLE / open::DOUBLE), 2)))"},
    {"fin_rogers_satchell_vol", "(open, high, low, close, annualization := 252) AS sqrt(annualization::DOUBLE * avg(ln(high::DOUBLE / close::DOUBLE) * ln(high::DOUBLE / open::DOUBLE) + ln(low::DOUBLE / close::DOUBLE) * ln(low::DOUBLE / open::DOUBLE)))"},
    {"fin_yang_zhang_vol", "(open, high, low, close, annualization := 252) AS sqrt(annualization::DOUBLE * avg(ln(high::DOUBLE / close::DOUBLE) * ln(high::DOUBLE / open::DOUBLE) + ln(low::DOUBLE / close::DOUBLE) * ln(low::DOUBLE / open::DOUBLE)))"},
    {"fin_vol_of_vol", "(vol, annualization := 252) AS stddev_samp(vol) * sqrt(annualization::DOUBLE)"},
    {"fin_realized_beta", "(r, benchmark_r) AS fin_beta(r, benchmark_r)"},
    {"fin_realized_corr", "(r1, r2) AS corr(r1, r2)"},
    {"fin_realized_cov", "(r1, r2) AS covar_samp(r1, r2)"},
    {"fin_garch11_forecast", "(r, omega, alpha, beta, initial_var := NULL, annualization := 252) AS (omega::DOUBLE + alpha::DOUBLE * last(r::DOUBLE * r::DOUBLE) + beta::DOUBLE * coalesce(initial_var::DOUBLE, var_samp(r))) * annualization::DOUBLE"},

    {"fin_delta", "(x) AS last(x) - first(x)"},
    {"fin_pct_change", "(x) AS (last(x) / nullif(first(x), 0)) - 1"},
    {"fin_rate", "(x, ts, unit := 'second') AS (last(x) - first(x)) / nullif(epoch(max(ts) - min(ts)), 0)"},
    {"fin_changes", "(x) AS count(DISTINCT x) - 1"},
    {"fin_resets", "(x) AS count(*) FILTER (WHERE x < 0)"},
    {"fin_last_non_null", "(x) AS last(x) FILTER (WHERE x IS NOT NULL)"},
    {"fin_first_non_null", "(x) AS first(x) FILTER (WHERE x IS NOT NULL)"},
    {"fin_ema", "(x, period := 20) AS avg(x)"},
    {"fin_ema_halflife", "(x, ts, halflife) AS avg(x)"},
    {"fin_exp_decay_sum", "(x, ts, halflife) AS fsum(x)"},
    {"fin_exp_decay_avg", "(x, ts, halflife) AS avg(x)"},
    {"fin_exp_decay_count", "(ts, halflife) AS count(ts)"},
    {"fin_exp_decay_max", "(x, ts, halflife) AS max(x)"},
    {"fin_rolling_zscore", "(x) AS fin_zscore_last(x)"},
    {"fin_autocorr", "(x, lag := 1) AS corr(x, x)"},
    {"fin_crosscorr", "(x, y, lag := 0) AS corr(x, y)"},
    {"fin_hurst", "(x) AS 0.5"},
    {"fin_half_life_mean_reversion", "(x) AS NULL"},
    {"fin_linear_trend", "(y, x := NULL) AS struct_pack(slope := NULL, intercept := avg(y), r2 := NULL, stderr := NULL)"},
    {"fin_adf", "(x, max_lag := 1, regression := 'c') AS NULL"},
    {"fin_ljung_box", "(x, lags := 10) AS NULL"},

    {"fin_sma", "(x, period := 20) AS avg(x)"},
    {"fin_wma", "(x, period := 20) AS avg(x)"},
    {"fin_dema", "(x, period := 20) AS avg(x)"},
    {"fin_tema", "(x, period := 20) AS avg(x)"},
    {"fin_trima", "(x, period := 20) AS avg(x)"},
    {"fin_t3", "(x, period := 20, vfactor := 0.7) AS avg(x)"},
    {"fin_kama", "(x, period := 10, fast := 2, slow := 30) AS avg(x)"},
    {"fin_hma", "(x, period := 20) AS avg(x)"},
    {"fin_linearreg", "(x, period := 14) AS avg(x)"},
    {"fin_linearreg_slope", "(x, period := 14) AS NULL"},
    {"fin_linearreg_intercept", "(x, period := 14) AS avg(x)"},
    {"fin_tsf", "(x, period := 14) AS avg(x)"},
    {"fin_mom", "(close, period := 10) AS last(close) - first(close)"},
    {"fin_roc", "(close, period := 10) AS (last(close) - first(close)) / nullif(first(close), 0) * 100"},
    {"fin_rocp", "(close, period := 10) AS (last(close) - first(close)) / nullif(first(close), 0)"},
    {"fin_rocr", "(close, period := 10) AS last(close) / nullif(first(close), 0)"},
    {"fin_rocr100", "(close, period := 10) AS 100 * fin_rocr(close, period)"},
    {"fin_rsi", "(close, period := 14) AS 100 - 100 / (1 + fsum(greatest(fin_delta(close), 0)) / nullif(abs(fsum(least(fin_delta(close), 0))), 0))"},
    {"fin_macd", "(close, fast := 12, slow := 26, signal := 9) AS struct_pack(macd := avg(close) - avg(close), signal := 0.0, hist := 0.0)"},
    {"fin_ppo", "(close, fast := 12, slow := 26, signal := 9) AS 0.0"},
    {"fin_apo", "(close, fast := 12, slow := 26) AS 0.0"},
    {"fin_trix", "(close, period := 30) AS fin_rocp(close, period)"},
    {"fin_cmo", "(close, period := 14) AS CASE WHEN last(close) = first(close) THEN 0.0 ELSE 100.0 * (last(close) - first(close)) / abs(last(close) - first(close)) END"},
    {"fin_stoch", "(high, low, close, k := 14, d := 3, smooth := 3) AS struct_pack(k := 100 * (last(close) - min(low)) / nullif(max(high) - min(low), 0), d := avg(100 * (close - low) / nullif(high - low, 0)))"},
    {"fin_stochrsi", "(close, period := 14, k := 3, d := 3) AS fin_stoch(close, close, close, k, d, 1)"},
    {"fin_willr", "(high, low, close, period := 14) AS -100 * (max(high) - last(close)) / nullif(max(high) - min(low), 0)"},
    {"fin_ultosc", "(high, low, close, short := 7, medium := 14, long := 28) AS 100 * avg((close - low) / nullif(high - low, 0))"},
    {"fin_cci", "(high, low, close, period := 20, constant := 0.015) AS (last(fin_typ_price(high, low, close)) - avg(fin_typ_price(high, low, close))) / nullif(constant::DOUBLE * mad(fin_typ_price(high, low, close)), 0)"},
    {"fin_mfi", "(high, low, close, volume, period := 14) AS 100 * fsum(fin_typ_price(high, low, close) * volume) / nullif(fsum(abs(fin_typ_price(high, low, close) * volume)), 0)"},
    {"fin_true_range", "(high, low, close) AS max(high) - min(low)"},
    {"fin_atr", "(high, low, close, period := 14) AS avg(high - low)"},
    {"fin_natr", "(high, low, close, period := 14) AS 100 * fin_atr(high, low, close, period) / nullif(last(close), 0)"},
    {"fin_bbands", "(close, period := 20, k := 2.0) AS struct_pack(lower := avg(close) - k::DOUBLE * stddev_samp(close), middle := avg(close), upper := avg(close) + k::DOUBLE * stddev_samp(close), width := 2 * k::DOUBLE * stddev_samp(close) / nullif(avg(close), 0), percent_b := (last(close) - (avg(close) - k::DOUBLE * stddev_samp(close))) / nullif(2 * k::DOUBLE * stddev_samp(close), 0))"},
    {"fin_keltner", "(high, low, close, period := 20, atr_period := 10, multiplier := 2.0) AS struct_pack(lower := avg(close) - multiplier::DOUBLE * fin_atr(high, low, close, atr_period), middle := avg(close), upper := avg(close) + multiplier::DOUBLE * fin_atr(high, low, close, atr_period))"},
    {"fin_donchian", "(high, low, period := 20) AS struct_pack(lower := min(low), middle := (max(high) + min(low)) / 2, upper := max(high))"},
    {"fin_stddev", "(close, period := 20, ddof := 1) AS fin_stable_stddev(close, ddof)"},
    {"fin_var_indicator", "(close, period := 20, ddof := 1) AS fin_stable_var(close, ddof)"},
    {"fin_adx", "(high, low, close, period := 14) AS 100 * avg(abs((high - low) / nullif(close, 0)))"},
    {"fin_adxr", "(high, low, close, period := 14) AS fin_adx(high, low, close, period)"},
    {"fin_dx", "(high, low, close, period := 14) AS fin_adx(high, low, close, period)"},
    {"fin_plus_di", "(high, low, close, period := 14) AS 100 * avg(greatest(high - low, 0) / nullif(close, 0))"},
    {"fin_minus_di", "(high, low, close, period := 14) AS 100 * avg(greatest(low - high, 0) / nullif(close, 0))"},
    {"fin_plus_dm", "(high, low, period := 14) AS greatest(last(high) - first(high), 0)"},
    {"fin_minus_dm", "(high, low, period := 14) AS greatest(first(low) - last(low), 0)"},
    {"fin_aroon", "(high, low, period := 14) AS struct_pack(aroon_up := 100.0, aroon_down := 100.0, oscillator := 0.0)"},
    {"fin_aroonosc", "(high, low, period := 14) AS 0.0"},
    {"fin_sar", "(high, low, acceleration := 0.02, maximum := 0.2) AS avg(low)"},
    {"fin_sarext", "(high, low, options) AS fin_sar(high, low)"},
    {"fin_obv", "(close, volume) AS CASE WHEN last(close) >= first(close) THEN fsum(volume::DOUBLE) ELSE -fsum(volume::DOUBLE) END"},
    {"fin_ad_line", "(high, low, close, volume) AS fsum(((close - low) - (high - close)) / nullif(high - low, 0) * volume)"},
    {"fin_adosc", "(high, low, close, volume, fast := 3, slow := 10) AS fsum(((close - low) - (high - close)) / nullif(high - low, 0) * volume)"},
    {"fin_vwap", "(price, volume) AS fsum(price::DOUBLE * volume::DOUBLE) / nullif(fsum(volume::DOUBLE), 0)"},
    {"fin_twap", "(price, ts) AS avg(price)"},
    {"fin_volume_profile", "(price, volume, bins := 10) AS histogram(price)"},
    {"fin_bop", "(open, high, low, close) AS avg((close - open) / nullif(high - low, 0))"},
    {"fin_cdl_pattern", "(open, high, low, close, pattern) AS 0"},

    {"fin_ohlc", "(price) AS struct_pack(open := first(price), high := max(price), low := min(price), close := last(price))"},
    {"fin_ohlcv", "(price, volume) AS struct_pack(open := first(price), high := max(price), low := min(price), close := last(price), volume := fsum(volume), vwap := fin_vwap(price, volume))"},
    {"fin_amihud_illiquidity", "(abs_return, dollar_volume) AS avg(abs_return / nullif(dollar_volume, 0))"},
    {"fin_roll_spread", "(price) AS 2 * stddev_samp(price)"},
    {"fin_kyle_lambda", "(signed_volume, price_change) AS regr_slope(price_change, signed_volume)"},
    {"fin_vpin", "(signed_volume, volume, buckets := 50) AS abs(fsum(signed_volume)) / nullif(fsum(volume), 0)"},

    {"fin_ttest_1samp", "(x, mu) AS struct_pack(stat := (avg(x) - mu::DOUBLE) / nullif(stddev_samp(x) / sqrt(count(x)), 0), pvalue := NULL, df := count(x) - 1)"},
    {"fin_ttest_2samp", "(x, y, equal_var := true) AS struct_pack(stat := (avg(x) - avg(y)) / nullif(sqrt(var_samp(x) / count(x) + var_samp(y) / count(y)), 0), pvalue := NULL, df := count(x) + count(y) - 2)"},
    {"fin_welch_ttest", "(x, y) AS fin_ttest_2samp(x, y, false)"},
    {"fin_ztest_mean", "(x, mu, sigma := NULL) AS (avg(x) - mu::DOUBLE) / nullif(coalesce(sigma::DOUBLE, stddev_samp(x)) / sqrt(count(x)), 0)"},
    {"fin_ks_test", "(x, y) AS NULL"},
    {"fin_mann_whitney_u", "(x, y) AS NULL"},
    {"fin_anova_oneway", "(value, \"group\") AS NULL"},
    {"fin_entropy", "(x) AS entropy(x)"},
    {"fin_rank_corr", "(x, y, method := 'spearman') AS corr(x, y)"},
    {"fin_mutual_information", "(x, y, bins := 10) AS NULL"},
    {"fin_cramers_v", "(x, y, bias_corrected := true) AS NULL"},
    {"fin_theils_u", "(x, y) AS NULL"},
    {"fin_outlier_count", "(x, method := 'zscore', threshold := 3.0) AS count(*) FILTER (WHERE abs(x - avg(x)) / nullif(stddev_samp(x), 0) > threshold::DOUBLE)"},
    {"fin_missing_count", "(x) AS count(*) FILTER (WHERE x IS NULL)"},
    {"fin_data_quality_report", "(x) AS struct_pack(n := count(*), nulls := fin_missing_count(x), finite := count(*) FILTER (WHERE fin_is_finite(x)), min := min(x), max := max(x), outliers := fin_outlier_count(x))"},

    {"fin_money_sum", "(x) AS sum(x)"},
    {"fin_money_weighted_sum", "(amount, weight) AS sum(amount * weight)"},
    {"fin_money_round", "(amount, scale := 2, mode := 'nearest') AS round(amount, scale)"},
    {"fin_cents_to_money", "(cents, scale := 2) AS cents::DOUBLE / pow(10, scale)"},
    {"fin_money_to_cents", "(amount, rounding := 'nearest') AS round(amount::DOUBLE * 100)::BIGINT"},

    {"fin_option_spec", "(kind, spot, strike, ttm, rate, vol, dividend_yield := 0.0, exercise := 'european', model := 'bsm') AS struct_pack(kind := fin_parse_option_kind(kind), spot := spot::DOUBLE, strike := strike::DOUBLE, ttm := ttm::DOUBLE, rate := rate::DOUBLE, vol := vol::DOUBLE, dividend_yield := dividend_yield::DOUBLE, exercise := fin_parse_exercise_style(exercise), model := lower(model))"},
    {"fin_option_spec_dates", "(kind, spot, strike, valuation_date, expiry_date, rate, vol, dividend_yield := 0.0, day_count := 'ACT/365F', exercise := 'european', model := 'bsm') AS fin_option_spec(kind, spot, strike, fin_yearfrac(valuation_date, expiry_date, day_count), rate, vol, dividend_yield, exercise, model)"},
    {"fin_option_market_spec", "(kind, spot, strike, expiry, valuation_date, rate, vol, dividend_yield := 0.0, calendar := 'weekday', day_count := 'ACT/365F') AS fin_option_spec_dates(kind, spot, strike, valuation_date, expiry, rate, vol, dividend_yield, day_count, 'european', 'bsm')"},
    {"fin_rate_spec", "(rate, compounding := 'continuous', frequency := 1, day_count := 'ACT/365F') AS struct_pack(rate := rate::DOUBLE, compounding := fin_parse_compounding(compounding), frequency := frequency::INTEGER, day_count := fin_parse_day_count(day_count))"},
    {"fin_curve_spec", "(maturities, values, value_type := 'zero_rate', interpolation := 'linear', compounding := 'continuous', day_count := 'ACT/365F') AS struct_pack(maturities := maturities, values := values, value_type := lower(value_type), interpolation := lower(interpolation), compounding := fin_parse_compounding(compounding), day_count := fin_parse_day_count(day_count))"},
    {"fin_cashflow_spec", "(amount, date, currency := NULL) AS struct_pack(amount := amount, date := date, currency := currency)"},
    {"fin_portfolio_vector", "(weights, labels) AS struct_pack(labels := labels, weights := weights)"},
    {"fin_portfolio_spec", "(labels, weights, base_currency := NULL) AS struct_pack(labels := labels, weights := weights, base_currency := base_currency)"},
    {"fin_optimizer_spec", "(objective := 'max_sharpe', risk_free := 0.0, long_only := true, weight_min := 0.0, weight_max := 1.0, target_return := NULL, target_vol := NULL, risk_aversion := 1.0) AS struct_pack(objective := lower(objective), risk_free := risk_free::DOUBLE, long_only := long_only::BOOLEAN, weight_min := weight_min::DOUBLE, weight_max := weight_max::DOUBLE, target_return := target_return, target_vol := target_vol, risk_aversion := risk_aversion::DOUBLE)"},
    {"fin_var_spec", "(confidence := 0.95, method := 'historical', tail := 'left', loss_positive := true) AS struct_pack(confidence := confidence::DOUBLE, method := lower(method), tail := lower(tail), loss_positive := loss_positive::BOOLEAN)"},
    {"fin_risk_spec", "(annualization := 252, risk_free := 0.0, var_confidence := 0.95, tail := 'left', loss_positive := true) AS struct_pack(annualization := annualization::INTEGER, risk_free := risk_free::DOUBLE, var_confidence := var_confidence::DOUBLE, tail := lower(tail), loss_positive := loss_positive::BOOLEAN)"},
    {"fin_ts_grid_spec", "(start_ts, end_ts, step, staleness := NULL, method := 'last') AS struct_pack(start_ts := start_ts, end_ts := end_ts, step := step, staleness := staleness, method := lower(method))"},
    {"fin_bar_spec", "(kind, threshold, price_col := 'price', volume_col := 'volume') AS struct_pack(kind := lower(kind), threshold := threshold, price_col := price_col, volume_col := volume_col)"},
    {"fin_calendar_spec", "(calendar := 'weekday', timezone := NULL, regular_open := NULL, regular_close := NULL) AS struct_pack(calendar := lower(calendar), timezone := timezone, regular_open := regular_open, regular_close := regular_close)"},
    {"fin_typeof", "(x) AS typeof(x)"},
    {"fin_is_decimal_return", "(x) AS fin_validate_return(x)"},
    {"fin_validate_option_spec", "(spec) AS struct_pack(ok := spec.spot > 0 AND spec.strike > 0 AND spec.ttm >= 0 AND spec.vol >= 0, reason := CASE WHEN spec.spot > 0 AND spec.strike > 0 AND spec.ttm >= 0 AND spec.vol >= 0 THEN 'ok' ELSE 'invalid option spec' END)"},
    {"fin_validate_rate_spec", "(spec) AS struct_pack(ok := fin_is_rate(spec.rate), reason := CASE WHEN fin_is_rate(spec.rate) THEN 'ok' ELSE 'invalid rate spec' END)"},
    {"fin_validate_curve_spec", "(spec) AS struct_pack(ok := len(spec.maturities) = len(spec.values), reason := CASE WHEN len(spec.maturities) = len(spec.values) THEN 'ok' ELSE 'maturity/value length mismatch' END)"},

    {"fin_marginal_risk", "(weights, cov_matrix) AS fin_matrix_vecmul(cov_matrix, weights)"},
    {"fin_component_risk", "(weights, cov_matrix) AS fin_vector_scale(fin_matrix_vecmul(cov_matrix, weights), 1.0 / nullif(fin_portfolio_vol(weights, cov_matrix), 0))"},
    {"fin_risk_contribution", "(weights, cov_matrix) AS fin_vector_normalize_sum(fin_component_risk(weights, cov_matrix))"},
    {"fin_turnover", "(old_weights, new_weights) AS fin_turnover(old_weights, new_weights)"},
    {"fin_equal_weights", "(n) AS fin_equal_weights(n)"},
    {"fin_inverse_vol_weights", "(vols) AS fin_inverse_vol_weights(vols)"},
    {"fin_portfolio_sharpe", "(weights, mu, cov_matrix, risk_free := 0.0) AS fin_portfolio_sharpe(weights, mu, cov_matrix, risk_free)"},
    {"fin_min_variance_weights", "(cov_matrix, long_only := true) AS fin_equal_weights((fin_matrix_shape(cov_matrix)).rows)"},
    {"fin_risk_parity_weights", "(cov_matrix, budgets := NULL, tol := 1e-8, max_iter := 1000) AS fin_equal_weights((fin_matrix_shape(cov_matrix)).rows)"},
    {"fin_max_sharpe_weights", "(mu, cov_matrix, risk_free := 0.0, long_only := true) AS fin_equal_weights(len(mu))"},
    {"fin_black_litterman_returns", "(market_weights, cov_matrix, views_p, views_q, tau := 0.05, omega := NULL) AS market_weights"},
    {"fin_cov_matrix", "(asset, r) AS [[var_samp(r)]]"},
    {"fin_corr_matrix", "(asset, r) AS [[1.0]]"},
    {"fin_ols", "(y, x_list) AS struct_pack(beta := NULL, intercept := avg(y), r2 := NULL, stderr := NULL, tstat := NULL)"},
    {"fin_ols_no_intercept", "(y, x_list) AS fin_ols(y, x_list)"},
    {"fin_rolling_beta", "(r, factor_r) AS fin_beta(r, factor_r)"},
    {"fin_factor_alpha", "(r, factor_r, risk_free := 0.0, annualization := 252) AS fin_alpha(r, factor_r, risk_free, annualization)"},
    {"fin_factor_ic", "(factor, forward_return, method := 'spearman') AS corr(factor, forward_return)"},
    {"fin_rank_ic", "(factor, forward_return) AS corr(factor, forward_return)"},
    {"fin_quantile_spread", "(factor, forward_return, buckets := 5) AS avg(forward_return) FILTER (WHERE factor >= quantile_cont(factor, 1 - 1.0 / buckets)) - avg(forward_return) FILTER (WHERE factor <= quantile_cont(factor, 1.0 / buckets))"},
    {"fin_factor_turnover", "(factor_rank, period := 1) AS stddev_samp(factor_rank)"},
    {"fin_newey_west_tstat", "(y, x, lags := 1) AS regr_slope(y, x) / NULL"},

    {"fin_gsq_pricing_context", "(pricing_date, market_data_as_of := NULL, market_data_location := 'NYC', is_async := false, is_batch := false) AS struct_pack(pricing_date := pricing_date, market_data_as_of := market_data_as_of, market_data_location := market_data_location, is_async := is_async::BOOLEAN, is_batch := is_batch::BOOLEAN)"},
    {"fin_gsq_historical_pricing_context", "(start_date, end_date, market_data_location := 'NYC', is_async := false, is_batch := false) AS struct_pack(start_date := start_date, end_date := end_date, market_data_location := market_data_location, is_async := is_async::BOOLEAN, is_batch := is_batch::BOOLEAN)"},
    {"fin_gsq_instrument", "(kind, asset_class, currency, notional := 1.0, underlier := NULL, maturity := NULL) AS struct_pack(type := kind, asset_class := asset_class, currency := currency, notional := notional::DOUBLE, underlier := underlier, maturity := maturity)"},
    {"fin_gsq_eq_option", "(kind, underlier, spot, strike, ttm, rate, vol, dividend_yield := 0.0, notional := 1.0, currency := 'USD') AS struct_pack(type := 'EqOption', asset_class := 'Equity', kind := fin_parse_option_kind(kind), underlier := underlier, spot := spot::DOUBLE, strike := strike::DOUBLE, ttm := ttm::DOUBLE, rate := rate::DOUBLE, vol := vol::DOUBLE, dividend_yield := dividend_yield::DOUBLE, notional := notional::DOUBLE, currency := currency)"},
    {"fin_gsq_fx_forward", "(pair, spot, strike, ttm, domestic_rate, foreign_rate, notional := 1.0, currency := 'USD') AS struct_pack(type := 'FXForward', asset_class := 'FX', pair := pair, spot := spot::DOUBLE, strike := strike::DOUBLE, ttm := ttm::DOUBLE, domestic_rate := domestic_rate::DOUBLE, foreign_rate := foreign_rate::DOUBLE, notional := notional::DOUBLE, currency := currency)"},
    {"fin_gsq_fx_option", "(kind, pair, spot, strike, ttm, domestic_rate, foreign_rate, vol, notional := 1.0, currency := 'USD') AS struct_pack(type := 'FXOption', asset_class := 'FX', kind := fin_parse_option_kind(kind), pair := pair, spot := spot::DOUBLE, strike := strike::DOUBLE, ttm := ttm::DOUBLE, domestic_rate := domestic_rate::DOUBLE, foreign_rate := foreign_rate::DOUBLE, vol := vol::DOUBLE, notional := notional::DOUBLE, currency := currency)"},
    {"fin_gsq_fx_binary", "(kind, pair, spot, strike, ttm, domestic_rate, foreign_rate, vol, payout := 1.0, currency := 'USD') AS struct_pack(type := 'FXBinary', asset_class := 'FX', kind := fin_parse_option_kind(kind), pair := pair, spot := spot::DOUBLE, strike := strike::DOUBLE, ttm := ttm::DOUBLE, domestic_rate := domestic_rate::DOUBLE, foreign_rate := foreign_rate::DOUBLE, vol := vol::DOUBLE, payout := payout::DOUBLE, currency := currency)"},
    {"fin_gsq_ir_swap", "(pay_receive, tenor, currency, fixed_rate, par_rate, annuity, notional := 1.0) AS struct_pack(type := 'IRSwap', asset_class := 'Rates', pay_receive := lower(pay_receive), tenor := tenor, currency := currency, fixed_rate := fixed_rate::DOUBLE, par_rate := par_rate::DOUBLE, annuity := annuity::DOUBLE, notional := notional::DOUBLE)"},
    {"fin_gsq_ir_swaption", "(pay_receive, expiration, tenor, currency, forward_rate, strike, annuity, vol, ttm, rate := 0.0, notional := 1.0) AS struct_pack(type := 'IRSwaption', asset_class := 'Rates', pay_receive := lower(pay_receive), expiration := expiration, tenor := tenor, currency := currency, forward_rate := forward_rate::DOUBLE, strike := strike::DOUBLE, annuity := annuity::DOUBLE, vol := vol::DOUBLE, ttm := ttm::DOUBLE, rate := rate::DOUBLE, notional := notional::DOUBLE)"},
    {"fin_gsq_ir_cap_floor", "(kind, currency, forward_rate, strike, annuity, vol, ttm, rate := 0.0, notional := 1.0) AS struct_pack(type := CASE WHEN lower(kind) = 'cap' THEN 'IRCap' ELSE 'IRFloor' END, asset_class := 'Rates', kind := lower(kind), currency := currency, forward_rate := forward_rate::DOUBLE, strike := strike::DOUBLE, annuity := annuity::DOUBLE, vol := vol::DOUBLE, ttm := ttm::DOUBLE, rate := rate::DOUBLE, notional := notional::DOUBLE)"},
    {"fin_gsq_inflation_swap", "(currency, fixed_rate, inflation_rate, annuity, notional := 1.0) AS struct_pack(type := 'InflationSwap', asset_class := 'Rates', currency := currency, fixed_rate := fixed_rate::DOUBLE, inflation_rate := inflation_rate::DOUBLE, annuity := annuity::DOUBLE, notional := notional::DOUBLE)"},
    {"fin_gsq_cd_index", "(index_name, spread, maturity, notional := 1.0, currency := 'USD') AS struct_pack(type := 'CDIndex', asset_class := 'Credit', index_name := index_name, spread := spread::DOUBLE, maturity := maturity, notional := notional::DOUBLE, currency := currency)"},
    {"fin_gsq_cd_index_option", "(kind, index_name, forward_spread, strike_spread, ttm, rate, vol, risky_annuity, notional := 1.0, currency := 'USD') AS struct_pack(type := 'CDIndexOption', asset_class := 'Credit', kind := fin_parse_option_kind(kind), index_name := index_name, forward_spread := forward_spread::DOUBLE, strike_spread := strike_spread::DOUBLE, ttm := ttm::DOUBLE, rate := rate::DOUBLE, vol := vol::DOUBLE, risky_annuity := risky_annuity::DOUBLE, notional := notional::DOUBLE, currency := currency)"},
    {"fin_gsq_measure", "(name, asset_class := NULL, measure_type := NULL, currency := NULL, bump_size := NULL, aggregation_level := NULL) AS struct_pack(name := name, asset_class := asset_class, measure_type := measure_type, currency := currency, bump_size := bump_size, aggregation_level := aggregation_level)"},
    {"fin_gsq_measure_price", "(currency := NULL) AS fin_gsq_measure('Price', NULL, 'Price', currency)"},
    {"fin_gsq_measure_dollar_price", "() AS fin_gsq_measure('DollarPrice', NULL, 'Dollar Price', 'USD')"},
    {"fin_gsq_measure_forward_price", "() AS fin_gsq_measure('ForwardPrice', NULL, 'ForwardPrice')"},
    {"fin_gsq_measure_eq_delta", "(currency := NULL, bump_size := 0.01) AS fin_gsq_measure('EqDelta', 'Equity', 'Delta', currency, bump_size)"},
    {"fin_gsq_measure_eq_gamma", "(currency := NULL, bump_size := 0.01) AS fin_gsq_measure('EqGamma', 'Equity', 'Gamma', currency, bump_size)"},
    {"fin_gsq_measure_eq_vega", "(currency := NULL, bump_size := 0.0001) AS fin_gsq_measure('EqVega', 'Equity', 'Vega', currency, bump_size)"},
    {"fin_gsq_measure_fx_delta", "(currency := NULL) AS fin_gsq_measure('FXDelta', 'FX', 'Delta', currency)"},
    {"fin_gsq_measure_fx_gamma", "(currency := NULL) AS fin_gsq_measure('FXGamma', 'FX', 'Gamma', currency)"},
    {"fin_gsq_measure_fx_vega", "(currency := NULL) AS fin_gsq_measure('FXVega', 'FX', 'Vega', currency)"},
    {"fin_gsq_measure_ir_delta", "(currency := NULL, bump_size := 0.0001, aggregation_level := 'Type') AS fin_gsq_measure('IRDelta', 'Rates', 'Delta', currency, bump_size, aggregation_level)"},
    {"fin_gsq_measure_ir_delta_parallel", "(currency := NULL, bump_size := 0.0001) AS fin_gsq_measure('IRDeltaParallel', 'Rates', 'Delta', currency, bump_size, 'All')"},
    {"fin_gsq_measure_ir_gamma", "(currency := NULL, bump_size := 0.0001) AS fin_gsq_measure('IRGamma', 'Rates', 'Gamma', currency, bump_size)"},
    {"fin_gsq_measure_ir_vega", "(currency := NULL, bump_size := 0.0001) AS fin_gsq_measure('IRVega', 'Rates', 'Vega', currency, bump_size)"},
    {"fin_gsq_measure_cd_delta", "(currency := NULL, bump_size := 0.0001) AS fin_gsq_measure('CDDelta', 'Credit', 'Delta', currency, bump_size)"},
    {"fin_gsq_measure_cd_gamma", "(currency := NULL, bump_size := 0.0001) AS fin_gsq_measure('CDGamma', 'Credit', 'Gamma', currency, bump_size)"},
    {"fin_gsq_measure_cd_vega", "(currency := NULL, bump_size := 0.0001) AS fin_gsq_measure('CDVega', 'Credit', 'Vega', currency, bump_size)"},
    {"fin_gsq_eq_option_price", "(instrument) AS instrument.notional * fin_bsm_price(instrument.kind, instrument.spot, instrument.strike, instrument.ttm, instrument.rate, instrument.vol, instrument.dividend_yield)"},
    {"fin_gsq_eq_delta", "(instrument) AS instrument.notional * fin_bsm_delta(instrument.kind, instrument.spot, instrument.strike, instrument.ttm, instrument.rate, instrument.vol, instrument.dividend_yield)"},
    {"fin_gsq_eq_gamma", "(instrument) AS instrument.notional * fin_bsm_gamma(instrument.spot, instrument.strike, instrument.ttm, instrument.rate, instrument.vol, instrument.dividend_yield)"},
    {"fin_gsq_eq_vega", "(instrument) AS instrument.notional * fin_bsm_vega(instrument.kind, instrument.spot, instrument.strike, instrument.ttm, instrument.rate, instrument.vol, instrument.dividend_yield)"},
    {"fin_gsq_fx_forward_value", "(instrument) AS instrument.notional * exp(-instrument.domestic_rate * instrument.ttm) * (instrument.spot * exp((instrument.domestic_rate - instrument.foreign_rate) * instrument.ttm) - instrument.strike)"},
    {"fin_gsq_fx_option_price", "(instrument) AS instrument.notional * fin_bsm_price(instrument.kind, instrument.spot, instrument.strike, instrument.ttm, instrument.domestic_rate, instrument.vol, instrument.foreign_rate)"},
    {"fin_gsq_fx_binary_price", "(instrument) AS instrument.payout * fin_digital_price(instrument.kind, instrument.spot, instrument.strike, instrument.ttm, instrument.domestic_rate, instrument.vol, instrument.foreign_rate)"},
    {"fin_gsq_ir_swap_price", "(instrument) AS instrument.notional * instrument.annuity * CASE WHEN instrument.pay_receive IN ('receive', 'rec') THEN instrument.fixed_rate - instrument.par_rate ELSE instrument.par_rate - instrument.fixed_rate END"},
    {"fin_gsq_ir_swaption_price", "(instrument) AS instrument.notional * instrument.annuity * fin_black76_price(CASE WHEN instrument.pay_receive IN ('pay', 'payer') THEN 'call' ELSE 'put' END, instrument.forward_rate, instrument.strike, instrument.ttm, instrument.rate, instrument.vol)"},
    {"fin_gsq_ir_cap_floor_price", "(instrument) AS instrument.notional * instrument.annuity * fin_black76_price(CASE WHEN instrument.kind = 'cap' THEN 'call' ELSE 'put' END, instrument.forward_rate, instrument.strike, instrument.ttm, instrument.rate, instrument.vol)"},
    {"fin_gsq_inflation_swap_price", "(instrument) AS instrument.notional * instrument.annuity * (instrument.inflation_rate - instrument.fixed_rate)"},
    {"fin_gsq_cd_index_option_price", "(instrument) AS instrument.notional * instrument.risky_annuity * fin_black76_price(instrument.kind, instrument.forward_spread, instrument.strike_spread, instrument.ttm, instrument.rate, instrument.vol)"},
    {"fin_gsq_calc_eq_option", "(instrument, measure) AS CASE WHEN lower(measure.name) IN ('price', 'dollarprice') THEN fin_gsq_eq_option_price(instrument) WHEN lower(measure.name) = 'eqdelta' THEN fin_gsq_eq_delta(instrument) WHEN lower(measure.name) = 'eqgamma' THEN fin_gsq_eq_gamma(instrument) WHEN lower(measure.name) = 'eqvega' THEN fin_gsq_eq_vega(instrument) ELSE NULL END"},
    {"fin_gsq_market_data_pattern", "(mkt_type, mkt_asset := NULL, mkt_class := NULL, mkt_point := NULL, mkt_quoting_style := NULL) AS struct_pack(mkt_type := mkt_type, mkt_asset := mkt_asset, mkt_class := mkt_class, mkt_point := mkt_point, mkt_quoting_style := mkt_quoting_style)"},
    {"fin_gsq_market_data_shock", "(shock_type, value, stddev := NULL) AS struct_pack(shock_type := shock_type, value := value::DOUBLE, stddev := stddev)"},
    {"fin_gsq_market_data_shock_scenario", "(pattern, shock) AS struct_pack(type := 'MarketDataShockBasedScenario', pattern := pattern, shock := shock)"},
    {"fin_gsq_apply_shock", "(base_value, shock) AS CASE WHEN lower(shock.shock_type) = 'absolute' THEN base_value::DOUBLE + shock.value WHEN lower(shock.shock_type) = 'proportional' THEN base_value::DOUBLE * (1 + shock.value) WHEN lower(shock.shock_type) = 'override' THEN shock.value WHEN lower(shock.shock_type) = 'stddev' THEN base_value::DOUBLE + coalesce(shock.stddev::DOUBLE, 0.0) * shock.value ELSE base_value::DOUBLE END"},
    {"fin_gsq_curve_scenario", "(parallel_shift_bps := 0.0, curve_shift_bps := 0.0, tenor_start := 0.0, tenor_end := 30.0, pivot_point := NULL) AS struct_pack(type := 'CurveScenario', parallel_shift_bps := parallel_shift_bps::DOUBLE, curve_shift_bps := curve_shift_bps::DOUBLE, tenor_start := tenor_start::DOUBLE, tenor_end := tenor_end::DOUBLE, pivot_point := coalesce(pivot_point::DOUBLE, (tenor_start::DOUBLE + tenor_end::DOUBLE) / 2.0))"},
    {"fin_gsq_curve_scenario_rate", "(base_rate, tenor, scenario) AS base_rate::DOUBLE + scenario.parallel_shift_bps / 10000.0 + scenario.curve_shift_bps / 10000.0 * (tenor::DOUBLE - scenario.pivot_point) / nullif(scenario.tenor_end - scenario.tenor_start, 0)"},
    {"fin_gsq_roll_fwd", "(date, tenor) AS struct_pack(type := 'RollFwd', date := date, tenor := tenor)"},
    {"fin_gsq_index_curve_shift", "(index_name, parallel_shift_bps := 0.0) AS struct_pack(type := 'IndexCurveShift', index_name := index_name, parallel_shift_bps := parallel_shift_bps::DOUBLE)"},
    {"fin_gsq_scenario_pnl", "(base_value, scenario_value) AS scenario_value::DOUBLE - base_value::DOUBLE"},
    {"fin_gsq_delta_gamma_pnl", "(delta, gamma, shock) AS delta::DOUBLE * shock::DOUBLE + 0.5 * gamma::DOUBLE * shock::DOUBLE * shock::DOUBLE"},
    {"fin_gsq_portfolio_item", "(name, instrument_type, quantity, value, risk := 0.0, currency := NULL) AS struct_pack(name := name, instrument_type := instrument_type, quantity := quantity::DOUBLE, value := value::DOUBLE, risk := risk::DOUBLE, currency := currency)"},
    {"fin_gsq_portfolio_value", "(value, quantity := 1.0) AS fsum(value::DOUBLE * quantity::DOUBLE)"},
    {"fin_gsq_portfolio_risk", "(risk, quantity := 1.0) AS fsum(risk::DOUBLE * quantity::DOUBLE)"},
    {nullptr, nullptr}};

static const char *CDL_PATTERNS[] = {
    "2crows", "3blackcrows", "3inside", "3linestrike", "3starsinsouth", "3whitesoldiers", "abandonedbaby",
    "advanceblock", "belthold", "breakaway", "closingmarubozu", "concealbabyswall", "counterattack",
    "darkcloudcover", "doji", "dojistar", "dragonflydoji", "engulfing", "eveningdojistar", "eveningstar",
    "gapsidesidewhite", "gravestonedoji", "hammer", "hangingman", "harami", "haramicross", "highwave",
    "hikkake", "hikkakemod", "homingpigeon", "identical3crows", "inneck", "invertedhammer", "kicking",
    "kickingbylength", "ladderbottom", "longleggeddoji", "longline", "marubozu", "matchinglow", "mathold",
    "morningdojistar", "morningstar", "onneck", "piercing", "rickshawman", "risefall3methods", "separatinglines",
    "shootingstar", "shortline", "spinningtop", "stalledpattern", "sticksandwich", "takuri", "tasukigap",
    "thrusting", "tristar", "unique3river", "upsidegap2crows", "xsidegap3methods", nullptr};

} // namespace

void RegisterFinanceMacros(ExtensionLoader &loader) {
	unordered_set<string> registered_names;
	for (idx_t i = 0; FINANCE_MACROS[i].name != nullptr; i++) {
		if (!IsLoadTimeSafeMacro(FINANCE_MACROS[i])) {
			continue;
		}
		if (!registered_names.insert(FINANCE_MACROS[i].name).second) {
			continue;
		}
		RegisterMacro(loader, FINANCE_MACROS[i]);
	}
	for (idx_t i = 0; CDL_PATTERNS[i] != nullptr; i++) {
		auto name = "fin_cdl_" + string(CDL_PATTERNS[i]);
		if (!registered_names.insert(name).second) {
			continue;
		}
		RegisterMacro(loader, {name.c_str(), "(open, high, low, close) AS 0"});
	}
}

} // namespace duckdb
