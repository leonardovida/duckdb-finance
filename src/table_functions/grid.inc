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
