// Normalizers project source columns into canonical names and pass every other
// source column through unchanged after the canonical ones. Source columns that
// were consumed, or whose name collides with a canonical output name, are not
// repeated. No ORDER BY is applied; sort the result explicitly when needed.

// The __finance_pad column keeps COLUMNS(...) non-empty when every source column
// was consumed; it is removed again by the outer projection.
static string NormalizedQuery(const string &canonical_select, const vector<string> &consumed,
                              const vector<string> &canonical, const string &table) {
	vector<string> names;
	for (auto &name : consumed) {
		names.push_back(SqlStringLiteral(StringUtil::Lower(name)));
	}
	for (auto &name : canonical) {
		names.push_back(SqlStringLiteral(StringUtil::Lower(name)));
	}
	return "SELECT * EXCLUDE (__finance_pad) FROM (SELECT " + canonical_select +
	       ", COLUMNS(lambda __finance_c: __finance_c = '__finance_pad' OR NOT list_contains([" +
	       StringUtil::Join(names, ", ") + "], lower(__finance_c))) FROM (SELECT *, NULL AS __finance_pad FROM " +
	       table + "))";
}

static string RequireColumnName(const TableFunctionBindInput &input, idx_t index, const string &function_name,
                                const string &parameter) {
	return RequireString(RequireArgument(input, index, function_name, parameter), function_name, parameter);
}

static unique_ptr<TableRef> NormalizeOhlcvBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_normalize_ohlcv";
	RequireInputCountBetween(input, 7, 8,
	                         "fin_normalize_ohlcv expects table_name, ts_col, open_col, high_col, low_col, close_col, "
	                         "volume_col[, asset_col]");
	auto table = SqlSourceArg(input, 0, function_name);
	vector<string> parameters = {"ts_col", "open_col", "high_col", "low_col", "close_col", "volume_col", "asset_col"};
	vector<string> consumed;
	for (idx_t i = 1; i < input.inputs.size(); i++) {
		consumed.push_back(RequireColumnName(input, i, function_name, parameters[i - 1]));
	}
	auto asset = input.inputs.size() == 8 ? SqlIdentifier(consumed[6]) + "::VARCHAR" : "CAST(NULL AS VARCHAR)";
	auto canonical = StringUtil::Format(
	    "%s::TIMESTAMP AS ts, %s AS asset_id, %s::DOUBLE AS open, %s::DOUBLE AS high, "
	    "%s::DOUBLE AS low, %s::DOUBLE AS close, %s::DOUBLE AS volume",
	    SqlIdentifier(consumed[0]), asset, SqlIdentifier(consumed[1]), SqlIdentifier(consumed[2]),
	    SqlIdentifier(consumed[3]), SqlIdentifier(consumed[4]), SqlIdentifier(consumed[5]));
	auto query =
	    NormalizedQuery(canonical, consumed, {"ts", "asset_id", "open", "high", "low", "close", "volume"}, table);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> NormalizeReturnsBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_normalize_returns";
	RequireInputCountExactly(input, 4, "fin_normalize_returns expects table_name, date_col, asset_col, return_col");
	auto table = SqlSourceArg(input, 0, function_name);
	auto date = RequireColumnName(input, 1, function_name, "date_col");
	auto asset = RequireColumnName(input, 2, function_name, "asset_col");
	auto ret = RequireColumnName(input, 3, function_name, "return_col");
	auto canonical = StringUtil::Format("%s::DATE AS date, %s::VARCHAR AS asset_id, %s::DOUBLE AS return_decimal",
	                                    SqlIdentifier(date), SqlIdentifier(asset), SqlIdentifier(ret));
	auto query = NormalizedQuery(canonical, {date, asset, ret}, {"date", "asset_id", "return_decimal"}, table);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> NormalizeOptionChainBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_normalize_option_chain";
	RequireInputCountBetween(input, 8, 9,
	                         "fin_normalize_option_chain expects table_name, kind_col, underlying_price_col, "
	                         "strike_col, expiry_col, valuation_date_col, rate_col, vol_col[, dividend_yield_col]");
	auto table = SqlSourceArg(input, 0, function_name);
	vector<string> parameters = {"kind_col",           "underlying_price_col", "strike_col", "expiry_col",
	                             "valuation_date_col", "rate_col",             "vol_col",    "dividend_yield_col"};
	vector<string> consumed;
	for (idx_t i = 1; i < input.inputs.size(); i++) {
		consumed.push_back(RequireColumnName(input, i, function_name, parameters[i - 1]));
	}
	auto kind = SqlIdentifier(consumed[0]);
	auto underlying = SqlIdentifier(consumed[1]);
	auto strike = SqlIdentifier(consumed[2]);
	auto expiry = SqlIdentifier(consumed[3]);
	auto valuation = SqlIdentifier(consumed[4]);
	auto rate = SqlIdentifier(consumed[5]);
	auto vol = SqlIdentifier(consumed[6]);
	auto dividend_yield = input.inputs.size() == 9 ? SqlIdentifier(consumed[7]) : "0.0";
	auto canonical = StringUtil::Format(
	    "fin_parse_option_kind(%s::VARCHAR) AS option_kind, %s::DOUBLE AS underlying_price, "
	    "%s::DOUBLE AS strike_price, %s::DATE AS expiry_date, %s::DATE AS valuation_date, "
	    "fin_yearfrac(%s::DATE, %s::DATE, 'ACT/365F') AS time_to_expiry_years, "
	    "%s::DOUBLE AS risk_free_rate, %s::DOUBLE AS implied_volatility, %s::DOUBLE AS dividend_yield, "
	    "fin_option_spec_dates(%s::VARCHAR, %s::DOUBLE, %s::DOUBLE, %s::DATE, %s::DATE, %s::DOUBLE, %s::DOUBLE, "
	    "%s::DOUBLE) AS option_spec",
	    kind, underlying, strike, expiry, valuation, valuation, expiry, rate, vol, dividend_yield, kind, underlying,
	    strike, valuation, expiry, rate, vol, dividend_yield);
	auto query = NormalizedQuery(canonical, consumed,
	                             {"option_kind", "underlying_price", "strike_price", "expiry_date", "valuation_date",
	                              "time_to_expiry_years", "risk_free_rate", "implied_volatility", "dividend_yield",
	                              "option_spec"},
	                             table);
	return ParseSubquery(context, query);
}
