struct EWMAState {
	bool isset;
	double variance;
	double lambda;
	double annualization;
	double tail;
	double scale;
	double decay_product;
	idx_t count;
};

template <bool RETURN_VOL>
struct EWMAOperation : public UnaryDoubleUpdateOperation<EWMAOperation<RETURN_VOL>> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.variance = 0.0;
		state.lambda = DEFAULT_EWMA_LAMBDA;
		state.annualization = DEFAULT_ANNUALIZATION;
		state.tail = 0.0;
		state.scale = 0.0;
		state.decay_product = 1.0;
		state.count = 0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (!std::isfinite(value)) {
			throw InvalidInputException("EWMA returns must be finite");
		}
		auto scale = std::abs(value);
		if (scale >= 1e-100 && scale <= 1.0) {
			scale = 1.0;
		}
		if (scale > state.scale) {
			auto ratio = state.scale / scale;
			state.variance *= ratio * ratio;
			state.tail *= ratio * ratio;
			state.scale = scale;
		}
		auto normalized = state.scale == 1.0 ? value : state.scale > 0.0 ? value / state.scale : 0.0;
		auto square = normalized * normalized;
		if (!state.isset) {
			state.variance = square;
			state.tail = (1.0 - state.lambda) * square;
			state.decay_product = state.lambda;
			state.count = 1;
			state.isset = true;
			return;
		}
		state.variance = state.lambda * state.variance + (1.0 - state.lambda) * square;
		state.tail = state.lambda * state.tail + (1.0 - state.lambda) * square;
		state.decay_product *= state.lambda;
		state.count++;
		if (state.variance > 0.0 && state.variance <= 1e-100 &&
		    state.scale > std::numeric_limits<double>::denorm_min()) {
			auto scale = std::max(std::numeric_limits<double>::denorm_min(), state.scale * std::sqrt(state.variance));
			auto ratio = state.scale / scale;
			state.variance = state.variance * ratio * ratio;
			state.tail = state.tail * ratio * ratio;
			state.scale = scale;
		}
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
		if (target.lambda != source.lambda || target.annualization != source.annualization) {
			throw InvalidInputException("EWMA lambda and annualization must be constant within a group");
		}
		auto scale = std::max(source.scale, target.scale);
		auto left = scale > 0.0 ? target.scale / scale : 0.0;
		auto right = scale > 0.0 ? source.scale / scale : 0.0;
		// The zero-seeded tail appends source observations without a subtraction
		// of nearly equal seeded variances. Work in a common scale before merging.
		auto variance = source.decay_product * target.variance * left * left + source.tail * right * right;
		auto tail = source.decay_product * target.tail * left * left + source.tail * right * right;
		if (source.decay_product == 0.0 || variance <= 1e-100) {
			auto log_decay = 0.5 * static_cast<double>(source.count) * std::log(source.lambda);
			auto magnitude = std::max(DecayedMagnitude(std::sqrt(target.variance), target.scale, log_decay),
			                          DecayedMagnitude(std::sqrt(target.tail), target.scale, log_decay));
			magnitude = std::max(magnitude, DecayedMagnitude(std::sqrt(source.tail), source.scale, 0.0));
			scale = ScaleForMagnitude(magnitude);
			auto root = ExponentialScaledRatio(std::sqrt(target.variance), target.scale, scale, log_decay);
			auto left_tail = ExponentialScaledRatio(std::sqrt(target.tail), target.scale, scale, log_decay);
			auto right_tail = ExponentialScaledRatio(std::sqrt(source.tail), source.scale, scale, 0.0);
			variance = root * root + right_tail * right_tail;
			tail = left_tail * left_tail + right_tail * right_tail;
		}
		target.variance = variance;
		target.tail = tail;
		target.scale = scale;
		target.decay_product *= source.decay_product;
		target.count += source.count;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset) {
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
		if (state.isset && state.lambda != lambda) {
			throw InvalidInputException("EWMA lambda must be constant within a group");
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
		if (state.isset && (state.lambda != lambda || state.annualization != annualization)) {
			throw InvalidInputException("EWMA lambda and annualization must be constant within a group");
		}
		state.lambda = lambda;
		state.annualization = annualization;
		EWMAOperation<RETURN_VOL>::UpdateValue(state, value);
	}
};
