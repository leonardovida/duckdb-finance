#include "finance/finance_extension.hpp"

#include "duckdb/common/exception.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/common/types/value.hpp"
#include "duckdb/common/types/value_map.hpp"
#include "duckdb/function/function_set.hpp"
#include "duckdb/function/table_function.hpp"
#include "duckdb/parser/parser.hpp"
#include "duckdb/parser/qualified_name.hpp"
#include "duckdb/parser/statement/select_statement.hpp"
#include "duckdb/parser/tableref/subqueryref.hpp"

#include <algorithm>
#include <cmath>
#include <ctime>

namespace duckdb {
namespace {

static string SqlIdentifier(const string &name) {
	return "\"" + StringUtil::Replace(name, "\"", "\"\"") + "\"";
}

static string SqlTableName(const Value &value) {
	if (value.IsNull()) {
		throw BinderException("Table name cannot be NULL");
	}
	return QualifiedName::Parse(value.GetValue<string>()).ToString();
}

static string SqlColumn(const Value &value) {
	if (value.IsNull()) {
		throw BinderException("Column name cannot be NULL");
	}
	return SqlIdentifier(value.GetValue<string>());
}

static string SqlLiteral(const Value &value) {
	if (value.IsNull()) {
		return "NULL";
	}
	return value.ToSQLString();
}

static string CurrentDateLiteral() {
	auto now = std::time(nullptr);
	std::tm tm_value;
#if defined(_WIN32)
	localtime_s(&tm_value, &now);
#else
	localtime_r(&now, &tm_value);
#endif
	char buffer[sizeof("YYYY-MM-DD")];
	if (std::strftime(buffer, sizeof(buffer), "%Y-%m-%d", &tm_value) == 0) {
		throw InternalException("Failed to format current local date");
	}
	return "DATE '" + string(buffer) + "'";
}

static unique_ptr<TableRef> ParseSubquery(ClientContext &context, const string &query) {
	Parser parser(context.GetParserOptions());
	parser.ParseQuery(query);
	if (parser.statements.size() != 1 || parser.statements[0]->type != StatementType::SELECT_STATEMENT) {
		throw ParserException("Finance table function generated an invalid SELECT statement");
	}
	auto select_stmt = unique_ptr_cast<SQLStatement, SelectStatement>(std::move(parser.statements[0]));
	return make_uniq<SubqueryRef>(std::move(select_stmt));
}

static string BSMArguments(const string &kind, const string &spot, const string &strike, const string &ttm,
                           const string &rate, const string &vol, const string &dividend_yield) {
	return StringUtil::Format("%s, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE", kind, spot,
	                          strike, ttm, rate, vol, dividend_yield);
}

static unique_ptr<TableRef> OptionChainBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	if (input.inputs.size() != 7 && input.inputs.size() != 8) {
		throw BinderException("fin_option_chain expects table_name, kind_col, spot_col, strike_col, ttm_col, rate_col, "
		                      "vol_col[, dividend_yield_col]");
	}
	auto table = SqlTableName(input.inputs[0]);
	auto kind = SqlColumn(input.inputs[1]);
	auto spot = SqlColumn(input.inputs[2]);
	auto strike = SqlColumn(input.inputs[3]);
	auto ttm = SqlColumn(input.inputs[4]);
	auto rate = SqlColumn(input.inputs[5]);
	auto vol = SqlColumn(input.inputs[6]);
	auto q = input.inputs.size() == 8 ? SqlColumn(input.inputs[7]) : "0.0";
	auto args = BSMArguments(kind, spot, strike, ttm, rate, vol, q);
	auto query = StringUtil::Format(
	    "WITH priced AS (SELECT *, fin_bsm_all(%s) AS __finance_bsm_all FROM %s) "
	    "SELECT * EXCLUDE (__finance_bsm_all), "
	    "__finance_bsm_all.price AS price, "
	    "__finance_bsm_all.delta AS delta, "
	    "__finance_bsm_all.gamma AS gamma, "
	    "__finance_bsm_all.vega AS vega, "
	    "__finance_bsm_all.theta AS theta, "
	    "__finance_bsm_all.rho AS rho, "
	    "fin_bsm_implied_vol(%s, __finance_bsm_all.price, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, "
	    "%s::DOUBLE) AS implied_vol "
	    "FROM priced",
	    args, table, kind, spot, strike, ttm, rate, q, vol);
	return ParseSubquery(context, query);
}

static string GridSubquery(TableFunctionBindInput &input, const string &value_expr) {
	auto table = SqlTableName(input.inputs[0]);
	auto ts_col = SqlColumn(input.inputs[1]);
	auto value_col = SqlColumn(input.inputs[2]);
	auto start_ts = SqlLiteral(input.inputs[3]);
	auto end_ts = SqlLiteral(input.inputs[4]);
	auto step = SqlLiteral(input.inputs[5]);
	return StringUtil::Format(
	    "WITH grid AS ("
	    "  SELECT generate_series AS ts FROM generate_series(%s::TIMESTAMP, %s::TIMESTAMP, %s::INTERVAL)"
	    "), source AS ("
	    "  SELECT %s::TIMESTAMP AS ts, %s::DOUBLE AS value FROM %s"
	    "), sampled AS ("
	    "  SELECT g.ts, (SELECT s.value FROM source s WHERE s.ts <= g.ts ORDER BY s.ts DESC LIMIT 1) AS value FROM grid g"
	    ") SELECT ts, %s AS value FROM sampled ORDER BY ts",
	    start_ts, end_ts, step, ts_col, value_col, table, value_expr);
}

static unique_ptr<TableRef> ResampleGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	if (input.inputs.size() < 6) {
		throw BinderException("fin_resample_grid expects table_name, ts_col, value_col, start_ts, end_ts, step");
	}
	return ParseSubquery(context, GridSubquery(input, "value"));
}

