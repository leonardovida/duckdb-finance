static unique_ptr<TableRef> PortfolioOptimizeTableBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_portfolio_optimize_table";
	auto table = SqlSourceArg(input, 0, function_name);
	auto asset = SqlColumnArg(input, 1, function_name, "asset_col");
	auto date = SqlColumnArg(input, 2, function_name, "date_col");
	auto ret = SqlColumnArg(input, 3, function_name, "return_col");
	// date_col and return_col are bound (so misspelled names fail) but not used
	// by the equal-weight placeholder.
	auto query = StringUtil::Format(
	    "WITH __finance_assets AS ("
	    "  SELECT DISTINCT asset FROM (SELECT %s AS asset, %s AS __finance_date, %s AS __finance_ret FROM %s) "
	    "  WHERE asset IS NOT NULL"
	    ") "
	    "SELECT asset, row_number() OVER (ORDER BY asset) - 1 AS asset_idx, 1.0::DOUBLE / count(*) OVER () AS weight "
	    "FROM __finance_assets ORDER BY asset",
	    asset, date, ret, table);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> PortfolioReturnTableBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_portfolio_return_table";
	RequireInputCountBetween(input, 4, 5,
	                         "fin_portfolio_return_table expects table_name, asset_col, weight_col, return_col[, "
	                         "date_col]");
	auto table = SqlSourceArg(input, 0, function_name);
	auto asset = SqlColumnArg(input, 1, function_name, "asset_col");
	auto weight = SqlColumnArg(input, 2, function_name, "weight_col");
	auto ret = SqlColumnArg(input, 3, function_name, "return_col");
	auto date = input.inputs.size() == 5 ? SqlColumnArg(input, 4, function_name, "date_col") : string();
	auto date_select = date.empty() ? string() : date + " AS __finance_date, ";
	auto date_group = date.empty() ? string() : string("__finance_date, ");
	auto date_output = date.empty() ? string() : "__finance_date AS " + date + ", ";
	auto query = StringUtil::Format(
	    "WITH __finance_positions AS ("
	    "  SELECT %s__finance_asset, "
	    "    CASE WHEN count(*) > 1 THEN error('fin_portfolio_return_table: duplicate asset ' || "
	    "      __finance_asset || ' (one row per asset%s is required)') END AS __finance_check, "
	    "    any_value(__finance_weight) AS __finance_weight, any_value(__finance_return) AS __finance_return "
	    "  FROM (SELECT %s%s::VARCHAR AS __finance_asset, %s::DOUBLE AS __finance_weight, "
	    "    %s::DOUBLE AS __finance_return FROM %s WHERE %s IS NOT NULL) "
	    "  GROUP BY %s__finance_asset"
	    ") "
	    "SELECT %sfsum(__finance_weight * __finance_return) AS portfolio_return, fsum(__finance_weight) AS weight_sum, "
	    "count(__finance_asset) AS asset_count "
	    "FROM __finance_positions WHERE __finance_check IS NULL%s%s",
	    date_group, date.empty() ? "" : " and date", date_select, asset, weight, ret, table, asset, date_group,
	    date_output,
	    date.empty() ? "" : " GROUP BY __finance_date ORDER BY __finance_date", "");
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> PortfolioVarianceTableBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_portfolio_variance_table";
	RequireInputCountExactly(input, 7,
	                         "fin_portfolio_variance_table expects weights_table, asset_col, weight_col, "
	                         "covariance_table, asset_i_col, asset_j_col, covariance_col");
	auto weights_table = SqlSourceArg(input, 0, function_name, "weights_table");
	auto weight_asset = SqlColumnArg(input, 1, function_name, "asset_col");
	auto weight = SqlColumnArg(input, 2, function_name, "weight_col");
	auto covariance_table = SqlSourceArg(input, 3, function_name, "covariance_table");
	auto asset_i = SqlColumnArg(input, 4, function_name, "asset_i_col");
	auto asset_j = SqlColumnArg(input, 5, function_name, "asset_j_col");
	auto covariance = SqlColumnArg(input, 6, function_name, "covariance_col");
	auto query = StringUtil::Format(
	    "WITH __finance_weights AS ("
	    "  SELECT %s::VARCHAR AS asset_id, CASE WHEN count(*) > 1 THEN "
	    "    error('fin_portfolio_variance_table: duplicate weight for asset ' || %s::VARCHAR) "
	    "    ELSE any_value(%s::DOUBLE) END AS weight "
	    "  FROM %s WHERE %s IS NOT NULL GROUP BY 1"
	    "), __finance_cov_input AS ("
	    "  SELECT %s::VARCHAR AS asset_i, %s::VARCHAR AS asset_j, CASE WHEN count(*) > 1 THEN "
	    "    error('fin_portfolio_variance_table: duplicate covariance for pair ' || %s::VARCHAR || ', ' || "
	    "    %s::VARCHAR) ELSE any_value(%s::DOUBLE) END AS covariance "
	    "  FROM %s WHERE %s IS NOT NULL AND %s IS NOT NULL GROUP BY 1, 2"
	    "), __finance_cov AS ("
	    "  SELECT asset_i, asset_j, covariance FROM __finance_cov_input "
	    "  UNION ALL "
	    "  SELECT c.asset_j, c.asset_i, c.covariance FROM __finance_cov_input c "
	    "  WHERE c.asset_i <> c.asset_j AND NOT EXISTS ("
	    "    SELECT 1 FROM __finance_cov_input m WHERE m.asset_i = c.asset_j AND m.asset_j = c.asset_i)"
	    "), __finance_missing AS ("
	    "  SELECT min(w.asset_id) AS asset_id FROM __finance_weights w "
	    "  LEFT JOIN __finance_cov_input c ON c.asset_i = w.asset_id AND c.asset_j = w.asset_id "
	    "  WHERE w.weight <> 0 AND c.covariance IS NULL"
	    "), __finance_risk AS ("
	    "  SELECT fsum(wi.weight * c.covariance * wj.weight) AS portfolio_variance "
	    "  FROM __finance_cov c "
	    "  JOIN __finance_weights wi ON wi.asset_id = c.asset_i "
	    "  JOIN __finance_weights wj ON wj.asset_id = c.asset_j"
	    ") "
	    "SELECT portfolio_variance, CASE WHEN portfolio_variance IS NOT NULL THEN sqrt(greatest(portfolio_variance, "
	    "0.0)) END AS portfolio_volatility FROM ("
	    "  SELECT CASE "
	    "    WHEN (SELECT asset_id FROM __finance_missing) IS NOT NULL THEN "
	    "      error('fin_portfolio_variance_table: missing variance (diagonal covariance) for asset ' || "
	    "      (SELECT asset_id FROM __finance_missing)) "
	    "    WHEN (SELECT count(*) FROM __finance_weights) = 0 THEN NULL "
	    "    ELSE coalesce(portfolio_variance, 0.0) END::DOUBLE AS portfolio_variance "
	    "  FROM __finance_risk)",
	    weight_asset, weight_asset, weight, weights_table, weight_asset, asset_i, asset_j, asset_i, asset_j, covariance,
	    covariance_table, asset_i, asset_j);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> FactorReportBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_factor_report";
	auto table = SqlSourceArg(input, 0, function_name);
	auto date = SqlColumnArg(input, 1, function_name, "date_col");
	auto asset = SqlColumnArg(input, 2, function_name, "asset_col");
	auto factor = SqlColumnArg(input, 3, function_name, "factor_col");
	auto ret = SqlColumnArg(input, 4, function_name, "return_col");
	int64_t buckets = 5;
	if (input.inputs.size() >= 6) {
		buckets = RequireInteger(input.inputs[5], function_name, "buckets");
	}
	if (buckets < 2 || buckets > 1000) {
		throw InvalidInputException("%s: buckets must be between 2 and 1000", function_name);
	}
	// Cross-sectional statistics per date, then time-series averages across dates.
	auto query = StringUtil::Format(
	    "WITH __finance_factor_source AS ("
	    "  SELECT %s AS __finance_date, %s AS __finance_asset, %s::DOUBLE AS __finance_factor, "
	    "    %s::DOUBLE AS __finance_ret FROM %s "
	    "  WHERE %s IS NOT NULL AND %s IS NOT NULL AND isfinite(%s::DOUBLE) AND isfinite(%s::DOUBLE)"
	    "), __finance_factor_ranked AS ("
	    "  SELECT *, "
	    "    ntile(%lld) OVER (PARTITION BY __finance_date ORDER BY __finance_factor, __finance_asset) AS __finance_bucket, "
	    "    rank() OVER (PARTITION BY __finance_date ORDER BY __finance_factor) "
	    "      + (count(*) OVER (PARTITION BY __finance_date, __finance_factor) - 1) / 2.0 AS __finance_factor_rank, "
	    "    rank() OVER (PARTITION BY __finance_date ORDER BY __finance_ret) "
	    "      + (count(*) OVER (PARTITION BY __finance_date, __finance_ret) - 1) / 2.0 AS __finance_ret_rank "
	    "  FROM __finance_factor_source"
	    "), __finance_factor_dates AS ("
	    "  SELECT __finance_date, "
	    "    CASE WHEN isfinite(corr(__finance_factor, __finance_ret)) THEN corr(__finance_factor, __finance_ret) END AS ic, "
	    "    CASE WHEN isfinite(corr(__finance_factor_rank, __finance_ret_rank)) "
	    "      THEN corr(__finance_factor_rank, __finance_ret_rank) END AS rank_ic, avg(__finance_ret) AS mean_return, "
	    "    avg(__finance_ret) FILTER (WHERE __finance_bucket = %lld) "
	    "      - avg(__finance_ret) FILTER (WHERE __finance_bucket = 1) AS quantile_spread, count(*) AS n "
	    "  FROM __finance_factor_ranked GROUP BY 1"
	    ") "
	    "SELECT avg(ic) AS ic, stddev_samp(ic) AS ic_std, avg(ic) / nullif(stddev_samp(ic), 0) AS ic_ir, "
	    "avg(ic) / nullif(stddev_samp(ic) / sqrt(count(ic)), 0) AS ic_tstat, avg(rank_ic) AS rank_ic, "
	    "avg(mean_return) AS mean_return, avg(quantile_spread) AS quantile_spread, count(ic) AS n_dates, "
	    "sum(n)::BIGINT AS n_obs "
	    "FROM __finance_factor_dates",
	    date, asset, factor, ret, table, date, asset, factor, ret, static_cast<long long>(buckets),
	    static_cast<long long>(buckets));
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> GarchFitBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_garch_fit";
	auto table = SqlSourceArg(input, 0, function_name);
	auto ret = SqlColumnArg(input, 1, function_name, "return_col");
	if (input.inputs.size() >= 3 && RequireInteger(input.inputs[2], function_name, "p") != 1) {
		throw InvalidInputException("%s: only p = 1 is supported", function_name);
	}
	if (input.inputs.size() >= 4 && RequireInteger(input.inputs[3], function_name, "q") != 1) {
		throw InvalidInputException("%s: only q = 1 is supported", function_name);
	}
	if (input.inputs.size() >= 5) {
		auto distribution = StringUtil::Lower(RequireString(input.inputs[4], function_name, "distribution"));
		StringUtil::Trim(distribution);
		if (distribution != "normal") {
			throw InvalidInputException("%s: unknown distribution '%s' (only 'normal' is supported)", function_name,
			                            distribution);
		}
	}
	auto query = StringUtil::Format(
	    "SELECT 1::BIGINT AS p, 1::BIGINT AS q, 0.000001::DOUBLE AS omega, 0.05::DOUBLE AS alpha, "
	    "0.90::DOUBLE AS beta, var_samp(%s::DOUBLE) AS unconditional_variance, "
	    "sqrt(var_samp(%s::DOUBLE) * 252.0) AS annualized_vol "
	    "FROM %s",
	    ret, ret, table);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> CalendarBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_calendar";
	RequireInputCountBetween(input, 1, 3, "fin_calendar expects calendar, start_date, end_date");
	auto calendar = SqlStringLiteral(RequireString(input.inputs[0], function_name, "calendar"));
	auto start_date = input.inputs.size() >= 2 ? SqlLiteral(RequireArgument(input, 1, function_name, "start_date"))
	                                           : CurrentDateSql(context);
	auto end_date =
	    input.inputs.size() >= 3 ? SqlLiteral(RequireArgument(input, 2, function_name, "end_date")) : start_date;
	auto query = StringUtil::Format(
	    "SELECT %s::VARCHAR AS calendar, CAST(generate_series AS DATE) AS date, "
	    "fin_is_business_day(CAST(generate_series AS DATE), %s::VARCHAR) AS is_business_day, "
	    "fin_is_business_day(CAST(generate_series AS DATE), %s::VARCHAR) AS is_regular_session "
	    "FROM generate_series(%s::DATE, %s::DATE, INTERVAL '1 day') ORDER BY date",
	    calendar, calendar, calendar, start_date, end_date);
	return ParseSubquery(context, query);
}

