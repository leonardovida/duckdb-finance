static string BSMArguments(const string &kind, const string &spot, const string &strike, const string &ttm,
                           const string &rate, const string &vol, const string &dividend_yield) {
	return StringUtil::Format("%s, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE", kind, spot,
	                          strike, ttm, rate, vol, dividend_yield);
}

static unique_ptr<TableRef> OptionChainBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	RequireInputCountBetween(input, 7, 8,
	                         "fin_option_chain expects table_name, kind_col, spot_col, strike_col, ttm_col, rate_col, "
	                         "vol_col[, dividend_yield_col]");
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
	    "__finance_bsm_all.price AS model_price, "
	    "__finance_bsm_all.delta AS model_delta, "
	    "__finance_bsm_all.gamma AS model_gamma, "
	    "__finance_bsm_all.vega AS model_vega, "
	    "__finance_bsm_all.theta AS model_theta, "
	    "__finance_bsm_all.rho AS model_rho, "
	    "fin_bsm_implied_vol(%s, __finance_bsm_all.price, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, "
	    "%s::DOUBLE) AS model_implied_volatility "
	    "FROM priced",
	    args, table, kind, spot, strike, ttm, rate, q, vol);
	return ParseSubquery(context, query);
}