static unique_ptr<TableRef> DeltaGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return ParseSubquery(context, GridSubquery(input, "value - lag(value) OVER (ORDER BY ts)"));
}

static unique_ptr<TableRef> RateGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return ParseSubquery(context, GridSubquery(input,
	                                          "(value - lag(value) OVER (ORDER BY ts)) / "
	                                          "nullif(epoch(ts - lag(ts) OVER (ORDER BY ts)), 0)"));
}

static unique_ptr<TableRef> ChangesGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return ParseSubquery(context, GridSubquery(input,
	                                          "CASE WHEN value IS DISTINCT FROM lag(value) OVER (ORDER BY ts) "
	                                          "THEN 1.0 ELSE 0.0 END"));
}

static unique_ptr<TableRef> ResetsGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return ParseSubquery(context,
	                     GridSubquery(input, "CASE WHEN value < lag(value) OVER (ORDER BY ts) THEN 1.0 ELSE 0.0 END"));
}

static unique_ptr<TableRef> BootstrapCurveBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	if (input.inputs.size() < 4) {
		throw BinderException("fin_bootstrap_curve expects table_name, instrument_col, maturity_col, rate_col");
	}
	auto table = SqlTableName(input.inputs[0]);
	auto instrument = SqlColumn(input.inputs[1]);
	auto maturity = SqlColumn(input.inputs[2]);
	auto rate = SqlColumn(input.inputs[3]);
	auto query = StringUtil::Format(
	    "SELECT %s AS instrument, %s::DOUBLE AS maturity, %s::DOUBLE AS zero_rate, "
	    "fin_discount_factor(%s::DOUBLE, %s::DOUBLE) AS discount_factor "
	    "FROM %s ORDER BY maturity",
	    instrument, maturity, rate, rate, maturity, table);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> PortfolioOptimizeTableBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	if (input.inputs.size() < 4) {
		throw BinderException("fin_portfolio_optimize_table expects table_name, asset_col, date_col, return_col");
	}
	auto table = SqlTableName(input.inputs[0]);
	auto asset = SqlColumn(input.inputs[1]);
	auto query = StringUtil::Format(
	    "WITH assets AS (SELECT DISTINCT %s AS asset FROM %s) "
	    "SELECT asset, row_number() OVER (ORDER BY asset) - 1 AS asset_idx, 1.0 / count(*) OVER () AS weight "
	    "FROM assets ORDER BY asset",
	    asset, table);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> FactorReportBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	if (input.inputs.size() < 5) {
		throw BinderException("fin_factor_report expects table_name, date_col, asset_col, factor_col, return_col");
	}
	auto table = SqlTableName(input.inputs[0]);
	auto factor = SqlColumn(input.inputs[3]);
	auto ret = SqlColumn(input.inputs[4]);
	auto buckets = input.inputs.size() >= 6 ? input.inputs[5].GetValue<int32_t>() : 5;
	if (buckets <= 1) {
		throw BinderException("fin_factor_report buckets must be greater than 1");
	}
	auto high_quantile = 1.0 - 1.0 / double(buckets);
	auto low_quantile = 1.0 / double(buckets);
	auto query = StringUtil::Format(
	    "WITH source AS ("
	    "  SELECT %s::DOUBLE AS factor, %s::DOUBLE AS ret FROM %s "
	    "  WHERE %s IS NOT NULL AND %s IS NOT NULL"
	    "), cuts AS ("
	    "  SELECT quantile_cont(factor, %f) AS high_cut, quantile_cont(factor, %f) AS low_cut FROM source"
	    ") "
	    "SELECT corr(factor, ret) AS ic, avg(ret) AS mean_return, "
	    "avg(ret) FILTER (WHERE factor >= high_cut) - "
	    "avg(ret) FILTER (WHERE factor <= low_cut) AS quantile_spread "
	    "FROM source, cuts",
	    factor, ret, table, factor, ret, high_quantile, low_quantile);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> GarchFitBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	if (input.inputs.size() < 2) {
		throw BinderException("fin_garch_fit expects table_name, return_col");
	}
	auto table = SqlTableName(input.inputs[0]);
	auto ret = SqlColumn(input.inputs[1]);
	auto query = StringUtil::Format(
	    "SELECT 1 AS p, 1 AS q, 0.000001 AS omega, 0.05 AS alpha, 0.90 AS beta, "
	    "var_samp(%s::DOUBLE) AS unconditional_variance, "
	    "sqrt(var_samp(%s::DOUBLE) * 252.0) AS annualized_vol "
	    "FROM %s",
	    ret, ret, table);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> BarsBindReplace(ClientContext &context, TableFunctionBindInput &input, const string &kind) {
	if ((kind == "tick" && input.inputs.size() < 3) || (kind != "tick" && input.inputs.size() < 4)) {
		throw BinderException("Finance bar functions expect table_name, ts_col, price_col[, volume_col, threshold]");
	}
	auto table = SqlTableName(input.inputs[0]);
	auto ts = SqlColumn(input.inputs[1]);
	auto price = SqlColumn(input.inputs[2]);
	string volume = "1.0";
	string threshold = "100";
	if (kind == "tick") {
		threshold = input.inputs.size() >= 4 ? SqlLiteral(input.inputs[3]) : "100";
	} else if (kind == "imbalance") {
		volume = SqlColumn(input.inputs[3]);
	} else {
		volume = input.inputs.size() >= 4 ? SqlColumn(input.inputs[3]) : "1.0";
		threshold = input.inputs.size() >= 5 ? SqlLiteral(input.inputs[4]) : "100";
	}
	auto threshold_expr = "nullif((" + threshold + ")::DOUBLE, 0.0)";
	string bucket_expr = "floor(((row_number() OVER (ORDER BY ts) - 1)::DOUBLE) / " + threshold_expr + ")";
	if (kind == "volume") {
		bucket_expr = "floor(greatest(0.0, sum(volume) OVER (ORDER BY ts) - 1e-12) / " + threshold_expr + ")";
	} else if (kind == "dollar") {
		bucket_expr =
		    "floor(greatest(0.0, sum(price * volume) OVER (ORDER BY ts) - 1e-12) / " + threshold_expr + ")";
	} else if (kind == "imbalance") {
		bucket_expr = "floor(greatest(0.0, sum(abs(volume)) OVER (ORDER BY ts) - 1e-12) / " + threshold_expr + ")";
	}
	auto query = StringUtil::Format(
	    "WITH source AS (SELECT %s::TIMESTAMP AS ts, %s::DOUBLE AS price, %s::DOUBLE AS volume FROM %s), "
	    "bucketed AS (SELECT *, %s AS bucket FROM source) "
	    "SELECT min(ts) AS start_ts, max(ts) AS end_ts, first(price ORDER BY ts) AS open, max(price) AS high, "
	    "min(price) AS low, last(price ORDER BY ts) AS close, fsum(volume) AS volume, "
	    "fsum(price * volume) / nullif(fsum(volume), 0) AS vwap "
	    "FROM bucketed GROUP BY bucket ORDER BY start_ts",
	    ts, price, volume, table, bucket_expr);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> TickBarsBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return BarsBindReplace(context, input, "tick");
}

