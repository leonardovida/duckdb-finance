struct IVRangeState {
	bool isset;
	bool invalid;
	double min_iv;
	double max_iv;
	double last_iv;
	idx_t count;
};

static bool IsValidIVObservation(double value) {
	return std::isfinite(value) && value >= 0.0;
}

struct IVRangeOperation : public UnaryDoubleUpdateOperation<IVRangeOperation> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.invalid = false;
		state.min_iv = 0.0;
		state.max_iv = 0.0;
		state.last_iv = 0.0;
		state.count = 0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (!IsValidIVObservation(value)) {
			// Negative or non-finite IV makes the group's rank undefined.
			state.invalid = true;
			return;
		}
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
		target.invalid = target.invalid || source.invalid;
		if (!source.isset) {
			return;
		}
		if (!target.isset) {
			auto invalid = target.invalid;
			target = source;
			target.invalid = invalid;
			return;
		}
		target.min_iv = std::min(target.min_iv, source.min_iv);
		target.max_iv = std::max(target.max_iv, source.max_iv);
		target.last_iv = source.last_iv;
		target.count += source.count;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || !state.isset || state.count == 0 || state.max_iv == state.min_iv) {
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

// IV percentile: fraction of the prior observations strictly below the latest
// observation. The history is kept for the exact count; window frames are
// rebuilt into one reusable local state.
struct IVPercentileState {
	vector<double> *values;
	FinWindowAux *window;
	bool invalid;
};

struct IVPercentileOperation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 1;
	static constexpr bool ORDER_DEPENDENT = true;
	static constexpr bool WINDOW_INCREMENTAL = true;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<double>();
		state.window = nullptr;
		state.invalid = false;
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		state.values->clear();
		state.invalid = false;
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t) {
		if (!IsValidIVObservation(row.v[0])) {
			state.invalid = true;
			return;
		}
		state.values->push_back(row.v[0]);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.invalid = target.invalid || source.invalid;
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.values->size() < 2) {
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
		delete state.window;
		state.window = nullptr;
	}
};
