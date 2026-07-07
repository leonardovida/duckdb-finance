static void ValidatePositiveBarThreshold(const Value &value, const string &function_name) {
	if (value.IsNull()) {
		throw BinderException("%s threshold cannot be NULL", function_name);
	}
	Value threshold_value;
	string error;
	if (!value.DefaultTryCastAs(LogicalType::DOUBLE, threshold_value, &error)) {
		throw BinderException("%s threshold must be numeric: %s", function_name, error);
	}
	auto threshold = threshold_value.GetValue<double>();
	if (!(threshold > 0.0) || !std::isfinite(threshold)) {
		throw BinderException("%s threshold must be positive and finite", function_name);
	}
}

static unique_ptr<TableRef> BarsBindReplace(ClientContext &context, TableFunctionBindInput &input, const string &kind) {
	RequireInputCountAtLeast(input, kind == "tick" ? 3 : 4,
	                         "Finance bar functions expect table_name, ts_col, price_col[, volume_col, threshold]");
	auto table = SqlTableName(input.inputs[0]);
	auto ts = SqlColumn(input.inputs[1]);
	auto price = SqlColumn(input.inputs[2]);
	string volume = "1.0";
	string threshold = "100";
	if (kind == "tick") {
		if (input.inputs.size() >= 4) {
			ValidatePositiveBarThreshold(input.inputs[3], "fin_tick_bars");
			threshold = SqlLiteral(input.inputs[3]);
		}
	} else if (kind == "imbalance") {
		volume = SqlColumn(input.inputs[3]);
	} else {
		volume = input.inputs.size() >= 4 ? SqlColumn(input.inputs[3]) : "1.0";
		if (input.inputs.size() >= 5) {
			ValidatePositiveBarThreshold(input.inputs[4], kind == "volume" ? "fin_volume_bars" : "fin_dollar_bars");
			threshold = SqlLiteral(input.inputs[4]);
		}
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
