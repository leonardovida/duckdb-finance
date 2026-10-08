struct DrawdownState {
	bool isset;
	bool invalid;
	FinWindowAux *window;
	double nav;
	double initial_nav;
	double current_drawdown;
	double min_drawdown;
	double sum_drawdown;
	double sum_drawdown_sq;
	idx_t count;
	idx_t current_duration;
	idx_t max_duration;
};

// Drawdowns are measured on NAV relative to its running peak, which stays in
// [0, 1]: D_t = NAV_t / max(initial_nav, max_{s<=t} NAV_s) - 1. The ratio is
// scale-invariant, so initial_nav is validated but does not change results.
template <class NAME>
struct DrawdownOperationBase : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 1;
	static constexpr bool ORDER_DEPENDENT = true;
	static constexpr bool WINDOW_INCREMENTAL = true;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.window = nullptr;
		Reset(state);
	}

	template <class STATE>
	static void Reset(STATE &state) {
		state.isset = false;
		state.invalid = false;
		state.nav = 1.0;
		state.initial_nav = 1.0;
		state.current_drawdown = 0.0;
		state.min_drawdown = 0.0;
		state.sum_drawdown = 0.0;
		state.sum_drawdown_sq = 0.0;
		state.count = 0;
		state.current_duration = 0;
		state.max_duration = 0;
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		Reset(state);
	}

	static void ValidateParameter(idx_t, double initial_nav, bool) {
		if (!(initial_nav > 0.0) || !std::isfinite(initial_nav)) {
			throw InvalidInputException("%s: initial_nav must be positive and finite", NAME::Name());
		}
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (state.invalid) {
			return;
		}
		if (!std::isfinite(value) || value < -1.0) {
			// Non-finite or below-total-loss returns make the group's drawdown undefined.
			state.invalid = true;
			return;
		}
		state.isset = true;
		state.nav = std::min(1.0, state.nav * (1.0 + value));
		state.current_drawdown = state.nav - 1.0;
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

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		if (input_count > 1) {
			auto initial_nav = row.valid[1] ? row.v[1] : std::numeric_limits<double>::quiet_NaN();
			if (!state.isset || initial_nav != state.initial_nav) {
				ValidateParameter(1, initial_nav, row.valid[1]);
			}
			state.initial_nav = initial_nav;
		}
		UpdateValue(state, row.v[0]);
	}

	template <class STATE>
	static bool HasRows(const STATE &state) {
		return state.isset || state.invalid;
	}

	// Drawdowns depend on the running peak of the ordered series, so only a
	// state that has not seen rows may take over another state's summary.
	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!HasRows(source)) {
			return;
		}
		if (HasRows(target)) {
			FinRejectUnorderedCombine(NAME::Name());
		}
		auto window = target.window;
		target = source;
		target.window = window;
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.window;
		state.window = nullptr;
	}

	template <class STATE>
	static bool Empty(STATE &state) {
		return state.invalid || !state.isset || state.count == 0;
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct CurrentDrawdownName {
	static const char *Name() {
		return "fin_drawdown";
	}
};
struct MaxDrawdownName {
	static const char *Name() {
		return "fin_max_drawdown";
	}
};
struct AvgDrawdownName {
	static const char *Name() {
		return "fin_avg_drawdown";
	}
};
struct UlcerIndexName {
	static const char *Name() {
		return "fin_ulcer_index";
	}
};
struct DrawdownDurationName {
	static const char *Name() {
		return "fin_drawdown_duration";
	}
};

struct CurrentDrawdownOperation : public DrawdownOperationBase<CurrentDrawdownName> {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (Empty(state)) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.current_drawdown;
	}
};

struct MaxDrawdownOperation : public DrawdownOperationBase<MaxDrawdownName> {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (Empty(state)) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.min_drawdown;
	}
};

struct AvgDrawdownOperation : public DrawdownOperationBase<AvgDrawdownName> {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (Empty(state)) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.sum_drawdown / static_cast<double>(state.count);
	}
};

