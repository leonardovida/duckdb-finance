// Information-driven bars (Lopez de Prado, Advances in Financial Machine Learning, ch. 2.3).
//
// Bars use the AFML reset-accumulator convention: rows are visited in
// (asset, ts, seq, price, volume) order, the bar metric is accumulated, and the bar
// closes on the first row whose running total reaches the threshold. The overshoot
// does not spill into the next bar; the accumulator restarts at zero.
//
// The bar index is computed by an internal window aggregate. DuckDB sorts each
// partition once, hands the whole sorted hash group to window_init, and the
// per-row window callback reads the precomputed index. The partition key is an
// explicit argument because a hash group may hold several partitions.

enum class BarKind : int32_t { TICK = 0, VOLUME = 1, DOLLAR = 2, IMBALANCE_SIGNED = 3, IMBALANCE_TICK_RULE = 4 };

struct BarRow {
	int64_t bar;
	double volume;
	double notional;
	double metric;
	bool has_volume;
};

// Neumaier-compensated running sum.
struct CompensatedSum {
	double sum = 0.0;
	double compensation = 0.0;

	void Add(double value) {
		auto next = sum + value;
		if (std::fabs(sum) >= std::fabs(value)) {
			compensation += (sum - next) + value;
		} else {
			compensation += (value - next) + sum;
		}
		sum = next;
	}

	double Total() const {
		return sum + compensation;
	}

	void Reset() {
		sum = 0.0;
		compensation = 0.0;
	}
};

struct BarIndexState {
	vector<BarRow> *bars;
};

struct BarIndexOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.bars = nullptr;
	}

	template <class STATE, class OP>
	static void Combine(const STATE &, STATE &, AggregateInputData &) {
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.bars;
		state.bars = nullptr;
	}

	static bool IgnoreNull() {
		return false;
	}
};

static void BarIndexUpdate(Vector[], AggregateInputData &, idx_t, Vector &, idx_t) {
	throw InvalidInputException("__finance_bar_index can only be used as a window function");
}

static void BarIndexFinalize(Vector &, AggregateInputData &, Vector &, idx_t, idx_t) {
	throw InvalidInputException("__finance_bar_index can only be used as a window function");
}

static const char *BarFunctionName(BarKind kind) {
	switch (kind) {
	case BarKind::TICK:
		return "fin_tick_bars";
	case BarKind::VOLUME:
		return "fin_volume_bars";
	case BarKind::DOLLAR:
		return "fin_dollar_bars";
	default:
		return "fin_imbalance_bars";
	}
}