static string NamedColumnOr(const TableFunctionBindInput &input, const string &name, const string &fallback,
                            const string &function_name) {
	auto column = OptionalNamedColumn(input, name, function_name);
	return column.empty() ? SqlIdentifier(fallback) : column;
}

static unique_ptr<TableRef> RebalanceTradesBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_rebalance_trades";
	auto current_table = SqlSourceArg(input, 0, function_name, "current_table");
	auto target_table = SqlSourceArg(input, 1, function_name, "target_table");
	auto price_table = SqlSourceArg(input, 2, function_name, "price_table");
	double portfolio_value = 1.0;
	if (input.inputs.size() >= 4) {
		portfolio_value = RequireFiniteDouble(input.inputs[3], function_name, "portfolio_value");
	}
	auto asset = NamedColumnOr(input, "asset_col", "asset", function_name);
	auto weight = NamedColumnOr(input, "weight_col", "weight", function_name);
	auto price = NamedColumnOr(input, "price_col", "price", function_name);
	auto unique_rows = [&](const string &label, const string &value_column, const string &table) {
		return StringUtil::Format(
		    "SELECT %s AS asset, CASE WHEN count(*) > 1 THEN error('fin_rebalance_trades: duplicate asset ' || "
		    "%s::VARCHAR || ' in %s') ELSE any_value(%s::DOUBLE) END AS value FROM %s WHERE %s IS NOT NULL GROUP BY 1",
		    asset, asset, label, value_column, table, asset);
	};
	auto value_literal = DoubleLiteral(portfolio_value);
	auto query = StringUtil::Format(
	    "WITH __finance_current_w AS (%s), __finance_target_w AS (%s), __finance_prices AS (%s), "
	    "__finance_joined AS ("
	    "  SELECT coalesce(c.asset, t.asset) AS asset, coalesce(c.value, 0.0) AS current_weight, "
	    "         coalesce(t.value, 0.0) AS target_weight "
	    "  FROM __finance_current_w c FULL OUTER JOIN __finance_target_w t ON c.asset = t.asset"
	    ") "
	    "SELECT j.asset AS %s, current_weight, target_weight, p.value AS %s, "
	    "       (target_weight - current_weight) * %s AS notional_delta, "
	    "       ((target_weight - current_weight) * %s) / nullif(p.value, 0) AS quantity_delta "
	    "FROM __finance_joined j LEFT JOIN __finance_prices p ON j.asset = p.asset ORDER BY j.asset",
	    unique_rows("current weights", weight, current_table), unique_rows("target weights", weight, target_table),
	    unique_rows("prices", price, price_table), asset, price, value_literal, value_literal);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> FamaMacbethBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_fama_macbeth";
	auto table = SqlSourceArg(input, 0, function_name);
	auto date_col = SqlColumnArg(input, 1, function_name, "date_col");
	auto asset_col = SqlColumnArg(input, 2, function_name, "asset_col");
	auto y_col = SqlColumnArg(input, 3, function_name, "y_col");
	auto &x_list = RequireArgument(input, 4, function_name, "x_cols");
	auto &x_children = ListValue::GetChildren(x_list);
	if (x_children.empty()) {
		throw InvalidInputException("%s: x_cols requires at least one column", function_name);
	}
	auto x_col = SqlColumn(x_children[0], function_name, "x_cols element");
	if (input.inputs.size() >= 6) {
		auto lags = RequireInteger(input.inputs[5], function_name, "lags");
		if (lags < 0) {
			throw InvalidInputException("%s: lags must be non-negative", function_name);
		}
	}
	auto query = StringUtil::Format(
	    "SELECT __finance_date AS date, regr_intercept(__finance_y, __finance_x) AS intercept, "
	    "regr_slope(__finance_y, __finance_x) AS beta, regr_r2(__finance_y, __finance_x) AS r2, "
	    "regr_count(__finance_y, __finance_x)::BIGINT AS n "
	    "FROM (SELECT %s AS __finance_date, %s AS __finance_asset, %s::DOUBLE AS __finance_y, "
	    "%s::DOUBLE AS __finance_x FROM %s) GROUP BY 1 ORDER BY 1",
	    date_col, asset_col, y_col, x_col, table);
	return ParseSubquery(context, query);
}
