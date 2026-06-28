struct EWMAState {
	bool isset;
	double variance;
	double lambda;
	double annualization;
};

template <bool RETURN_VOL>
struct EWMAOperation : public UnaryDoubleUpdateOperation<EWMAOperation<RETURN_VOL>> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.variance = 0.0;
		state.lambda = DEFAULT_EWMA_LAMBDA;
		state.annualization = DEFAULT_ANNUALIZATION;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		auto square = value * value;
		if (!state.isset) {
			state.variance = square;
			state.isset = true;
			return;
		}
		state.variance = state.lambda * state.variance + (1.0 - state.lambda) * square;
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
		target.variance = target.lambda * target.variance + (1.0 - target.lambda) * source.variance;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset) {
			finalize_data.ReturnNull();
			return;
		}
		auto annualized = state.variance * state.annualization;
		target = RETURN_VOL ? std::sqrt(annualized) : annualized;
	}

	static bool IgnoreNull() {
		return true;
	}
};

template <bool RETURN_VOL>
struct EWMAWithLambdaOperation : public EWMAOperation<RETURN_VOL> {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double lambda) {
		if (lambda <= 0.0 || lambda >= 1.0 || !std::isfinite(lambda)) {
			throw InvalidInputException("EWMA lambda must be finite and in (0, 1)");
		}
		state.lambda = lambda;
		EWMAOperation<RETURN_VOL>::UpdateValue(state, value);
	}

	template <class INPUT_TYPE, class LAMBDA_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, const LAMBDA_TYPE &lambda, AggregateBinaryInput &,
	                              idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input), static_cast<double>(lambda));
		}
	}

	template <class INPUT_TYPE, class LAMBDA_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const LAMBDA_TYPE &lambda, AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(input), static_cast<double>(lambda));
	}
};

template <bool RETURN_VOL>
struct EWMAWithLambdaAnnualizationOperation : public EWMAOperation<RETURN_VOL> {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double lambda, double annualization) {
		if (lambda <= 0.0 || lambda >= 1.0 || !std::isfinite(lambda)) {
			throw InvalidInputException("EWMA lambda must be finite and in (0, 1)");
		}
		if (annualization <= 0.0 || !std::isfinite(annualization)) {
			throw InvalidInputException("EWMA annualization must be positive and finite");
		}
		state.lambda = lambda;
		state.annualization = annualization;
		EWMAOperation<RETURN_VOL>::UpdateValue(state, value);
	}
};
