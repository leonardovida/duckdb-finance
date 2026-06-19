static unique_ptr<TableRef> BarsBindReplace(ClientContext &context, TableFunctionBindInput &input, const string &kind) {
	RequireInputCountAtLeast(input, kind == "tick" ? 3 : 4,
	                         "Finance bar functions expect table_name, ts_col, price_col[, volume_col, threshold]");
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