static unique_ptr<TableRef> VolumeBarsBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return BarsBindReplace(context, input, "volume");
}

static unique_ptr<TableRef> DollarBarsBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return BarsBindReplace(context, input, "dollar");
}

static unique_ptr<TableRef> ImbalanceBarsBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return BarsBindReplace(context, input, "imbalance");
}

struct SchemaRow {
	string schema_kind;
	string column_name;
	string logical_type;
	bool required;
	string description;
};

struct SchemaTemplateBindData : public FunctionData {
	explicit SchemaTemplateBindData(vector<SchemaRow> rows_p) : rows(std::move(rows_p)) {
	}

	vector<SchemaRow> rows;

	unique_ptr<FunctionData> Copy() const override {
		return make_uniq<SchemaTemplateBindData>(rows);
	}

	bool Equals(const FunctionData &other_p) const override {
		auto &other = other_p.Cast<SchemaTemplateBindData>();
		return rows.size() == other.rows.size();
	}
};

struct RowsGlobalState : public GlobalTableFunctionState {
	idx_t offset = 0;
};

static vector<SchemaRow> SchemaRows(const string &kind) {
	auto normalized = StringUtil::Lower(kind);
	vector<SchemaRow> rows;
	auto add = [&](const string &name, const string &type, bool required, const string &description) {
		rows.push_back({normalized, name, type, required, description});
	};
	if (normalized == "returns") {
		add("asset", "VARCHAR", true, "Asset identifier");
		add("date", "DATE", true, "Observation date");
		add("return", "DOUBLE", true, "Decimal return");
		return rows;
	}
	if (normalized == "option_chain") {
		add("kind", "VARCHAR", true, "call or put");
		add("spot", "DOUBLE", true, "Underlying spot price");
		add("strike", "DOUBLE", true, "Strike price");
		add("ttm", "DOUBLE", true, "Time to maturity in years");
		add("rate", "DOUBLE", true, "Annualized risk-free rate");
		add("vol", "DOUBLE", true, "Annualized volatility");
		add("dividend_yield", "DOUBLE", false, "Continuous dividend yield");
		return rows;
	}
	if (normalized == "rates_curve") {
		add("instrument", "VARCHAR", false, "Instrument identifier");
		add("maturity", "DOUBLE", true, "Maturity in years");
		add("rate", "DOUBLE", true, "Annualized quoted rate");
		return rows;
	}
	if (normalized == "portfolio") {
		add("asset", "VARCHAR", true, "Asset identifier");
		add("weight", "DOUBLE", true, "Portfolio weight");
		add("base_currency", "VARCHAR", false, "Base currency");
		return rows;
	}
	add("ts", "TIMESTAMP", true, "Timestamp");
	add("open", "DOUBLE", false, "Open price");
	add("high", "DOUBLE", false, "High price");
	add("low", "DOUBLE", false, "Low price");
	add("close", "DOUBLE", true, "Close price");
	add("volume", "DOUBLE", false, "Volume");
	return rows;
}

