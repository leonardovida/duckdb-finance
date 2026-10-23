struct EWMAState {
	bool isset;
	double variance;
	double lambda;
	double annualization;
	double scale;
	idx_t count;
	bool invalid;
	bool parameters_set;
	FinWindowAux *window;
};

// RiskMetrics EWMA over the ordered returns, seeded with the first squared
// return. Optional arguments are (lambda, annualization). The recursion is
// evaluated on returns normalized by a running scale so that tiny or huge
// returns neither underflow nor overflow.
template <bool RETURN_VOL>
struct EWMAOperation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 1;
	static constexpr bool ORDER_DEPENDENT = true;
	static constexpr bool WINDOW_INCREMENTAL = true;

	static const char *Name() {
		return RETURN_VOL ? "fin_ewma_vol" : "fin_ewma_variance";
	}

	template <class STATE>
	static void Initialize(STATE &state) {
		state.window = nullptr;
		WindowReset(state);
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		state.isset = false;
		state.variance = 0.0;
		state.lambda = DEFAULT_EWMA_LAMBDA;
		state.annualization = DEFAULT_ANNUALIZATION;
		state.scale = 0.0;
		state.count = 0;
		state.invalid = false;
		state.parameters_set = false;
	}

	// A NULL lambda or annualization skips the row (DuckDB's default NULL
	// handling), so only non-NULL constants are validated.
	static void ValidateParameter(idx_t column, double value, bool valid) {
		if (!valid) {
			return;
		}
		if (column == 1 && (value <= 0.0 || value >= 1.0 || !std::isfinite(value))) {
			throw InvalidInputException("%s: lambda must be finite and in (0, 1)", Name());
		}
		if (column == 2 && (value <= 0.0 || !std::isfinite(value))) {
			throw InvalidInputException("%s: annualization must be positive and finite", Name());
		}
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		if (input_count > 1) {
			auto lambda = row.v[1];
			auto annualization = input_count > 2 ? row.v[2] : state.annualization;
			if (!state.parameters_set || lambda != state.lambda || annualization != state.annualization) {
				ValidateParameter(1, lambda, true);
				if (input_count > 2) {
					ValidateParameter(2, annualization, true);
				}
				if (state.parameters_set) {
					throw InvalidInputException(input_count > 2
					                                ? "%s: lambda and annualization must be constant within a group"
					                                : "%s: lambda must be constant within a group",
					                            Name());
				}
				state.lambda = lambda;
				state.annualization = annualization;
				state.parameters_set = true;
			}
		}
		UpdateValue(state, row.v[0]);
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (state.invalid) {
			return;
		}
		if (!std::isfinite(value)) {
			// A non-finite return makes the group's EWMA undefined.
			state.invalid = true;
			return;
		}
		auto scale = std::abs(value);
		if (scale >= 1e-100 && scale <= 1.0) {
			scale = 1.0;
		}
		if (scale > state.scale) {
			auto ratio = state.scale / scale;
			state.variance *= ratio * ratio;
			state.scale = scale;
		}
		auto normalized = state.scale == 1.0 ? value : state.scale > 0.0 ? value / state.scale : 0.0;
		auto square = normalized * normalized;
		if (!state.isset) {
			state.variance = square;
			state.count = 1;
			state.isset = true;
			return;
		}
		state.variance = state.lambda * state.variance + (1.0 - state.lambda) * square;
		state.count++;
		if (state.variance > 0.0 && state.variance <= 1e-100 &&
		    state.scale > std::numeric_limits<double>::denorm_min()) {
			auto scale = std::max(std::numeric_limits<double>::denorm_min(), state.scale * std::sqrt(state.variance));
			auto ratio = state.scale / scale;
			state.variance = state.variance * ratio * ratio;
			state.scale = scale;
		}
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset && !source.invalid) {
			return;
		}
		if (target.isset || target.invalid) {
			FinRejectUnorderedCombine(Name());
		}
		auto window = target.window;
		target = source;
		target.window = window;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || !state.isset) {
			finalize_data.ReturnNull();
			return;
		}
		auto vol = ScaledRatio(std::sqrt(std::max(0.0, state.variance)), state.scale, 1.0, 1.0,
		                       std::sqrt(state.annualization));
		target = RETURN_VOL ? vol : vol * vol;
		if (!std::isfinite(target)) {
			finalize_data.ReturnNull();
		}
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.window;
		state.window = nullptr;
	}
};
