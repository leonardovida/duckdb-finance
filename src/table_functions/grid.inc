// Regular timestamp grids (Prometheus-style instant sampling).
//
// The grid is generated from range(n), where n is computed at bind time, so the
// planner sees an exact cardinality and uses the sort-merge ASOF join instead of
// a nested loop. Grid points are anchored at start_ts: start_ts + i * step.

static constexpr idx_t FINANCE_MAX_GRID_POINTS = 10000000;

static interval_t MultiplyGridInterval(const interval_t &step, int64_t factor, const string &function_name) {
	interval_t result;
	int64_t months;
	int64_t days;
	if (!TryMultiplyOperator::Operation<int64_t, int64_t, int64_t>(step.months, factor, months) ||
	    !TryMultiplyOperator::Operation<int64_t, int64_t, int64_t>(step.days, factor, days) ||
	    !TryMultiplyOperator::Operation<int64_t, int64_t, int64_t>(step.micros, factor, result.micros) ||
	    months > NumericLimits<int32_t>::Maximum() || months < NumericLimits<int32_t>::Minimum() ||
	    days > NumericLimits<int32_t>::Maximum() || days < NumericLimits<int32_t>::Minimum()) {
		throw InvalidInputException("%s: grid is too large for the requested step", function_name);
	}
	result.months = static_cast<int32_t>(months);
	result.days = static_cast<int32_t>(days);
	return result;
}

struct GridSpec {
	string start;
	string step;
	idx_t points;
};

static GridSpec GridSpecFromInputs(const TableFunctionBindInput &input, const string &function_name) {
	auto start_value = RequireArgument(input, 3, function_name, "start_ts").DefaultCastAs(LogicalType::TIMESTAMP);
	auto end_value = RequireArgument(input, 4, function_name, "end_ts").DefaultCastAs(LogicalType::TIMESTAMP);
	auto step_value = RequireArgument(input, 5, function_name, "step").DefaultCastAs(LogicalType::INTERVAL);
	auto start = start_value.GetValue<timestamp_t>();
	auto end = end_value.GetValue<timestamp_t>();
	auto step = step_value.GetValue<interval_t>();
	if (!Timestamp::IsFinite(start) || !Timestamp::IsFinite(end)) {
		throw InvalidInputException("%s: start_ts and end_ts must be finite", function_name);
	}
	if (start > end) {
		throw InvalidInputException("%s: start_ts must not be after end_ts", function_name);
	}
	idx_t points = 0;
	if (step.months == 0) {
		// TIMESTAMP days are exactly 24 hours, so the step has a fixed length.
		hugeint_t step_micros = hugeint_t(step.days) * hugeint_t(Interval::MICROS_PER_DAY) + hugeint_t(step.micros);
		if (step_micros <= hugeint_t(0)) {
			throw InvalidInputException("%s: step must be a positive interval", function_name);
		}
		hugeint_t span = hugeint_t(end.value) - hugeint_t(start.value);
		hugeint_t count = span / step_micros + hugeint_t(1);
		if (count > hugeint_t(static_cast<int64_t>(FINANCE_MAX_GRID_POINTS))) {
			throw InvalidInputException("%s: grid has more than %llu points; use a larger step or a shorter range",
			                            function_name, static_cast<unsigned long long>(FINANCE_MAX_GRID_POINTS));
		}
		points = static_cast<idx_t>(Hugeint::Cast<int64_t>(count));
	} else {
		auto previous = start;
		points = 1;
		while (true) {
			if (points > FINANCE_MAX_GRID_POINTS) {
				throw InvalidInputException("%s: grid has more than %llu points; use a larger step or a shorter range",
				                            function_name, static_cast<unsigned long long>(FINANCE_MAX_GRID_POINTS));
			}
			auto offset = MultiplyGridInterval(step, NumericCast<int64_t>(points), function_name);
			timestamp_t next;
			try {
				next = Interval::Add(start, offset);
			} catch (std::exception &) {
				break;
			}
			if (!(next > previous)) {
				throw InvalidInputException("%s: step must be a positive interval", function_name);
			}
			if (next > end) {
				break;
			}
			previous = next;
			points++;
		}
	}
	return {start_value.ToSQLString(), step_value.ToSQLString(), points};
}

enum class GridKind { LAST, DELTA, RATE, CHANGES, RESETS };

static const char *GridFunctionName(GridKind kind) {
	switch (kind) {
	case GridKind::DELTA:
		return "fin_delta_to_grid";
	case GridKind::RATE:
		return "fin_rate_to_grid";
	case GridKind::CHANGES:
		return "fin_changes_to_grid";
	case GridKind::RESETS:
		return "fin_resets_to_grid";
	default:
		return "fin_resample_grid";
	}
}