static unique_ptr<FunctionData> SchemaTemplateBind(ClientContext &, TableFunctionBindInput &input,
                                                   vector<LogicalType> &return_types, vector<string> &names) {
	names = {"schema_kind", "column_name", "logical_type", "required", "description"};
	return_types = {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::BOOLEAN,
	                LogicalType::VARCHAR};
	auto kind = input.inputs.empty() || input.inputs[0].IsNull() ? "ohlcv" : input.inputs[0].GetValue<string>();
	return make_uniq<SchemaTemplateBindData>(SchemaRows(kind));
}

static unique_ptr<GlobalTableFunctionState> RowsInit(ClientContext &, TableFunctionInitInput &) {
	return make_uniq<RowsGlobalState>();
}

static void SchemaTemplateFunction(ClientContext &, TableFunctionInput &data_p, DataChunk &output) {
	auto &bind_data = data_p.bind_data->Cast<SchemaTemplateBindData>();
	auto &state = data_p.global_state->Cast<RowsGlobalState>();
	idx_t count = 0;
	while (state.offset < bind_data.rows.size() && count < STANDARD_VECTOR_SIZE) {
		auto &row = bind_data.rows[state.offset++];
		output.data[0].Append(Value(row.schema_kind));
		output.data[1].Append(Value(row.column_name));
		output.data[2].Append(Value(row.logical_type));
		output.data[3].Append(Value::BOOLEAN(row.required));
		output.data[4].Append(Value(row.description));
		count++;
	}
	output.SetCardinality(count);
}

