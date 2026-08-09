struct SortinoState {
	idx_t count;
	double sum_excess;
	double downside_sq;
	double annualization;
};

struct SortinoOperation : public UnaryDoubleUpdateOperation<SortinoOperation> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.count = 0;
		state.sum_excess = 0.0;
		state.downside_sq = 0.0;
		state.annualization = DEFAULT_ANNUALIZATION;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		state.count++;
		state.sum_excess += value;
		if (value < 0.0) {
			state.downside_sq += value * value;
		}
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (source.count == 0) {
			return;
		}
		if (target.count == 0) {
			target.annualization = source.annualization;
		} else if (target.annualization != source.annualization) {
			throw InvalidInputException("Sortino annualization must be constant within a group");
		}
		target.count += source.count;
		target.sum_excess += source.sum_excess;
		target.downside_sq += source.downside_sq;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.count == 0 || state.downside_sq <= 0.0) {
			finalize_data.ReturnNull();
			return;
		}
		auto mean = state.sum_excess / static_cast<double>(state.count);
		auto downside = std::sqrt(state.downside_sq / static_cast<double>(state.count));
		target = mean / downside * std::sqrt(state.annualization);
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct SortinoWithMAROperation : public SortinoOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double mar) {
		SortinoOperation::UpdateValue(state, value - mar / DEFAULT_ANNUALIZATION);
	}

	template <class INPUT_TYPE, class MAR_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, const MAR_TYPE &mar, AggregateBinaryInput &,
	                              idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input), static_cast<double>(mar));
		}
	}

	template <class INPUT_TYPE, class MAR_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const MAR_TYPE &mar, AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(input), static_cast<double>(mar));
	}
};

struct SortinoWithMARAnnualizationOperation : public SortinoOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double mar, double annualization) {
		if (annualization <= 0.0 || !std::isfinite(annualization)) {
			throw InvalidInputException("Sortino annualization must be positive and finite");
		}
		if (state.count > 0 && state.annualization != annualization) {
			throw InvalidInputException("Sortino annualization must be constant within a group");
		}
		state.annualization = annualization;
		SortinoOperation::UpdateValue(state, value - mar / annualization);
	}
};
