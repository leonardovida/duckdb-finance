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
#include "macros/returns_risk.inc"
#include "macros/time_series.inc"
#include "macros/technical.inc"
#include "macros/statistics_specs_portfolio.inc"
#include "macros/compatibility.inc"
#include "macros/gsq.inc"
    {nullptr, nullptr}};

static const char *CDL_PATTERNS[] = {
#include "macros/candlestick_patterns.inc"

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
