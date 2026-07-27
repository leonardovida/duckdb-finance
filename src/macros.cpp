#include "finance/finance_extension.hpp"

#include "duckdb/common/exception.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/function/scalar_macro_function.hpp"
#include "duckdb/parser/parser.hpp"
#include "duckdb/parser/expression/columnref_expression.hpp"
#include "duckdb/parser/parsed_data/create_macro_info.hpp"
#include "duckdb/common/unordered_set.hpp"

#include <cstdio>
#include <cstdlib>
#include <cctype>

namespace duckdb {
namespace {

struct FinanceMacro {
	const char *name;
	const char *definition;
};

static string TrimCopy(const string &value) {
	idx_t start = 0;
	while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start]))) {
		start++;
	}
	idx_t end = value.size();
	while (end > start && std::isspace(static_cast<unsigned char>(value[end - 1]))) {
		end--;
	}
	return value.substr(start, end - start);
}

static string UnquoteIdentifier(const string &value) {
	auto trimmed = TrimCopy(value);
	if (trimmed.size() >= 2 && trimmed.front() == '"' && trimmed.back() == '"') {
		return StringUtil::Replace(trimmed.substr(1, trimmed.size() - 2), "\"\"", "\"");
	}
	return trimmed;
}

struct SqlQuoteState {
	char quote = '\0';

	bool Consume(const string &sql, idx_t &position) {
		auto current = sql[position];
		if (quote != '\0') {
			if (current == quote) {
				if (position + 1 < sql.size() && sql[position + 1] == quote) {
					position++;
				} else {
					quote = '\0';
				}
			}
			return true;
		}
		if (current == '\'' || current == '"') {
			quote = current;
			return true;
		}
		return false;
	}
};

static idx_t FindParameterListEnd(const string &definition) {
	idx_t depth = 0;
	SqlQuoteState quote_state;
	for (idx_t i = 0; i < definition.size(); i++) {
		auto current = definition[i];
		if (quote_state.Consume(definition, i)) {
			continue;
		}
		if (current == '(') {
			depth++;
		} else if (current == ')') {
			if (depth == 0) {
				throw InternalException("Finance macro has an unmatched closing parenthesis");
			}
			depth--;
			if (depth == 0) {
				return i;
			}
		}
	}
	throw InternalException("Finance macro is missing a closing parameter list");
}

static vector<string> SplitTopLevel(const string &input, char delimiter) {
	vector<string> result;
	idx_t depth = 0;
	SqlQuoteState quote_state;
	idx_t start = 0;
	for (idx_t i = 0; i < input.size(); i++) {
		auto current = input[i];
		if (quote_state.Consume(input, i)) {
			continue;
		}
		if (current == '(' || current == '[' || current == '{') {
			depth++;
		} else if (current == ')' || current == ']' || current == '}') {
			if (depth > 0) {
				depth--;
			}
		} else if (current == delimiter && depth == 0) {
			result.push_back(TrimCopy(input.substr(start, i - start)));
			start = i + 1;
		}
	}
	result.push_back(TrimCopy(input.substr(start)));
	return result;
}

static unique_ptr<CreateMacroInfo> BuildMacroInfo(const FinanceMacro &macro) {
	auto definition = string(macro.definition);
	if (definition.empty() || definition.front() != '(') {
		throw InternalException("Finance macro definition must start with a parameter list");
	}
	auto close = FindParameterListEnd(definition);
	auto remainder = TrimCopy(definition.substr(close + 1));
	if (remainder.size() < 2 || !StringUtil::CIEquals(remainder.substr(0, 2), "AS")) {
		throw InternalException("Finance macro definition must use ') AS <expression>'");
	}
	auto parameters = definition.substr(1, close - 1);
	auto expression_sql = TrimCopy(remainder.substr(2));
	auto expressions = Parser::ParseExpressionList(expression_sql);
	if (expressions.size() != 1) {
		throw InternalException("Expected a single expression for finance macro %s", macro.name);
	}

	auto function = make_uniq<ScalarMacroFunction>(std::move(expressions[0]));
	for (auto &parameter : SplitTopLevel(parameters, ',')) {
		if (parameter.empty()) {
			continue;
		}
		auto default_pos = parameter.find(":=");
		if (default_pos == string::npos) {
			function->parameters.push_back(make_uniq<ColumnRefExpression>(FinanceFunctionName(UnquoteIdentifier(parameter))));
			continue;
		}
		auto name = UnquoteIdentifier(parameter.substr(0, default_pos));
		auto default_sql = TrimCopy(parameter.substr(default_pos + 2));
		auto default_expression = Parser::ParseExpressionList(default_sql);
		if (default_expression.size() != 1) {
			throw InternalException("Expected a single default expression for finance macro %s", macro.name);
		}
		function->parameters.push_back(make_uniq<ColumnRefExpression>(FinanceFunctionName(name)));
		function->default_parameters.insert(FinanceFunctionName(name), std::move(default_expression[0]));
	}

	auto info = make_uniq<CreateMacroInfo>(CatalogType::MACRO_ENTRY);
	info->macros.push_back(std::move(function));
#if FINANCE_HAS_DUCKDB_IDENTIFIER
	info->SetSchema(FinanceFunctionName(DEFAULT_SCHEMA));
	info->SetFunctionName(FinanceFunctionName(macro.name));
#else
	info->schema = DEFAULT_SCHEMA;
	info->name = macro.name;
#endif
	info->temporary = true;
	info->internal = true;
	return info;
}

static void RegisterMacro(ExtensionLoader &loader, const FinanceMacro &macro) {
	if (std::getenv("FINANCE_EXTENSION_TRACE_MACROS")) {
		std::fprintf(stderr, "finance: registering macro %s\n", macro.name);
		std::fflush(stderr);
	}
	auto info = BuildMacroInfo(macro);
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
	       !Contains(macro.definition, "generate_series(") && !Contains(macro.definition, "lambda :=") &&
	       !Contains(macro.definition, "fin_delta(");
}

static const FinanceMacro FINANCE_MACROS[] = {
#include "macros/returns_risk.inc"
#include "macros/time_series.inc"
#include "macros/technical.inc"
#include "macros/statistics_specs_portfolio.inc"
    {nullptr, nullptr}};

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
}

} // namespace duckdb