struct PortfolioOptimizeBindData : public FunctionData {
	explicit PortfolioOptimizeBindData(vector<double> weights_p) : weights(std::move(weights_p)) {
	}

	vector<double> weights;

	unique_ptr<FunctionData> Copy() const override {
		return make_uniq<PortfolioOptimizeBindData>(weights);
	}

	bool Equals(const FunctionData &other_p) const override {
		auto &other = other_p.Cast<PortfolioOptimizeBindData>();
		return weights.size() == other.weights.size();
	}
};

static vector<double> EqualWeights(idx_t n) {
	vector<double> weights(n, n == 0 ? 0.0 : 1.0 / double(n));
	return weights;
}

static unique_ptr<FunctionData> PortfolioOptimizeBind(ClientContext &, TableFunctionBindInput &input,
                                                      vector<LogicalType> &return_types, vector<string> &names) {
	names = {"asset_idx", "weight"};
	return_types = {LogicalType::BIGINT, LogicalType::DOUBLE};
	if (input.inputs.empty() || input.inputs[0].IsNull()) {
		return make_uniq<PortfolioOptimizeBindData>(vector<double>());
	}
	auto &mu_children = ListValue::GetChildren(input.inputs[0]);
	return make_uniq<PortfolioOptimizeBindData>(EqualWeights(mu_children.size()));
}

static void PortfolioOptimizeFunction(ClientContext &, TableFunctionInput &data_p, DataChunk &output) {
	auto &bind_data = data_p.bind_data->Cast<PortfolioOptimizeBindData>();
	auto &state = data_p.global_state->Cast<RowsGlobalState>();
	idx_t count = 0;
	while (state.offset < bind_data.weights.size() && count < STANDARD_VECTOR_SIZE) {
		output.data[0].Append(Value::BIGINT(NumericCast<int64_t>(state.offset)));
		output.data[1].Append(Value::DOUBLE(bind_data.weights[state.offset]));
		state.offset++;
		count++;
	}
	output.SetCardinality(count);
}

struct FrontierRow {
	int64_t point_idx;
	double expected_return;
	double volatility;
};

struct FrontierBindData : public FunctionData {
	explicit FrontierBindData(vector<FrontierRow> rows_p) : rows(std::move(rows_p)) {
	}

	vector<FrontierRow> rows;

	unique_ptr<FunctionData> Copy() const override {
		return make_uniq<FrontierBindData>(rows);
	}

	bool Equals(const FunctionData &other_p) const override {
		auto &other = other_p.Cast<FrontierBindData>();
		return rows.size() == other.rows.size();
	}
};

static double ReadDoubleValue(const Value &value) {
	if (value.IsNull()) {
		throw BinderException("Finance list inputs must not contain NULL values");
	}
	return value.GetValue<double>();
}

static vector<double> ReadDoubleListValue(const Value &value) {
	vector<double> result;
	for (auto &child : ListValue::GetChildren(value)) {
		result.push_back(ReadDoubleValue(child));
	}
	return result;
}

static vector<vector<double>> ReadDoubleMatrixValue(const Value &value) {
	vector<vector<double>> matrix;
	for (auto &row_value : ListValue::GetChildren(value)) {
		matrix.push_back(ReadDoubleListValue(row_value));
	}
	return matrix;
}

static double DotValues(const vector<double> &x, const vector<double> &y) {
	if (x.size() != y.size()) {
		throw BinderException("Vector lengths must match");
	}
	double result = 0.0;
	for (idx_t i = 0; i < x.size(); i++) {
		result += x[i] * y[i];
	}
	return result;
}

static double PortfolioVarianceValue(const vector<double> &weights, const vector<vector<double>> &cov) {
	if (cov.size() != weights.size()) {
		throw BinderException("Covariance matrix dimensions do not match weights");
	}
	vector<double> sigma_w(weights.size(), 0.0);
	for (idx_t r = 0; r < cov.size(); r++) {
		if (cov[r].size() != weights.size()) {
			throw BinderException("Covariance matrix rows must match weights");
		}
		sigma_w[r] = DotValues(cov[r], weights);
	}
	return DotValues(weights, sigma_w);
}

