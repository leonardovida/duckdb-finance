struct RSIState {
	bool isset;
	vector<double> *prefix;
	int32_t period;
	idx_t count;
	double last;
	double gain;
	double loss;
	double tail_gain;
	double tail_loss;
	double tail_decay;
};

struct RSIOperation : public UnaryDoubleUpdateOperation<RSIOperation> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.prefix = new vector<double>();
		state.period = 14;
		state.count = 0;
		state.last = 0.0;
		state.gain = 0.0;
		state.loss = 0.0;
		state.tail_gain = 0.0;
		state.tail_loss = 0.0;
		state.tail_decay = 1.0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (!std::isfinite(value)) {
			throw InvalidInputException("RSI prices must be finite");
		}
		if (state.prefix->size() <= idx_t(state.period)) {
			state.prefix->push_back(value);
		}
		if (state.isset) {
			auto diff = value - state.last;
			auto gain = std::max(diff, 0.0);
			auto loss = std::max(-diff, 0.0);
			if (state.count <= idx_t(state.period)) {
				state.gain += gain;
				state.loss += loss;
				if (state.count == idx_t(state.period)) {
					state.gain /= state.period;
					state.loss /= state.period;
				}
			} else {
				auto decay = double(state.period - 1) / state.period;
				state.tail_gain = (state.tail_gain * (state.period - 1) + gain) / state.period;
				state.tail_loss = (state.tail_loss * (state.period - 1) + loss) / state.period;
				state.tail_decay *= decay;
			}
		}
		state.last = value;
		state.count++;
		state.isset = true;
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset) {
			return;
		}
		if (target.isset && target.period != source.period) {
			throw InvalidInputException("RSI period must be constant within a group");
		}
		if (!target.isset) {
			auto prefix = target.prefix;
			target = source;
			target.prefix = prefix;
			*target.prefix = *source.prefix;
			return;
		}
		// Retain only the seed prices. Later changes are an affine Wilder
		// recurrence, so an arbitrarily long tail merges in constant time.
		for (auto value : *source.prefix) {
			UpdateValue(target, value);
		}
		auto tail_count = source.count - source.prefix->size();
		if (tail_count > 0) {
			target.tail_gain = source.tail_gain + source.tail_decay * target.tail_gain;
			target.tail_loss = source.tail_loss + source.tail_decay * target.tail_loss;
			target.tail_decay *= source.tail_decay;
			target.count += tail_count;
			target.last = source.last;
		}
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count < 2) {
			finalize_data.ReturnNull();
			return;
		}
		double avg_gain = state.gain;
		double avg_loss = state.loss;
		if (state.count - 1 < idx_t(state.period)) {
			avg_gain /= double(state.count - 1);
			avg_loss /= double(state.count - 1);
		} else {
			avg_gain = state.tail_gain + state.tail_decay * avg_gain;
			avg_loss = state.tail_loss + state.tail_decay * avg_loss;
		}
		if (!std::isfinite(avg_gain) || !std::isfinite(avg_loss)) {
			finalize_data.ReturnNull();
			return;
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
		delete state.prefix;
		state.prefix = nullptr;
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