struct GridSource {
	string asset;
	string ctes;
	string grid_from;
	string join_condition;
	string partition;
	string asset_select;
	string order_prefix;
};

// Builds the grid CTEs: __finance_grid (grid points, crossed with the assets when
// asset_col is given) and __finance_obs (one deterministic observation per asset
// and timestamp; duplicates keep the row with the largest seq_col, then value).
static GridSource BuildGridSource(const TableFunctionBindInput &input, const string &function_name,
                                  const GridSpec &grid) {
	GridSource result;
	auto table = SqlSourceArg(input, 0, function_name);
	auto ts_col = SqlColumnArg(input, 1, function_name, "ts_col");
	auto value_col = SqlColumnArg(input, 2, function_name, "value_col");
	result.asset = OptionalNamedColumn(input, "asset_col", function_name);
	auto seq = OptionalNamedColumn(input, "seq_col", function_name);
	auto has_asset = !result.asset.empty();
	// Primitive aggregates only: max() without seq_col, an ordered last() with it.
	auto dedupe = seq.empty() ? string("max(__finance_value)")
	                          : string("last(__finance_value ORDER BY __finance_seq, __finance_value)");
	result.ctes = StringUtil::Format(
	    "__finance_grid_points AS ("
	    "  SELECT %s::TIMESTAMP + %s::INTERVAL * __finance_i AS __finance_ts FROM range(%llu) __finance_r(__finance_i)"
	    "), __finance_obs AS ("
	    "  SELECT %s__finance_ts, %s AS __finance_value FROM ("
	    "    SELECT %s%s::TIMESTAMP AS __finance_ts, %s::DOUBLE AS __finance_value%s FROM %s"
	    "    WHERE %s IS NOT NULL AND %s IS NOT NULL"
	    "  ) GROUP BY ALL"
	    ")",
	    grid.start, grid.step, static_cast<unsigned long long>(grid.points), has_asset ? "__finance_asset, " : "",
	    dedupe, has_asset ? result.asset + " AS __finance_asset, " : "", ts_col, value_col,
	    seq.empty() ? "" : ", " + seq + " AS __finance_seq", table, ts_col, value_col);
	if (has_asset) {
		result.ctes += ", __finance_assets AS (SELECT DISTINCT __finance_asset FROM __finance_obs)";
		result.ctes += ", __finance_grid AS (SELECT a.__finance_asset, g.__finance_ts FROM __finance_assets a "
		               "CROSS JOIN __finance_grid_points g)";
		result.join_condition = "g.__finance_asset = o.__finance_asset AND g.__finance_ts >= o.__finance_ts";
		result.partition = "PARTITION BY __finance_asset ";
		result.asset_select = "__finance_asset AS " + result.asset + ", ";
		result.order_prefix = "__finance_asset, ";
	} else {
		result.ctes += ", __finance_grid AS (SELECT __finance_ts FROM __finance_grid_points)";
		result.join_condition = "g.__finance_ts >= o.__finance_ts";
	}
	return result;
}

static string GridSubquery(TableFunctionBindInput &input, GridKind kind) {
	const string function_name = GridFunctionName(kind);
	auto grid = GridSpecFromInputs(input, function_name);
	if (input.inputs.size() >= 7 && !input.inputs[6].IsNull()) {
		auto method = StringUtil::Lower(input.inputs[6].ToString());
		StringUtil::Trim(method);
		if (method != "last") {
			throw InvalidInputException("%s: unknown method '%s' (only 'last' is supported)", function_name, method);
		}
	}
	auto sampled_value = string("o.__finance_value");
	if (input.inputs.size() >= 8 && !input.inputs[7].IsNull()) {
		auto staleness = input.inputs[7].DefaultCastAs(LogicalType::INTERVAL).GetValue<interval_t>();
		if (staleness.months < 0 || staleness.days < 0 || staleness.micros < 0) {
			throw InvalidInputException("%s: staleness must be a non-negative interval", function_name);
		}
		sampled_value = StringUtil::Format("CASE WHEN o.__finance_ts >= g.__finance_ts - %s THEN o.__finance_value END",
		                                   input.inputs[7].DefaultCastAs(LogicalType::INTERVAL).ToSQLString());
	}
	auto source = BuildGridSource(input, function_name, grid);
	auto previous_value = "lag(__finance_value) OVER (" + source.partition + "ORDER BY __finance_ts)";
	auto previous_ts = "lag(__finance_ts) OVER (" + source.partition + "ORDER BY __finance_ts)";
	string value_expr;
	switch (kind) {
	case GridKind::LAST:
		value_expr = "__finance_value";
		break;
	case GridKind::DELTA:
		value_expr = "__finance_value - " + previous_value;
		break;
	case GridKind::RATE:
		value_expr = "(__finance_value - " + previous_value + ") / nullif(epoch(__finance_ts) - epoch(" +
		             previous_ts + "), 0)";
		break;
	case GridKind::CHANGES:
		value_expr = "CASE WHEN __finance_value IS NULL OR " + previous_value + " IS NULL THEN NULL WHEN " +
		             "__finance_value <> " + previous_value + " THEN 1.0 ELSE 0.0 END";
		break;
	case GridKind::RESETS:
		value_expr = "CASE WHEN __finance_value IS NULL OR " + previous_value + " IS NULL THEN NULL WHEN " +
		             "__finance_value < " + previous_value + " THEN 1.0 ELSE 0.0 END";
		break;
	}
	return StringUtil::Format("WITH %s, __finance_sampled AS ("
	                          "  SELECT g.*, %s AS __finance_value FROM __finance_grid g "
	                          "  ASOF LEFT JOIN __finance_obs o ON %s"
	                          ") SELECT %s__finance_ts AS ts, (%s)::DOUBLE AS value FROM __finance_sampled "
	                          "ORDER BY %s__finance_ts",
	                          source.ctes, sampled_value, source.join_condition, source.asset_select, value_expr,
	                          source.order_prefix);
}