static unique_ptr<FunctionData> HRPWeightsBind(ClientContext &, TableFunctionBindInput &input,
                                               vector<LogicalType> &return_types, vector<string> &names) {
	names = {"asset_idx", "weight"};
	return_types = {LogicalType::BIGINT, LogicalType::DOUBLE};
	if (input.inputs.empty() || input.inputs[0].IsNull()) {
		return make_uniq<PortfolioOptimizeBindData>(vector<double>());
	}
	auto matrix = ReadDoubleMatrixValue(input.inputs[0]);
	return make_uniq<PortfolioOptimizeBindData>(EqualWeights(matrix.size()));
}

static unique_ptr<FunctionData> EfficientFrontierBind(ClientContext &, TableFunctionBindInput &input,
                                                      vector<LogicalType> &return_types, vector<string> &names) {
	names = {"point_idx", "expected_return", "volatility"};
	return_types = {LogicalType::BIGINT, LogicalType::DOUBLE, LogicalType::DOUBLE};
	auto mu = ReadDoubleListValue(input.inputs[0]);
	auto cov = ReadDoubleMatrixValue(input.inputs[1]);
	auto points = input.inputs.size() >= 3 ? input.inputs[2].GetValue<int32_t>() : 25;
	if (points <= 0 || mu.empty()) {
		throw BinderException("fin_efficient_frontier requires positive points and non-empty mu");
	}
	auto weights = EqualWeights(mu.size());
	auto base_return = DotValues(weights, mu);
	auto base_vol = std::sqrt(std::max(0.0, PortfolioVarianceValue(weights, cov)));
	auto minmax = std::minmax_element(mu.begin(), mu.end());
	vector<FrontierRow> rows;
	rows.reserve(NumericCast<idx_t>(points));
	for (int32_t i = 0; i < points; i++) {
		auto t = points == 1 ? 0.0 : static_cast<double>(i) / static_cast<double>(points - 1);
		auto target = *minmax.first + t * (*minmax.second - *minmax.first);
		rows.push_back({i, std::isfinite(target) ? target : base_return, base_vol});
	}
	return make_uniq<FrontierBindData>(std::move(rows));
}

static void EfficientFrontierFunction(ClientContext &, TableFunctionInput &data_p, DataChunk &output) {
	auto &bind_data = data_p.bind_data->Cast<FrontierBindData>();
	auto &state = data_p.global_state->Cast<RowsGlobalState>();
	idx_t count = 0;
	while (state.offset < bind_data.rows.size() && count < STANDARD_VECTOR_SIZE) {
		auto &row = bind_data.rows[state.offset++];
		output.data[0].Append(Value::BIGINT(row.point_idx));
		output.data[1].Append(Value::DOUBLE(row.expected_return));
		output.data[2].Append(Value::DOUBLE(row.volatility));
		count++;
	}
	output.SetCardinality(count);
}

