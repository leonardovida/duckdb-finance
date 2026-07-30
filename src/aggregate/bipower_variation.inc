struct BipowerVariationState {
	bool isset;
	double first_absolute_return;
	double last_absolute_return;
	double product_sum;
	double product_compensation;
	double annualization;
	idx_t count;
};

struct BipowerVariationOperation : public UnaryDoubleUpdateOperation<BipowerVariationOperation> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.first_absolute_return = 0.0;
		state.last_absolute_return = 0.0;
		state.product_sum = 0.0;
		state.product_compensation = 0.0;
		state.annualization = DEFAULT_ANNUALIZATION;
		state.count = 0;
	}

	template <class STATE>
	static void AddProduct(STATE &state, double product) {
		if (!std::isfinite(product)) {
			throw InvalidInputException("Bipower variation products must be finite");
		}
		double adjusted = product - state.product_compensation;
		double sum = state.product_sum + adjusted;
		if (!std::isfinite(sum)) {
			throw InvalidInputException("Bipower variation sum must be finite");
		}
		state.product_compensation = (sum - state.product_sum) - adjusted;
		state.product_sum = sum;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (!std::isfinite(value)) {
			throw InvalidInputException("Bipower variation returns must be finite");
		}
		double absolute_return = std::fabs(value);
		if (!state.isset) {
			state.isset = true;
			state.first_absolute_return = absolute_return;
		} else {
			AddProduct(state, state.last_absolute_return * absolute_return);
		}
		state.last_absolute_return = absolute_return;
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
		if (target.annualization != source.annualization) {
			throw InvalidInputException("Bipower variation annualization must be constant within a group");
		}
		AddProduct(target, target.last_absolute_return * source.first_absolute_return);
		AddProduct(target, source.product_sum);
		target.last_absolute_return = source.last_absolute_return;
		target.count += source.count;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.count < 2) {
			finalize_data.ReturnNull();
			return;
		}
		constexpr double HALF_PI = 1.57079632679489661923;
		target = HALF_PI * state.product_sum * state.annualization / static_cast<double>(state.count - 1);
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct BipowerVariationWithAnnualizationOperation : public BipowerVariationOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double annualization) {
		if (!(annualization > 0.0) || !std::isfinite(annualization)) {
			throw InvalidInputException("Bipower variation annualization must be positive and finite");
		}
		if (state.isset && state.annualization != annualization) {
			throw InvalidInputException("Bipower variation annualization must be constant within a group");
		}
		state.annualization = annualization;
		BipowerVariationOperation::UpdateValue(state, value);
	}

	template <class INPUT_TYPE, class ANNUALIZATION_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, const ANNUALIZATION_TYPE &annualization,
	                              AggregateBinaryInput &, idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input), static_cast<double>(annualization));
		}
	}

	template <class INPUT_TYPE, class ANNUALIZATION_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const ANNUALIZATION_TYPE &annualization,
	                      AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(input), static_cast<double>(annualization));
	}
};
