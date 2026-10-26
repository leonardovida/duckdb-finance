template <class OPERATION>
struct UnaryDoubleUpdateOperation {
	template <class INPUT_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &, idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			OPERATION::UpdateValue(state, static_cast<double>(input));
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &) {
		OPERATION::UpdateValue(state, static_cast<double>(input));
	}
};

typedef void (*fin_simple_update_t)(Vector inputs[], AggregateInputData &aggr_input_data, idx_t input_count,
                                    data_ptr_t state, idx_t count);

//! DuckDB 2.0 replaced the ungrouped "simple update" with a clustered update: the input rows come in runs that each
//! update one state. A single run over every row (ungrouped aggregation) takes the simple update path; anything else
//! is scattered through the regular update.
template <fin_simple_update_t SIMPLE, aggregate_update_t SCATTER>
static void FinClusterUpdate(Vector inputs[], AggregateInputData &aggr_input_data, idx_t input_count,
                             const ClusteredAggr &clustered, idx_t count) {
	auto runs = clustered.runs();
	if (runs.size() == 1 && !runs[0].sel && runs[0].count == count) {
		SIMPLE(inputs, aggr_input_data, input_count, runs[0].state, count);
		return;
	}
	Vector states(LogicalType::POINTER, count);
	auto state_data = FlatVector::GetDataMutable<data_ptr_t>(states);
	for (auto &run : runs) {
		for (idx_t i = 0; i < run.count; i++) {
			state_data[run.sel ? run.sel[i] : i] = run.state;
		}
	}
	FlatVector::SetSize(states, count);
	SCATTER(inputs, aggr_input_data, input_count, states, count);
}
