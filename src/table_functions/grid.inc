static string GridSubquery(TableFunctionBindInput &input, const string &value_expr) {
	RequireInputCountAtLeast(input, 6, "fin_resample_grid expects table_name, ts_col, value_col, start_ts, end_ts, step");
	auto table = SqlTableName(input.inputs[0]);
	auto ts_col = SqlColumn(input.inputs[1]);
	auto value_col = SqlColumn(input.inputs[2]);
	auto start_ts = SqlLiteral(input.inputs[3]);
	auto end_ts = SqlLiteral(input.inputs[4]);
	auto step = SqlLiteral(input.inputs[5]);
	if (input.inputs.size() >= 7 && !input.inputs[6].IsNull()) {
		auto method = StringUtil::Lower(input.inputs[6].GetValue<string>());
		if (method != "last") {
			throw BinderException("Finance grid table functions currently support only method 'last'");
		}
	}
	auto sampled_value = string("s.value");
	if (input.inputs.size() >= 8 && !input.inputs[7].IsNull()) {
		auto staleness = SqlLiteral(input.inputs[7]);
		sampled_value = StringUtil::Format("CASE WHEN s.ts IS NOT NULL AND s.ts >= g.ts - (%s)::INTERVAL THEN s.value ELSE NULL END",
		                                   staleness);
	}
	return StringUtil::Format(
	    "WITH grid AS ("
	    "  SELECT generate_series AS ts FROM generate_series(%s::TIMESTAMP, %s::TIMESTAMP, %s::INTERVAL)"
	    "), source AS ("
	    "  SELECT %s::TIMESTAMP AS ts, %s::DOUBLE AS value FROM %s WHERE %s IS NOT NULL"
	    "), sampled AS ("
	    "  SELECT g.ts, %s AS value FROM grid g ASOF LEFT JOIN source s ON g.ts >= s.ts"
	    ") SELECT ts, %s AS value FROM sampled ORDER BY ts",
	    start_ts, end_ts, step, ts_col, value_col, table, ts_col, sampled_value, value_expr);
}

static unique_ptr<TableRef> ResampleGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
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
