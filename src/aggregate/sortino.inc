struct SortinoState {
	idx_t count;
	double sum_excess;
	double downside_sq;
	double annualization;
	double scale;
	double correction;
	double downside_correction;
	double downside_scale;
};

struct SortinoOperation : public UnaryDoubleUpdateOperation<SortinoOperation> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.count = 0;
		state.sum_excess = 0.0;
		state.downside_sq = 0.0;
		state.annualization = DEFAULT_ANNUALIZATION;
		state.scale = state.correction = state.downside_correction = 0.0;
		state.downside_scale = 0.0;
	}

	static void AddExcess(double value, double &sum, double &correction) {
		auto next = sum + value;
		correction += std::abs(sum) >= std::abs(value) ? (sum - next) + value : (value - next) + sum;
		sum = next;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (!std::isfinite(value)) {
			throw InvalidInputException("Sortino excess returns must be finite");
		}
		auto scale = std::abs(value);
		// Ordinary returns need no rescaling. Keep their hot path in original
		// units; only extreme magnitudes need a non-unit normalization scale.
		if (scale >= 1e-100 && scale <= 1e100) {
			scale = 1.0;
		}
		if (scale > state.scale) {
			auto ratio = state.scale / scale;
			state.sum_excess *= ratio;
			state.correction *= ratio;
			state.scale = scale;
		}
		auto normalized = state.scale == 1.0 ? value : state.scale > 0.0 ? value / state.scale : 0.0;
		state.count++;
		AddExcess(normalized, state.sum_excess, state.correction);
		if (value < 0.0) {
			if (scale > state.downside_scale) {
				auto ratio = state.downside_scale / scale;
				state.downside_sq = state.downside_sq * ratio * ratio;
				state.downside_correction = state.downside_correction * ratio * ratio;
				state.downside_scale = scale;
			}
			auto downside = state.downside_scale == 1.0 ? value : value / state.downside_scale;
			AddCompensated(downside * downside, state.downside_sq, state.downside_correction);
		}
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (source.count == 0) {
			return;
		}
		if (target.count == 0) {
			target = source;
			return;
		} else if (target.annualization != source.annualization) {
			throw InvalidInputException("Sortino annualization must be constant within a group");
		}
		target.count += source.count;
		auto scale = std::max(target.scale, source.scale);
		auto left = scale > 0.0 ? target.scale / scale : 0.0;
		auto right = scale > 0.0 ? source.scale / scale : 0.0;
		target.sum_excess *= left;
		target.correction *= left;
		AddExcess(source.sum_excess * right, target.sum_excess, target.correction);
		AddExcess(source.correction * right, target.sum_excess, target.correction);
		target.scale = scale;
		auto downside_scale = std::max(target.downside_scale, source.downside_scale);
		left = downside_scale > 0.0 ? target.downside_scale / downside_scale : 0.0;
		right = downside_scale > 0.0 ? source.downside_scale / downside_scale : 0.0;
		target.downside_sq = target.downside_sq * left * left;
		target.downside_correction = target.downside_correction * left * left;
		AddCompensated(source.downside_sq * right * right, target.downside_sq, target.downside_correction);
		target.downside_scale = downside_scale;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.count == 0 || state.downside_sq <= 0.0) {
			finalize_data.ReturnNull();
			return;
		}
		auto mean = (state.sum_excess + state.correction) / static_cast<double>(state.count);
		auto downside = std::sqrt(state.downside_sq / static_cast<double>(state.count));
		target = ScaledRatio(mean, state.scale, downside, state.downside_scale, std::sqrt(state.annualization));
		if (!std::isfinite(target)) {
			finalize_data.ReturnNull();
		}
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct SortinoWithMAROperation : public SortinoOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double mar) {
		if (!std::isfinite(value) || !std::isfinite(mar)) {
			throw InvalidInputException("Sortino returns and MAR must be finite");
		}
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
		if (!std::isfinite(value) || !std::isfinite(mar)) {
			throw InvalidInputException("Sortino returns and MAR must be finite");
		}
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

static void SortinoSimpleUpdate(Vector inputs[], AggregateInputData &input_data, idx_t input_count,
                                 data_ptr_t state_ptr, idx_t count) {
	D_ASSERT(input_count == 1);
	auto &state = *reinterpret_cast<SortinoState *>(state_ptr);
	bool eligible = inputs[0].GetVectorType() == VectorType::FLAT_VECTOR && FlatVector::Validity(inputs[0]).AllValid() &&
	                (state.count == 0 || state.scale == 1.0) &&
	                (state.downside_scale == 0.0 || state.downside_scale == 1.0);
	auto values = eligible ? FlatVector::GetData<double>(inputs[0]) : nullptr;
	if (eligible) {
		for (idx_t i = 0; i < count; i++) {
			auto magnitude = std::abs(values[i]);
			if (!std::isfinite(values[i]) || magnitude > 1e100 || (magnitude > 0.0 && magnitude < 1e-100)) {
				eligible = false;
				break;
			}
		}
	}
	if (!eligible) {
		AggregateFunction::UnaryUpdate<SortinoState, double, SortinoOperation>(
		    inputs, input_data, input_count, state_ptr, count);
		return;
	}
	// Fold an ordinary flat chunk with independent compensated lanes. Extreme,
	// nullable and selected inputs retain the general scaled update path.
	double sums[4] = {0.0, 0.0, 0.0, 0.0};
	double corrections[4] = {0.0, 0.0, 0.0, 0.0};
	double downside[4] = {0.0, 0.0, 0.0, 0.0};
	double downside_corrections[4] = {0.0, 0.0, 0.0, 0.0};
	auto add = [&](idx_t i, idx_t lane) {
		auto value = values[i];
		SortinoOperation::AddExcess(value, sums[lane], corrections[lane]);
		AddCompensated(value < 0.0 ? value * value : 0.0, downside[lane], downside_corrections[lane]);
	};
	idx_t i = 0;
	for (; i + 4 <= count; i += 4) {
		add(i, 0);
		add(i + 1, 1);
		add(i + 2, 2);
		add(i + 3, 3);
	}
	for (; i < count; i++) {
		add(i, 0);
	}
	SortinoState chunk;
	SortinoOperation::Initialize(chunk);
	chunk.scale = chunk.downside_scale = 1.0;
	chunk.count = count;
	for (idx_t lane = 0; lane < 4; lane++) {
		SortinoOperation::AddExcess(sums[lane], chunk.sum_excess, chunk.correction);
		SortinoOperation::AddExcess(corrections[lane], chunk.sum_excess, chunk.correction);
		AddCompensated(downside[lane], chunk.downside_sq, chunk.downside_correction);
		AddCompensated(-downside_corrections[lane], chunk.downside_sq, chunk.downside_correction);
	}
	SortinoOperation::Combine<SortinoState, SortinoOperation>(chunk, state, input_data);
}
