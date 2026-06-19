static unique_ptr<TableRef> NormalizeOhlcvBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	RequireInputCountBetween(input, 7, 8,
	                         "fin_normalize_ohlcv expects table_name, ts_col, open_col, high_col, low_col, close_col, "
	                         "volume_col[, asset_col]");
	auto table = SqlTableName(input.inputs[0]);
	auto ts = SqlColumn(input.inputs[1]);
	auto open = SqlColumn(input.inputs[2]);
	auto high = SqlColumn(input.inputs[3]);
	auto low = SqlColumn(input.inputs[4]);
	auto close = SqlColumn(input.inputs[5]);
	auto volume = SqlColumn(input.inputs[6]);
	auto asset = input.inputs.size() == 8 ? SqlColumn(input.inputs[7]) : "CAST(NULL AS VARCHAR)";
	auto query = StringUtil::Format(
	    "SELECT %s::TIMESTAMP AS ts, %s::VARCHAR AS asset_id, %s::DOUBLE AS open, %s::DOUBLE AS high, "
	    "%s::DOUBLE AS low, %s::DOUBLE AS close, %s::DOUBLE AS volume "
	    "FROM %s ORDER BY ts, asset_id",
	    ts, asset, open, high, low, close, volume, table);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> NormalizeReturnsBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	RequireInputCountExactly(input, 4, "fin_normalize_returns expects table_name, date_col, asset_col, return_col");
	auto table = SqlTableName(input.inputs[0]);
	auto date = SqlColumn(input.inputs[1]);
	auto asset = SqlColumn(input.inputs[2]);
	auto ret = SqlColumn(input.inputs[3]);
	auto query = StringUtil::Format(
	    "SELECT %s::DATE AS date, %s::VARCHAR AS asset_id, %s::DOUBLE AS return_decimal "
	    "FROM %s ORDER BY date, asset_id",
	    date, asset, ret, table);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> NormalizeOptionChainBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	RequireInputCountBetween(input, 8, 9,
	                         "fin_normalize_option_chain expects table_name, kind_col, underlying_price_col, "
	                         "strike_col, expiry_col, valuation_date_col, rate_col, vol_col[, dividend_yield_col]");
	auto table = SqlTableName(input.inputs[0]);
	auto kind = SqlColumn(input.inputs[1]);
	auto underlying = SqlColumn(input.inputs[2]);
	auto strike = SqlColumn(input.inputs[3]);
	auto expiry = SqlColumn(input.inputs[4]);
	auto valuation = SqlColumn(input.inputs[5]);
	auto rate = SqlColumn(input.inputs[6]);
	auto vol = SqlColumn(input.inputs[7]);
	auto dividend_yield = input.inputs.size() == 9 ? SqlColumn(input.inputs[8]) : "0.0";
	auto query = StringUtil::Format(
	    "SELECT fin_parse_option_kind(%s::VARCHAR) AS option_kind, %s::DOUBLE AS underlying_price, "
	    "%s::DOUBLE AS strike_price, %s::DATE AS expiry_date, %s::DATE AS valuation_date, "
	    "fin_yearfrac(%s::DATE, %s::DATE, 'ACT/365F') AS time_to_expiry_years, "
	    "%s::DOUBLE AS risk_free_rate, %s::DOUBLE AS implied_volatility, %s::DOUBLE AS dividend_yield, "
	    "fin_option_spec_dates(%s::VARCHAR, %s::DOUBLE, %s::DOUBLE, %s::DATE, %s::DATE, %s::DOUBLE, %s::DOUBLE, "
	    "%s::DOUBLE) AS option_spec "
	    "FROM %s ORDER BY expiry_date, strike_price, option_kind",
	    kind, underlying, strike, expiry, valuation, valuation, expiry, rate, vol, dividend_yield, kind, underlying,
	    strike, valuation, expiry, rate, vol, dividend_yield, table);
	return ParseSubquery(context, query);
}
