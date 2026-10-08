static string BSMArguments(const string &kind, const string &spot, const string &strike, const string &ttm,
                           const string &rate, const string &vol, const string &dividend_yield) {
	return StringUtil::Format("%s, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE", kind, spot,
	                          strike, ttm, rate, vol, dividend_yield);
}

static unique_ptr<TableRef> OptionChainBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	RequireInputCountBetween(input, 7, 8,
	                         "fin_option_chain expects table_name, kind_col, spot_col, strike_col, ttm_col, rate_col, "
	                         "vol_col[, dividend_yield_col]");
	auto table = SqlSourceArg(input, 0, "fin_option_chain");
	auto kind = "__finance_source." + SqlColumnArg(input, 1, "fin_option_chain", "kind_col");
	auto spot = "__finance_source." + SqlColumnArg(input, 2, "fin_option_chain", "spot_col");
	auto strike = "__finance_source." + SqlColumnArg(input, 3, "fin_option_chain", "strike_col");
	auto ttm = "__finance_source." + SqlColumnArg(input, 4, "fin_option_chain", "ttm_col");
	auto rate = "__finance_source." + SqlColumnArg(input, 5, "fin_option_chain", "rate_col");
	auto vol = "__finance_source." + SqlColumnArg(input, 6, "fin_option_chain", "vol_col");
	auto q = input.inputs.size() == 8 ? "__finance_source." + SqlColumnArg(input, 7, "fin_option_chain", "dividend_yield_col") : "0.0";
	auto args = BSMArguments(kind, spot, strike, ttm, rate, vol, q);
	auto input_column = [&](idx_t column) {
		return SqlIdentifier("__finance_source_" + input.inputs[column].GetValue<string>());
	};
	auto model_q = input.inputs.size() == 8 ? input_column(7) : "0.0";
	// Keep source fields flat and separate from helpers. Only old model
	// outputs are removed after their inputs have been used for repricing.
	auto query = StringUtil::Format(
	    "SELECT COLUMNS('(?s)^__finance_source_(.*)$') AS \"\\1\", "
	    "bsm.price AS model_price, "
	    "bsm.delta AS model_delta, "
	    "bsm.gamma AS model_gamma, "
	    "bsm.vega AS model_vega, "
	    "bsm.theta AS model_theta, "
	    "bsm.rho AS model_rho, "
	    "__finance_iv AS model_implied_volatility "
	    "FROM (SELECT COLUMNS(lambda c: NOT regexp_matches(c, "
	    "'(?i)^__finance_source_model_(price|delta|gamma|vega|theta|rho|implied_volatility)$')) "
	    "FROM (SELECT *, fin_bsm_implied_vol(%s, bsm.price, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, %s::DOUBLE, "
	    "%s::DOUBLE, %s::DOUBLE) AS __finance_iv "
	    "FROM (SELECT COLUMNS(__finance_source.*) AS \"__finance_source_\\0\", "
	    "fin_bsm_all(%s) AS bsm FROM %s AS __finance_source) AS priced) AS calculated) AS filtered",
	    input_column(1), input_column(2), input_column(3), input_column(4), input_column(5), model_q, input_column(6),
	    args, table);
	return ParseSubquery(context, query);
}
