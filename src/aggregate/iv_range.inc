struct IVRangeState {
	bool isset;
	double min_iv;
	double max_iv;
	double last_iv;
	idx_t count;
};

template <bool PERCENTILE>
struct IVRangeOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.min_iv = 0.0;
		state.max_iv = 0.0;
		state.last_iv = 0.0;
		state.count = 0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (!state.isset) {
			state.isset = true;
			state.min_iv = value;
			state.max_iv = value;
		}
		state.min_iv = std::min(state.min_iv, value);
		state.max_iv = std::max(state.max_iv, value);
		state.last_iv = value;
		state.count++;
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &, idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input));
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &) {
		UpdateValue(state, static_cast<double>(input));
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset) {
			return;
		}
		if (!target.isset) {
			target = source;
			return;
		}
		target.min_iv = std::min(target.min_iv, source.min_iv);
		target.max_iv = std::max(target.max_iv, source.max_iv);
		target.last_iv = source.last_iv;
		target.count += source.count;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0 || state.max_iv == state.min_iv) {
			finalize_data.ReturnNull();
			return;
		}
		auto rank = (state.last_iv - state.min_iv) / (state.max_iv - state.min_iv);
		target = PERCENTILE ? std::min(1.0, std::max(0.0, rank)) : rank;
	}

	static bool IgnoreNull() {
		return true;
	}
};