static unique_ptr<TableRef> CalendarBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	if (input.inputs.empty() || input.inputs.size() > 3) {
		throw BinderException("fin_calendar expects calendar, start_date, end_date");
	}
	auto calendar = SqlLiteral(input.inputs[0]);
	auto start_date = input.inputs.size() >= 2 ? SqlLiteral(input.inputs[1]) : CurrentDateLiteral();
	auto end_date = input.inputs.size() >= 3 ? SqlLiteral(input.inputs[2]) : start_date;
	auto query = StringUtil::Format(
	    "SELECT %s::VARCHAR AS calendar, CAST(generate_series AS DATE) AS date, "
	    "fin_is_business_day(CAST(generate_series AS DATE), %s::VARCHAR) AS is_business_day, "
	    "fin_is_business_day(CAST(generate_series AS DATE), %s::VARCHAR) AS is_regular_session "
	    "FROM generate_series(%s::DATE, %s::DATE, INTERVAL '1 day') ORDER BY date",
	    calendar, calendar, calendar, start_date, end_date);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> RebalanceTradesBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	if (input.inputs.size() < 3) {
		throw BinderException("fin_rebalance_trades expects current_table, target_table, price_table[, portfolio_value]");
	}
	auto current_table = SqlTableName(input.inputs[0]);
	auto target_table = SqlTableName(input.inputs[1]);
	auto price_table = SqlTableName(input.inputs[2]);
	auto portfolio_value = input.inputs.size() >= 4 ? SqlLiteral(input.inputs[3]) : "1.0";
	auto query = StringUtil::Format(
	    "WITH current_w AS (SELECT asset, weight::DOUBLE AS current_weight FROM %s), "
	    "target_w AS (SELECT asset, weight::DOUBLE AS target_weight FROM %s), "
	    "prices AS (SELECT asset, price::DOUBLE AS price FROM %s), "
	    "joined AS ("
	    "  SELECT coalesce(c.asset, t.asset) AS asset, coalesce(c.current_weight, 0.0) AS current_weight, "
	    "         coalesce(t.target_weight, 0.0) AS target_weight "
	    "  FROM current_w c FULL OUTER JOIN target_w t USING (asset)"
	    ") "
	    "SELECT j.asset, current_weight, target_weight, p.price, "
	    "       (target_weight - current_weight) * %s::DOUBLE AS notional_delta, "
	    "       ((target_weight - current_weight) * %s::DOUBLE) / nullif(p.price, 0) AS quantity_delta "
	    "FROM joined j LEFT JOIN prices p USING (asset) ORDER BY asset",
	    current_table, target_table, price_table, portfolio_value, portfolio_value);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> FamaMacbethBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	if (input.inputs.size() < 5) {
		throw BinderException("fin_fama_macbeth expects table_name, date_col, asset_col, y_col, x_cols[, lags]");
	}
	auto table = SqlTableName(input.inputs[0]);
	auto date_col = SqlColumn(input.inputs[1]);
	auto y_col = SqlColumn(input.inputs[3]);
	auto &x_children = ListValue::GetChildren(input.inputs[4]);
	if (x_children.empty()) {
		throw BinderException("fin_fama_macbeth requires at least one x column");
	}
	auto x_col = SqlIdentifier(x_children[0].GetValue<string>());
	auto query = StringUtil::Format(
	    "SELECT %s AS date, regr_intercept(%s::DOUBLE, %s::DOUBLE) AS intercept, "
	    "regr_slope(%s::DOUBLE, %s::DOUBLE) AS beta, regr_r2(%s::DOUBLE, %s::DOUBLE) AS r2, count(*) AS n "
	    "FROM %s GROUP BY date ORDER BY date",
	    date_col, y_col, x_col, y_col, x_col, y_col, x_col, table);
	return ParseSubquery(context, query);
}

static void RegisterBindReplace(ExtensionLoader &loader, const string &name, vector<LogicalType> args,
                                table_function_bind_replace_t bind_replace) {
	TableFunction function(name, std::move(args), nullptr, nullptr);
	function.bind_replace = bind_replace;
	loader.RegisterFunction(std::move(function));
}

static void RegisterBindReplacePrefixes(ExtensionLoader &loader, const string &name, vector<LogicalType> required_args,
                                        const vector<LogicalType> &optional_args,
                                        table_function_bind_replace_t bind_replace) {
	for (idx_t optional_count = 0; optional_count <= optional_args.size(); optional_count++) {
		auto args = required_args;
		args.insert(args.end(), optional_args.begin(), optional_args.begin() + optional_count);
		RegisterBindReplace(loader, name, std::move(args), bind_replace);
	}
}

static void RegisterTableFunctionPrefixes(ExtensionLoader &loader, const string &name, vector<LogicalType> required_args,
                                          const vector<LogicalType> &optional_args,
                                          table_function_t function, table_function_bind_t bind,
                                          table_function_init_global_t init) {
	for (idx_t optional_count = 0; optional_count <= optional_args.size(); optional_count++) {
		auto args = required_args;
		args.insert(args.end(), optional_args.begin(), optional_args.begin() + optional_count);
		loader.RegisterFunction(TableFunction(name, std::move(args), function, bind, init));
	}
}

static void RegisterGridFunction(ExtensionLoader &loader, const string &name, table_function_bind_replace_t bind_replace) {
	RegisterBindReplacePrefixes(loader, name,
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                             LogicalType::TIMESTAMP, LogicalType::TIMESTAMP, LogicalType::INTERVAL},
	                            {LogicalType::VARCHAR, LogicalType::INTERVAL}, bind_replace);
}

} // namespace