static void BarIndexWindowInit(AggregateInputData &, const WindowPartitionInput &partition, data_ptr_t g_state) {
	auto &state = *reinterpret_cast<BarIndexState *>(g_state);
	if (!state.bars) {
		state.bars = new vector<BarRow>();
	}
	auto &bars = *state.bars;
	bars.resize(partition.count);
	if (partition.count == 0) {
		return;
	}

	ColumnDataScanState scan_state;
	DataChunk chunk;
	partition.inputs->InitializeScan(scan_state, partition.column_ids);
	partition.inputs->InitializeScanChunk(scan_state, chunk);

	bool have_key = false;
	bool previous_key_null = false;
	string previous_key;
	int64_t bar = 0;
	CompensatedSum metric_sum;
	CompensatedSum volume_sum;
	CompensatedSum notional_sum;
	bool bar_has_volume = false;
	double sign = 0.0;
	bool have_price = false;
	double previous_price = 0.0;
	idx_t row = 0;

	while (partition.inputs->Scan(scan_state, chunk)) {
		UnifiedVectorFormat kind_format, key_format, price_format, volume_format, threshold_format;
		FinanceToUnifiedFormat(chunk.data[0], chunk.size(), kind_format);
		FinanceToUnifiedFormat(chunk.data[1], chunk.size(), key_format);
		FinanceToUnifiedFormat(chunk.data[2], chunk.size(), price_format);
		FinanceToUnifiedFormat(chunk.data[3], chunk.size(), volume_format);
		FinanceToUnifiedFormat(chunk.data[4], chunk.size(), threshold_format);
		auto kinds = UnifiedVectorFormat::GetData<int32_t>(kind_format);
		auto keys = UnifiedVectorFormat::GetData<string_t>(key_format);
		auto prices = UnifiedVectorFormat::GetData<double>(price_format);
		auto volumes = UnifiedVectorFormat::GetData<double>(volume_format);
		auto thresholds = UnifiedVectorFormat::GetData<double>(threshold_format);

		for (idx_t i = 0; i < chunk.size(); i++, row++) {
			auto kind_idx = kind_format.sel->get_index(i);
			auto key_idx = key_format.sel->get_index(i);
			auto price_idx = price_format.sel->get_index(i);
			auto volume_idx = volume_format.sel->get_index(i);
			auto threshold_idx = threshold_format.sel->get_index(i);
			auto kind = static_cast<BarKind>(kinds[kind_idx]);

			// Detect partition boundaries.
			auto key_null = !key_format.validity.RowIsValid(key_idx);
			bool new_partition = !have_key;
			if (have_key) {
				if (key_null != previous_key_null) {
					new_partition = true;
				} else if (!key_null) {
					auto &key = keys[key_idx];
					new_partition = key.GetSize() != previous_key.size() ||
					                memcmp(key.GetData(), previous_key.data(), previous_key.size()) != 0;
				}
			}
			if (new_partition) {
				have_key = true;
				previous_key_null = key_null;
				if (!key_null) {
					previous_key = keys[key_idx].GetString();
				}
				bar = 0;
				metric_sum.Reset();
				volume_sum.Reset();
				notional_sum.Reset();
				bar_has_volume = false;
				sign = 0.0;
				have_price = false;
			}

			auto threshold = thresholds[threshold_idx];
			auto price_valid = price_format.validity.RowIsValid(price_idx);
			auto price = price_valid ? prices[price_idx] : 0.0;
			auto volume_valid = volume_format.validity.RowIsValid(volume_idx);
			auto volume = volume_valid ? volumes[volume_idx] : 0.0;
			if (!price_valid || !std::isfinite(price)) {
				throw InvalidInputException("%s: price must be finite", BarFunctionName(kind));
			}

			double metric = 1.0;
			switch (kind) {
			case BarKind::TICK:
				if (volume_valid && (!std::isfinite(volume) || volume < 0.0)) {
					throw InvalidInputException("%s: volume must be finite and non-negative", BarFunctionName(kind));
				}
				break;
			case BarKind::VOLUME:
			case BarKind::DOLLAR:
			case BarKind::IMBALANCE_TICK_RULE:
				if (!volume_valid || !std::isfinite(volume) || volume < 0.0) {
					throw InvalidInputException("%s: volume must be finite and non-negative", BarFunctionName(kind));
				}
				if (kind == BarKind::VOLUME) {
					metric = volume;
				} else if (kind == BarKind::DOLLAR) {
					metric = std::fabs(price) * volume;
				} else {
					// Tick rule: the sign of the last non-zero price change.
					if (have_price && price != previous_price) {
						sign = price > previous_price ? 1.0 : -1.0;
					}
					metric = sign * volume;
				}
				break;
			case BarKind::IMBALANCE_SIGNED:
				if (!volume_valid || !std::isfinite(volume)) {
					throw InvalidInputException("%s: signed volume must be finite", BarFunctionName(kind));
				}
				metric = volume;
				break;
			default:
				throw InternalException("Unknown finance bar kind");
			}
			have_price = true;
			previous_price = price;

			// Running totals within the open bar; the last row of a bar carries the bar totals.
			metric_sum.Add(metric);
			if (volume_valid) {
				auto traded = kind == BarKind::IMBALANCE_SIGNED ? std::fabs(volume) : volume;
				volume_sum.Add(traded);
				notional_sum.Add(price * traded);
				bar_has_volume = true;
			}
			auto total = metric_sum.Total();
			bars[row] = {bar, volume_sum.Total(), notional_sum.Total(), total, bar_has_volume};
			auto reached = kind == BarKind::IMBALANCE_SIGNED || kind == BarKind::IMBALANCE_TICK_RULE
			                   ? std::fabs(total) >= threshold * (1.0 - 1e-12)
			                   : total >= threshold * (1.0 - 1e-12);
			if (reached) {
				bar++;
				metric_sum.Reset();
				volume_sum.Reset();
				notional_sum.Reset();
				bar_has_volume = false;
			}
		}
	}
}

