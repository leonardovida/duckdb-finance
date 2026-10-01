struct IVRangeState {
	bool isset;
	double min_iv;
	double max_iv;
	double last_iv;
	idx_t count;
};

static void ValidateIVObservation(double value) {
	if (!std::isfinite(value) || value < 0.0) {
		throw InvalidInputException("IV observations must be non-negative and finite");
	}
}

struct IVRangeOperation : public UnaryDoubleUpdateOperation<IVRangeOperation> {
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
		ValidateIVObservation(value);
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
		target = rank;
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct IVPercentileState {
	vector<double> *values;
};

struct IVPercentileOperation : public UnaryDoubleUpdateOperation<IVPercentileOperation> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<double>();
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		ValidateIVObservation(value);
		state.values->push_back(value);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.values->size() < 2) {
			finalize_data.ReturnNull();
			return;
		}
		auto current = state.values->back();
		auto below = std::count_if(state.values->begin(), state.values->end() - 1,
		                           [current](double value) { return value < current; });
		target = static_cast<double>(below) / static_cast<double>(state.values->size() - 1);
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
