struct RSIState {
	bool isset;
	vector<double> *values;
	int32_t period;
};

struct RSIOperation : public UnaryDoubleUpdateOperation<RSIOperation> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.values = new vector<double>();
		state.period = 14;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (!std::isfinite(value)) {
			throw InvalidInputException("RSI prices must be finite");
		}
		state.isset = true;
		state.values->push_back(value);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset) {
			return;
		}
		if (target.isset && target.period != source.period) {
			throw InvalidInputException("RSI period must be constant within a group");
		}
		target.period = source.period;
		target.isset = true;
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.values->size() < 2) {
			finalize_data.ReturnNull();
			return;
		}
		auto changes = state.values->size() - 1;
		auto initial_count = std::min<idx_t>(NumericCast<idx_t>(state.period), changes);
		double avg_gain = 0.0;
		double avg_loss = 0.0;
		for (idx_t i = 1; i <= initial_count; i++) {
			auto diff = (*state.values)[i] - (*state.values)[i - 1];
			avg_gain += std::max(diff, 0.0);
			avg_loss += std::max(-diff, 0.0);
		}
		avg_gain /= static_cast<double>(initial_count);
		avg_loss /= static_cast<double>(initial_count);
		for (idx_t i = initial_count + 1; i <= changes; i++) {
			auto diff = (*state.values)[i] - (*state.values)[i - 1];
			avg_gain = (avg_gain * (state.period - 1) + std::max(diff, 0.0)) / state.period;
			avg_loss = (avg_loss * (state.period - 1) + std::max(-diff, 0.0)) / state.period;
		}
		if (avg_loss == 0.0) {
			target = 100.0;
			return;
		}
		auto rs = avg_gain / avg_loss;
		target = 100.0 - 100.0 / (1.0 + rs);
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.values;
		state.values = nullptr;
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
		if (state.isset && state.period != period) {
			throw InvalidInputException("RSI period must be constant within a group");
		}
		state.period = period;
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
