// Deterministic "value at the first/last ordering key" helpers for SQL macros.
// DuckDB v1.5.6 rewrites first/last(x ORDER BY k1, k2) into arg_min/arg_max over a
// sort-key blob whose unaligned arena allocation misaligns the list segments of other
// ordered aggregates in the same GROUP BY (UBSan). These keep fixed-size primitive state.
// Ties on the key resolve to the larger value for LAST and the smaller value for FIRST,
// so results do not depend on thread count or physical row order.
template <class KEY>
struct ValueAtKeyState {
	KEY key;
	double value;
	bool is_set;
};

template <bool LAST>
struct ValueAtKeyOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.is_set = false;
	}

	template <class KEY>
	static bool Prefer(const KEY &key, double value, const KEY &current_key, double current_value) {
		if (!Equals::Operation(key, current_key)) {
			return LAST ? GreaterThan::Operation(key, current_key) : LessThan::Operation(key, current_key);
		}
		return LAST ? GreaterThan::Operation(value, current_value) : LessThan::Operation(value, current_value);
	}

	template <class STATE, class KEY>
	static void Update(STATE &state, double value, const KEY &key) {
		if (!state.is_set || Prefer(key, value, state.key, state.value)) {
			state.key = key;
			state.value = value;
			state.is_set = true;
		}
	}

	template <class A_TYPE, class B_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const A_TYPE &value, const B_TYPE &key, AggregateBinaryInput &) {
		Update(state, static_cast<double>(value), key);
	}

	template <class A_TYPE, class B_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const A_TYPE &value, const B_TYPE &key, AggregateBinaryInput &,
	                              idx_t) {
		Update(state, static_cast<double>(value), key);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (source.is_set) {
			Update(target, source.value, source.key);
		}
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.is_set) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.value;
	}

	static bool IgnoreNull() {
		return true;
	}
};

template <class KEY, bool LAST>
static AggregateFunction ValueAtKeyAggregate(const string &name, const LogicalType &key_type) {
	auto function = AggregateFunction::BinaryAggregate<ValueAtKeyState<KEY>, double, KEY, double, ValueAtKeyOperation<LAST>>(
	    FinanceLogicalType(LogicalTypeId::DOUBLE), key_type, FinanceLogicalType(LogicalTypeId::DOUBLE));
	function.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	return NamedAggregateFunction(name, std::move(function));
}

template <bool LAST>
static AggregateFunctionSet ValueAtKeySet(const string &name) {
	AggregateFunctionSet set(FinanceFunctionName(name));
	set.AddFunction(ValueAtKeyAggregate<int64_t, LAST>(name, FinanceLogicalType(LogicalTypeId::BIGINT)));
	set.AddFunction(ValueAtKeyAggregate<double, LAST>(name, FinanceLogicalType(LogicalTypeId::DOUBLE)));
	set.AddFunction(ValueAtKeyAggregate<date_t, LAST>(name, FinanceLogicalType(LogicalTypeId::DATE)));
	set.AddFunction(ValueAtKeyAggregate<timestamp_t, LAST>(name, FinanceLogicalType(LogicalTypeId::TIMESTAMP)));
	set.AddFunction(
	    ValueAtKeyAggregate<timestamp_tz_t, LAST>(name, FinanceLogicalType(LogicalTypeId::TIMESTAMP_TZ)));
	return set;
}

static void RegisterValueAtKeyAggregates(ExtensionLoader &loader) {
	loader.RegisterFunction(ValueAtKeySet<true>("finance_last_by_internal"));
	loader.RegisterFunction(ValueAtKeySet<false>("finance_first_by_internal"));
}
