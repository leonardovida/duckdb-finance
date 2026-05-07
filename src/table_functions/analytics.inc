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
