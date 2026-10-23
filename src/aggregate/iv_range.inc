struct IVRangeState {
	bool isset;
	bool invalid;
	double min_iv;
	double max_iv;
	double last_iv;
	idx_t count;
	FinWindowAux *window;
};

static bool IsValidIVObservation(double value) {
	return std::isfinite(value) && value >= 0.0;
}

// IV rank: (last - min) / (max - min) over the ordered observations. The last
// observation depends on the ordering, so the aggregate is order-dependent.
struct IVRangeOperation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 1;
	static constexpr bool ORDER_DEPENDENT = true;
	static constexpr bool WINDOW_INCREMENTAL = true;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.window = nullptr;
		WindowReset(state);
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		state.isset = false;
		state.invalid = false;
		state.min_iv = 0.0;
		state.max_iv = 0.0;
		state.last_iv = 0.0;
		state.count = 0;
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t) {
		auto value = row.v[0];
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
		if (!source.isset && !source.invalid) {
			return;
		}
		if (target.isset || target.invalid) {
			FinRejectUnorderedCombine("fin_iv_rank");
		}
		auto window = target.window;
		target = source;
		target.window = window;
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

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.window;
		state.window = nullptr;
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
		if (source.values->empty() && !source.invalid) {
			return;
		}
		if (!target.values->empty() || target.invalid) {
			FinRejectUnorderedCombine("fin_iv_percentile");
		}
		target.invalid = source.invalid;
		*target.values = *source.values;
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
