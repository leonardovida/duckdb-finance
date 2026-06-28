struct RSIState {
	bool isset;
	double first;
	double last;
	double gain_sum;
	double loss_sum;
	idx_t changes;
};

struct RSIOperation : public UnaryDoubleUpdateOperation<RSIOperation> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.first = 0.0;
		state.last = 0.0;
		state.gain_sum = 0.0;
		state.loss_sum = 0.0;
		state.changes = 0;
	}

	static void AddDiff(RSIState &state, double diff) {
		if (diff > 0.0) {
			state.gain_sum += diff;
		} else {
			state.loss_sum -= diff;
		}
		state.changes++;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (!state.isset) {
			state.isset = true;
			state.first = value;
			state.last = value;
			return;
		}
		AddDiff(state, value - state.last);
		state.last = value;
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
		AddDiff(target, source.first - target.last);
		target.gain_sum += source.gain_sum;
		target.loss_sum += source.loss_sum;
		target.changes += source.changes;
		target.last = source.last;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.changes == 0) {
			finalize_data.ReturnNull();
			return;
		}
		if (state.loss_sum == 0.0) {
			target = 100.0;
			return;
		}
		auto avg_gain = state.gain_sum / static_cast<double>(state.changes);
		auto avg_loss = state.loss_sum / static_cast<double>(state.changes);
		auto rs = avg_gain / avg_loss;
		target = 100.0 - 100.0 / (1.0 + rs);
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct RSIWithPeriodOperation : public RSIOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, int32_t period) {
		if (period <= 0) {
			throw InvalidInputException("RSI period must be positive");
		}
		RSIOperation::UpdateValue(state, value);
	}

	template <class INPUT_TYPE, class PERIOD_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, const PERIOD_TYPE &period, AggregateBinaryInput &,
	                              idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input), static_cast<int32_t>(period));
		}
	}

	template <class INPUT_TYPE, class PERIOD_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const PERIOD_TYPE &period, AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(input), static_cast<int32_t>(period));
	}
};