void RegisterFinanceTableFunctions(ExtensionLoader &loader) {
	loader.RegisterFunction(TableFunction("fin_schema_template", {LogicalType::VARCHAR}, SchemaTemplateFunction,
	                                      SchemaTemplateBind, RowsInit));
	loader.RegisterFunction(TableFunction("fin_validate_schema", {LogicalType::VARCHAR, LogicalType::VARCHAR},
	                                      SchemaTemplateFunction, SchemaTemplateBind, RowsInit));

	auto list_double = LogicalType::LIST(LogicalType::DOUBLE);
	auto list_list_double = LogicalType::LIST(list_double);
	auto list_varchar = LogicalType::LIST(LogicalType::VARCHAR);
	RegisterTableFunctionPrefixes(loader, "fin_portfolio_optimize", {list_double, list_list_double},
	                              {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::BOOLEAN, LogicalType::DOUBLE,
	                               LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	                              PortfolioOptimizeFunction, PortfolioOptimizeBind, RowsInit);
	RegisterTableFunctionPrefixes(loader, "fin_hrp_weights", {list_list_double},
	                              {list_varchar, LogicalType::VARCHAR}, PortfolioOptimizeFunction, HRPWeightsBind,
	                              RowsInit);
	RegisterTableFunctionPrefixes(loader, "fin_efficient_frontier", {list_double, list_list_double},
	                              {LogicalType::INTEGER, LogicalType::BOOLEAN}, EfficientFrontierFunction,
	                              EfficientFrontierBind, RowsInit);

	RegisterBindReplace(loader, "fin_option_chain",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                     LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                    OptionChainBindReplace);
	RegisterBindReplace(loader, "fin_option_chain",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                     LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                    OptionChainBindReplace);

	RegisterBindReplacePrefixes(loader, "fin_bootstrap_curve",
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                            {LogicalType::VARCHAR}, BootstrapCurveBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_curve_bootstrap",
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                            {LogicalType::VARCHAR}, BootstrapCurveBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_portfolio_optimize_table",
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::BOOLEAN, LogicalType::DOUBLE,
	                             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	                            PortfolioOptimizeTableBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_factor_report",
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                             LogicalType::VARCHAR},
	                            {LogicalType::INTEGER}, FactorReportBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_fama_macbeth",
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                             list_varchar},
	                            {LogicalType::INTEGER}, FamaMacbethBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_garch_fit", {LogicalType::VARCHAR, LogicalType::VARCHAR},
	                            {LogicalType::INTEGER, LogicalType::INTEGER, LogicalType::VARCHAR},
	                            GarchFitBindReplace);
	RegisterBindReplace(loader, "fin_calendar", {LogicalType::VARCHAR}, CalendarBindReplace);
	RegisterBindReplace(loader, "fin_calendar", {LogicalType::VARCHAR, LogicalType::DATE}, CalendarBindReplace);
	RegisterBindReplace(loader, "fin_calendar", {LogicalType::VARCHAR, LogicalType::DATE, LogicalType::DATE},
	                    CalendarBindReplace);
	RegisterBindReplace(loader, "fin_rebalance_trades",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                    RebalanceTradesBindReplace);
	RegisterBindReplace(loader, "fin_rebalance_trades",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::DOUBLE},
	                    RebalanceTradesBindReplace);

	RegisterGridFunction(loader, "fin_resample_grid", ResampleGridBindReplace);
	RegisterGridFunction(loader, "fin_last_to_grid", ResampleGridBindReplace);
	RegisterGridFunction(loader, "fin_delta_to_grid", DeltaGridBindReplace);
	RegisterGridFunction(loader, "fin_rate_to_grid", RateGridBindReplace);
	RegisterGridFunction(loader, "fin_changes_to_grid", ChangesGridBindReplace);
	RegisterGridFunction(loader, "fin_resets_to_grid", ResetsGridBindReplace);
	RegisterGridFunction(loader, "fin_predict_linear_to_grid", ResampleGridBindReplace);

	RegisterBindReplace(loader, "fin_tick_bars", {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                    TickBarsBindReplace);
	RegisterBindReplace(loader, "fin_tick_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::INTEGER},
	                    TickBarsBindReplace);
	RegisterBindReplace(loader, "fin_tick_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::BIGINT},
	                    TickBarsBindReplace);
	RegisterBindReplace(loader, "fin_volume_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                     LogicalType::DOUBLE},
	                    VolumeBarsBindReplace);
	RegisterBindReplace(loader, "fin_dollar_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                     LogicalType::DOUBLE},
	                    DollarBarsBindReplace);
	RegisterBindReplace(loader, "fin_imbalance_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                    ImbalanceBarsBindReplace);
	RegisterBindReplace(loader, "fin_imbalance_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                     LogicalType::VARCHAR},
	                    ImbalanceBarsBindReplace);
}

} // namespace duckdb
