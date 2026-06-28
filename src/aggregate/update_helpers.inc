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
