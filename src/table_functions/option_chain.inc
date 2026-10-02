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
	auto kind = "__finance_source." + SqlColumn(input.inputs[1]);
	auto spot = "__finance_source." + SqlColumn(input.inputs[2]);
	auto strike = "__finance_source." + SqlColumn(input.inputs[3]);
	auto ttm = "__finance_source." + SqlColumn(input.inputs[4]);
	auto rate = "__finance_source." + SqlColumn(input.inputs[5]);
	auto vol = "__finance_source." + SqlColumn(input.inputs[6]);
	auto q = input.inputs.size() == 8 ? "__finance_source." + SqlColumn(input.inputs[7]) : "0.0";
	auto args = BSMArguments(kind, spot, strike, ttm, rate, vol, q);
	auto query = StringUtil::Format(
	    "WITH priced AS (SELECT struct_pack(*COLUMNS(__finance_source.*)) AS __finance_source, "
	    "fin_bsm_all(%s) AS bsm FROM %s AS __finance_source) "
	    "SELECT __finance_source.*, "
	    "bsm.price AS model_price, "
	    "bsm.delta AS model_delta, "
	    "bsm.gamma AS model_gamma, "
	    "bsm.vega AS model_vega, "
	    "bsm.theta AS model_theta, "
	    "bsm.rho AS model_rho, "
	    "fin_bsm_implied_vol(%s, bsm.price, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, "
	    "%s::DOUBLE) AS model_implied_volatility "
	    "FROM priced",
	    args, table, kind, spot, strike, ttm, rate, q, vol);
	return ParseSubquery(context, query);
}
