struct DrawdownState {
	bool isset;
	vector<double> *values;
	double nav;
	double peak;
	double current_drawdown;
	double min_drawdown;
	double sum_drawdown;
	double sum_drawdown_sq;
	idx_t count;
	idx_t current_duration;
	idx_t max_duration;
};

struct DrawdownOperationBase : public UnaryDoubleUpdateOperation<DrawdownOperationBase> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.values = new vector<double>();
		state.nav = 1.0;
		state.peak = 1.0;
		state.current_drawdown = 0.0;
		state.min_drawdown = 0.0;
		state.sum_drawdown = 0.0;
		state.sum_drawdown_sq = 0.0;
		state.count = 0;
		state.current_duration = 0;
		state.max_duration = 0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value, double initial_nav = 1.0) {
		if (!std::isfinite(value) || value < -1.0) {
			throw InvalidInputException("Drawdown returns must be finite and greater than or equal to -1");
		}
		if (initial_nav <= 0.0 || !std::isfinite(initial_nav)) {
			throw InvalidInputException("Initial NAV must be positive and finite");
		}
		if (!state.isset) {
			state.isset = true;
			state.nav = initial_nav;
			state.peak = initial_nav;
		}
		state.values->push_back(value);
		state.nav *= 1.0 + value;
		state.peak = std::max(state.peak, state.nav);
		state.current_drawdown = state.peak == 0.0 ? 0.0 : state.nav / state.peak - 1.0;
		state.min_drawdown = std::min(state.min_drawdown, state.current_drawdown);
		state.sum_drawdown += state.current_drawdown;
		state.sum_drawdown_sq += state.current_drawdown * state.current_drawdown;
		state.count++;
		if (state.current_drawdown < 0.0) {
			state.current_duration++;
			state.max_duration = std::max(state.max_duration, state.current_duration);
		} else {
			state.current_duration = 0;
		}
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset) {
			return;
		}
		if (!target.isset) {
			for (auto value : *source.values) {
				UpdateValue(target, value);
			}
			return;
		}
		// Drawdowns in the right-hand state depend on the peak reached by the
		// left-hand state, so isolated summaries cannot be merged exactly.
		for (auto value : *source.values) {
			UpdateValue(target, value);
		}
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

template <class FINALIZE_OPERATION>
struct DrawdownWithInitialNavOperation : public FINALIZE_OPERATION {
	template <class INPUT_TYPE, class NAV_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const NAV_TYPE &initial_nav, AggregateBinaryInput &) {
		DrawdownOperationBase::UpdateValue(state, static_cast<double>(input), static_cast<double>(initial_nav));
	}
};

struct CurrentDrawdownOperation : public DrawdownOperationBase {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.current_drawdown;
	}
};

struct MaxDrawdownOperation : public DrawdownOperationBase {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.min_drawdown;
	}
};

struct AvgDrawdownOperation : public DrawdownOperationBase {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.sum_drawdown / static_cast<double>(state.count);
	}
};

struct UlcerIndexOperation : public DrawdownOperationBase {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = std::sqrt(state.sum_drawdown_sq / static_cast<double>(state.count));
	}
};

struct DrawdownDurationOperation : public DrawdownOperationBase {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = static_cast<int64_t>(state.max_duration);
	}
};
