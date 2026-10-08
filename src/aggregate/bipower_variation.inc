struct BipowerVariationState {
	bool isset;
	double last_absolute_return;
	double product_sum;
	double product_compensation;
	double annualization;
	idx_t count;
	bool invalid;
	bool annualization_set;
	FinWindowAux *window;
};

// Bipower variation (Barndorff-Nielsen and Shephard, 2004) of the ordered
// returns: (pi / 2) * annualization * sum |r_t| |r_(t-1)| / (n - 1). The
// optional argument is the annualization factor.
struct BipowerVariationOperation : public FinOperationDefaults {
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
		state.last_absolute_return = 0.0;
		state.product_sum = 0.0;
		state.product_compensation = 0.0;
		state.annualization = DEFAULT_ANNUALIZATION;
		state.count = 0;
		state.invalid = false;
		state.annualization_set = false;
	}

	// A NULL annualization skips the row (DuckDB's default NULL handling), so
	// only a non-NULL constant is validated.
	static void ValidateParameter(idx_t, double annualization, bool valid) {
		if (valid && (!(annualization > 0.0) || !std::isfinite(annualization))) {
			throw InvalidInputException("fin_bipower_variation: annualization must be positive and finite");
		}
	}

	template <class STATE>
	static void AddProduct(STATE &state, double product) {
		double adjusted = product - state.product_compensation;
		double sum = state.product_sum + adjusted;
		if (!std::isfinite(product) || !std::isfinite(sum)) {
			state.invalid = true;
			return;
		}
		state.product_compensation = (sum - state.product_sum) - adjusted;
		state.product_sum = sum;
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		if (input_count > 1 && (!state.annualization_set || row.v[1] != state.annualization)) {
			ValidateParameter(1, row.v[1], true);
			if (state.annualization_set) {
				throw InvalidInputException("fin_bipower_variation: annualization must be constant within a group");
			}
			state.annualization = row.v[1];
			state.annualization_set = true;
		}
		auto value = row.v[0];
		if (!std::isfinite(value)) {
			state.invalid = true;
			return;
		}
		double absolute_return = std::fabs(value);
		if (!state.isset) {
			state.isset = true;
		} else {
			AddProduct(state, state.last_absolute_return * absolute_return);
		}
		state.last_absolute_return = absolute_return;
		state.count++;
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset && !source.invalid) {
			return;
		}
		if (target.isset || target.invalid) {
			FinRejectUnorderedCombine("fin_bipower_variation");
		}
		auto window = target.window;
		target = source;
		target.window = window;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.count < 2) {
			finalize_data.ReturnNull();
			return;
		}
		constexpr double HALF_PI = 1.57079632679489661923;
		target = HALF_PI * state.product_sum * state.annualization / static_cast<double>(state.count - 1);
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.window;
		state.window = nullptr;
	}
};