static unique_ptr<TableRef> ResampleGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return ParseSubquery(context, GridSubquery(input, GridKind::LAST));
}

static unique_ptr<TableRef> DeltaGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return ParseSubquery(context, GridSubquery(input, GridKind::DELTA));
}

static unique_ptr<TableRef> RateGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return ParseSubquery(context, GridSubquery(input, GridKind::RATE));
}

static unique_ptr<TableRef> ChangesGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return ParseSubquery(context, GridSubquery(input, GridKind::CHANGES));
}

static unique_ptr<TableRef> ResetsGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return ParseSubquery(context, GridSubquery(input, GridKind::RESETS));
}

// Prometheus predict_linear: at every grid point g, fit value = a + b * t by
// least squares over the observations with ts in (g - lookback, g] and predict
// at g + horizon. Fewer than two observations, or no time spread, give NULL.
static unique_ptr<TableRef> PredictLinearGridBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_predict_linear_to_grid";
	auto grid = GridSpecFromInputs(input, function_name);
	auto lookback_value =
	    RequireArgument(input, 6, function_name, "lookback").DefaultCastAs(LogicalType::INTERVAL);
	auto lookback = lookback_value.GetValue<interval_t>();
	if (lookback.months < 0 || lookback.days < 0 || lookback.micros < 0 ||
	    (lookback.months == 0 && lookback.days == 0 && lookback.micros == 0)) {
		throw InvalidInputException("%s: lookback must be a positive interval", function_name);
	}
	double horizon_seconds = 0.0;
	if (input.inputs.size() >= 8) {
		auto horizon =
		    RequireArgument(input, 7, function_name, "horizon").DefaultCastAs(LogicalType::INTERVAL).GetValue<interval_t>();
		horizon_seconds = static_cast<double>(Interval::GetMicro(horizon)) / Interval::MICROS_PER_SEC;
	}
	auto source = BuildGridSource(input, function_name, grid);
	auto asset_join = source.asset.empty() ? string() : string("g.__finance_asset = o.__finance_asset AND ");
	auto group_prefix = source.asset.empty() ? string() : string("g.__finance_asset, ");
	auto query = StringUtil::Format(
	    "WITH %s, __finance_fit AS ("
	    "  SELECT %sg.__finance_ts, "
	    "    regr_slope(o.__finance_value, epoch(o.__finance_ts) - epoch(g.__finance_ts)) AS __finance_slope, "
	    "    regr_intercept(o.__finance_value, epoch(o.__finance_ts) - epoch(g.__finance_ts)) AS __finance_intercept "
	    "  FROM __finance_grid g LEFT JOIN __finance_obs o ON %so.__finance_ts <= g.__finance_ts "
	    "    AND o.__finance_ts > g.__finance_ts - %s "
	    "  GROUP BY ALL"
	    ") SELECT %s__finance_ts AS ts, (__finance_intercept + __finance_slope * %s)::DOUBLE AS value "
	    "FROM __finance_fit ORDER BY %s__finance_ts",
	    source.ctes, group_prefix, asset_join, lookback_value.ToSQLString(), source.asset_select,
	    DoubleLiteral(horizon_seconds), source.order_prefix);
	return ParseSubquery(context, query);
}