struct UlcerIndexOperation : public DrawdownOperationBase<UlcerIndexName> {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (Empty(state)) {
			finalize_data.ReturnNull();
			return;
		}
		target = std::sqrt(state.sum_drawdown_sq / static_cast<double>(state.count));
	}
};

struct DrawdownDurationOperation : public DrawdownOperationBase<DrawdownDurationName> {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (Empty(state)) {
			finalize_data.ReturnNull();
			return;
		}
		target = static_cast<int64_t>(state.max_duration);
	}
};

//===--------------------------------------------------------------------===//
// Drawdown at risk (Chekhlov, Uryasev and Zabarankin, 2005)
//===--------------------------------------------------------------------===//
// Drawdown magnitudes D_t = 1 - NAV_t / peak_t >= 0 are built from the ordered
// returns. DaR is the linear-interpolation confidence quantile of D_t and CDaR
// is the mean of the drawdowns at or beyond DaR.
struct DrawdownRiskState {
	vector<double> *values;
	vector<double> *scratch;
	FinWindowAux *window;
	double confidence;
	bool confidence_set;
	bool invalid;
};

template <bool CONDITIONAL>
struct DrawdownRiskOperation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 1;
	static constexpr bool ORDER_DEPENDENT = true;
	static constexpr bool WINDOW_INCREMENTAL = true;

	static const char *Name() {
		return CONDITIONAL ? "fin_conditional_drawdown_at_risk" : "fin_drawdown_at_risk";
	}

	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<double>();
		state.scratch = new vector<double>();
		state.window = nullptr;
		WindowReset(state);
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		state.values->clear();
		state.confidence = 0.95;
		state.confidence_set = false;
		state.invalid = false;
	}

	static void ValidateParameter(idx_t, double confidence, bool) {
		if (!std::isfinite(confidence) || confidence <= 0.0 || confidence >= 1.0) {
			throw InvalidInputException("%s: confidence must be finite and in (0, 1)", Name());
		}
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		if (input_count > 1) {
			auto confidence = row.valid[1] ? row.v[1] : std::numeric_limits<double>::quiet_NaN();
			if (!state.confidence_set || confidence != state.confidence) {
				ValidateParameter(1, confidence, row.valid[1]);
				if (state.confidence_set) {
					throw InvalidInputException("%s: confidence must be constant within a group", Name());
				}
			}
			state.confidence = confidence;
		}
		state.confidence_set = true;
		auto value = row.v[0];
		if (!std::isfinite(value) || value < -1.0) {
			state.invalid = true;
			return;
		}
		state.values->push_back(value);
	}

	// Every counted row sets confidence_set, so it marks a state that has seen rows.
	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.confidence_set) {
			return;
		}
		if (target.confidence_set) {
			FinRejectUnorderedCombine(Name());
		}
		target.confidence = source.confidence;
		target.confidence_set = true;
		target.invalid = source.invalid;
		*target.values = *source.values;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.values->empty()) {
			finalize_data.ReturnNull();
			return;
		}
		auto &drawdowns = *state.scratch;
		drawdowns.clear();
		double nav = 1.0;
		for (auto value : *state.values) {
			nav = std::min(1.0, nav * (1.0 + value));
			drawdowns.push_back(1.0 - nav);
		}
		auto dar = FinContinuousQuantile(drawdowns, state.confidence);
		if (!CONDITIONAL) {
			target = dar;
			return;
		}
		FinSum sum;
		sum.Reset();
		idx_t count = 0;
		for (auto drawdown : drawdowns) {
			if (drawdown >= dar) {
				sum.Add(drawdown);
				count++;
			}
		}
		target = count == 0 ? dar : sum.Value() / static_cast<double>(count);
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.values;
		state.values = nullptr;
		delete state.scratch;
		state.scratch = nullptr;
		delete state.window;
		state.window = nullptr;
	}
};