static void BarIndexWindow(AggregateInputData &, const WindowPartitionInput &, const_data_ptr_t g_state, data_ptr_t,
                           const SubFrames &frames, Vector &result, idx_t rid) {
	auto &state = *reinterpret_cast<const BarIndexState *>(g_state);
	auto row = frames[0].start;
	if (!state.bars || row >= state.bars->size()) {
		throw InternalException("__finance_bar_index window state is not initialized");
	}
	auto &entry = (*state.bars)[row];
	auto &children = StructVector::GetEntries(result);
	FlatVector::GetData<int64_t>(*children[0])[rid] = entry.bar;
	FlatVector::GetData<double>(*children[1])[rid] = entry.volume;
	FlatVector::GetData<double>(*children[2])[rid] = entry.notional;
	FlatVector::GetData<double>(*children[3])[rid] = entry.metric;
	if (!entry.has_volume) {
		FlatVector::SetNull(*children[1], rid, true);
		FlatVector::SetNull(*children[2], rid, true);
	}
}

static LogicalType BarIndexReturnType() {
	child_list_t<LogicalType> children;
	children.emplace_back("bar_id", FinanceLogicalType(LogicalTypeId::BIGINT));
	children.emplace_back("volume", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("notional", FinanceLogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("metric", FinanceLogicalType(LogicalTypeId::DOUBLE));
	return LogicalType::STRUCT(std::move(children));
}

static AggregateFunction BarIndexAggregate() {
	AggregateFunction function(
	    "__finance_bar_index",
	    {FinanceLogicalType(LogicalTypeId::INTEGER), FinanceLogicalType(LogicalTypeId::VARCHAR),
	     FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	     FinanceLogicalType(LogicalTypeId::DOUBLE)},
	    BarIndexReturnType(), AggregateFunction::StateSize<BarIndexState>,
	    AggregateFunction::StateInitialize<BarIndexState, BarIndexOperation>, BarIndexUpdate,
	    AggregateFunction::StateCombine<BarIndexState, BarIndexOperation>, BarIndexFinalize,
	    FunctionNullHandling::SPECIAL_HANDLING);
	function.SetStateDestructorCallback(AggregateFunction::StateDestroy<BarIndexState, BarIndexOperation>);
	function.SetWindowInitCallback(BarIndexWindowInit);
	function.SetWindowCallback(BarIndexWindow);
	function.SetOrderDependent(AggregateOrderDependent::ORDER_DEPENDENT);
	return function;
}

static unique_ptr<TableRef> BarsBindReplace(ClientContext &context, TableFunctionBindInput &input, BarKind kind) {
	const string function_name = BarFunctionName(kind);
	auto table = SqlSourceArg(input, 0, function_name);
	auto ts = SqlColumnArg(input, 1, function_name, "ts_col");
	auto price = SqlColumnArg(input, 2, function_name, "price_col");
	string volume;
	double threshold = 100.0;
	auto method = string("signed");
	if (kind == BarKind::TICK) {
		if (input.inputs.size() >= 4) {
			threshold = RequireFiniteDouble(input.inputs[3], function_name, "threshold");
		}
		auto volume_col = OptionalNamedColumn(input, "volume_col", function_name);
		volume = volume_col;
	} else {
		volume = SqlColumnArg(input, 3, function_name, "volume_col");
		threshold = RequireFiniteDouble(RequireArgument(input, 4, function_name, "threshold"), function_name,
		                                "threshold");
		if (kind == BarKind::IMBALANCE_SIGNED && input.inputs.size() >= 6) {
			method = StringUtil::Lower(RequireString(input.inputs[5], function_name, "method"));
			StringUtil::Trim(method);
			if (method == "tick_rule") {
				kind = BarKind::IMBALANCE_TICK_RULE;
			} else if (method != "signed") {
				throw InvalidInputException("%s: unknown method '%s' (expected 'signed' or 'tick_rule')",
				                            function_name, method);
			}
		}
	}
	if (!(threshold > 0.0)) {
		throw InvalidInputException("%s: threshold must be positive and finite", function_name);
	}
	auto asset = OptionalNamedColumn(input, "asset_col", function_name);
	auto seq = OptionalNamedColumn(input, "seq_col", function_name);

	string source_columns;
	if (!asset.empty()) {
		source_columns += asset + " AS __finance_asset, ";
	}
	source_columns += ts + "::TIMESTAMP AS __finance_ts, " + price + "::DOUBLE AS __finance_price, ";
	source_columns += (volume.empty() ? string("NULL::DOUBLE") : volume + "::DOUBLE") + " AS __finance_volume";
	if (!seq.empty()) {
		source_columns += ", " + seq + " AS __finance_seq";
	}
	auto filter = ts + " IS NOT NULL AND " + price + " IS NOT NULL";
	if (!volume.empty() && kind != BarKind::TICK) {
		filter += " AND " + volume + " IS NOT NULL";
	}
	auto partition = asset.empty() ? string() : string("PARTITION BY __finance_asset ");
	auto order = string("ORDER BY __finance_ts") + (seq.empty() ? "" : ", __finance_seq") +
	             ", __finance_price, __finance_volume";
	auto key = asset.empty() ? string("NULL::VARCHAR") : string("__finance_asset::VARCHAR");
	auto asset_output = asset.empty() ? string() : string("__finance_asset AS ") + asset + ", ";
	auto group_prefix = asset.empty() ? string() : string("__finance_asset, ");
	auto imbalance_output = kind == BarKind::IMBALANCE_SIGNED || kind == BarKind::IMBALANCE_TICK_RULE
	                            ? string(", arg_max(__finance_state.metric, __finance_rn) AS imbalance")
	                            : string();
	auto query = StringUtil::Format(
	    "WITH __finance_bar_source AS (SELECT %s FROM %s WHERE %s), "
	    "__finance_bar_rows AS ("
	    "  SELECT *, __finance_state.bar_id AS __finance_bar FROM ("
	    "    SELECT *, row_number() OVER (%s%s) AS __finance_rn, "
	    "    __finance_bar_index(%d, %s, __finance_price, __finance_volume, %s) "
	    "    OVER (%s%s ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS __finance_state "
	    "    FROM __finance_bar_source)"
	    ") "
	    "SELECT %s__finance_bar AS bar_id, min(__finance_ts) AS start_ts, max(__finance_ts) AS end_ts, "
	    "arg_min(__finance_price, __finance_rn) AS open, max(__finance_price) AS high, "
	    "min(__finance_price) AS low, arg_max(__finance_price, __finance_rn) AS close, "
	    "arg_max(__finance_state.volume, __finance_rn) AS volume, "
	    "arg_max(__finance_state.notional, __finance_rn) / "
	    "nullif(arg_max(__finance_state.volume, __finance_rn), 0) AS vwap, count(*) AS ticks%s "
	    "FROM __finance_bar_rows GROUP BY %s__finance_bar ORDER BY %s__finance_bar",
	    source_columns, table, filter, partition, order, static_cast<int32_t>(kind), key, DoubleLiteral(threshold),
	    partition, order, asset_output, imbalance_output, group_prefix, group_prefix);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> TickBarsBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return BarsBindReplace(context, input, BarKind::TICK);
}

static unique_ptr<TableRef> VolumeBarsBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return BarsBindReplace(context, input, BarKind::VOLUME);
}

static unique_ptr<TableRef> DollarBarsBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return BarsBindReplace(context, input, BarKind::DOLLAR);
}

static unique_ptr<TableRef> ImbalanceBarsBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return BarsBindReplace(context, input, BarKind::IMBALANCE_SIGNED);
}
