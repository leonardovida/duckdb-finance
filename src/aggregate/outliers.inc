struct OutlierCountState {
	vector<double> *values;
	double threshold;
	double scale;
};

struct OutlierCountOperation : public UnaryDoubleUpdateOperation<OutlierCountOperation> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<double>();
		state.threshold = 3.0;
		state.scale = 0.0;
	}

	template <class STATE>
	static void CheckThresholdConsistency(const STATE &state, double threshold) {
		// Only a retained finite observation fixes the group's threshold.
		if (state.values && !state.values->empty() && state.threshold != threshold) {
			throw InvalidInputException("Outlier threshold must be constant within a group");
		}
	}

	template <class STATE>
	static void ValidateThreshold(const STATE &state, double threshold) {
		if (threshold <= 0.0 || !std::isfinite(threshold)) {
			throw InvalidInputException("Outlier threshold must be positive and finite");
		}
		CheckThresholdConsistency(state, threshold);
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (std::isfinite(value)) {
			state.values->push_back(value);
			state.scale = std::max(state.scale, std::abs(value));
		}
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.values || source.values->empty()) {
			return;
		}
		CheckThresholdConsistency(target, source.threshold);
		target.threshold = source.threshold;
		target.scale = std::max(target.scale, source.scale);
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &) {
		auto n = state.values ? NumericCast<idx_t>(state.values->size()) : idx_t(0);
		if (n < 2 || state.scale == 0.0) {
			target = 0;
			return;
		}
		auto first = state.values->front();
		if (std::all_of(state.values->begin(), state.values->end(), [first](double value) { return value == first; })) {
			target = 0;
			return;
		}
		auto inverse_scale = 1.0 / state.scale;
		auto normalize = [&](double value) {
			return std::isfinite(inverse_scale) ? value * inverse_scale : value / state.scale;
		};
		auto sum = CompensatedVectorSum(*state.values, normalize);
		auto mean = sum / static_cast<double>(n);
		auto sum_sq = CompensatedVectorSum(*state.values, [&](double value) {
			auto diff = normalize(value) - mean;
			return diff * diff;
		});
		auto variance = sum_sq / static_cast<double>(n - 1);
		if (variance <= 0.0) {
			target = 0;
			return;
		}
		auto cutoff = state.threshold * std::sqrt(variance);
		int64_t outliers = 0;
		for (auto value : *state.values) {
			if (std::abs(normalize(value) - mean) > cutoff) {
				outliers++;
			}
		}
		target = outliers;
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

struct OutlierCountWithThresholdOperation : public OutlierCountOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double threshold) {
		ValidateThreshold(state, threshold);
		state.threshold = threshold;
		OutlierCountOperation::UpdateValue(state, value);
	}

	template <class INPUT_TYPE, class THRESHOLD_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const THRESHOLD_TYPE &threshold,
	                      AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(input), static_cast<double>(threshold));
	}
};

struct OutlierCountWithMethodOperation : public OutlierCountOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, const string &method, double threshold) {
		if (StringUtil::Lower(method) != "zscore") {
			throw InvalidInputException("fin_outlier_count currently supports method='zscore'");
		}
		OutlierCountWithThresholdOperation::UpdateValue(state, value, threshold);
	}
};

static bool AppendFlatOutliers(Vector &input, OutlierCountState &state, idx_t count) {
	if (input.GetVectorType() != VectorType::FLAT_VECTOR || !FlatVector::Validity(input).AllValid()) {
		return false;
	}
	auto values = FlatVector::GetData<double>(input);
	double scales[4] = {0.0, 0.0, 0.0, 0.0};
	idx_t i = 0;
	for (; i + 4 <= count; i += 4) {
		if (!std::isfinite(values[i]) || !std::isfinite(values[i + 1]) ||
		    !std::isfinite(values[i + 2]) || !std::isfinite(values[i + 3])) {
			return false;
		}
		for (idx_t lane = 0; lane < 4; lane++) {
			scales[lane] = std::max(scales[lane], std::abs(values[i + lane]));
		}
	}
	for (; i < count; i++) {
		if (!std::isfinite(values[i])) {
			return false;
		}
		scales[0] = std::max(scales[0], std::abs(values[i]));
	}
	// Validate the entire chunk before mutating state. Contiguous input then
	// needs one bulk append rather than a capacity check for every observation.
	state.values->insert(state.values->end(), values, values + count);
	for (auto scale : scales) {
		state.scale = std::max(state.scale, scale);
	}
	return true;
}

template <bool WITH_THRESHOLD>
static void OutlierCountSimpleUpdate(Vector inputs[], AggregateInputData &input_data, idx_t input_count,
                                     data_ptr_t state_ptr, idx_t count) {
	D_ASSERT(input_count == (WITH_THRESHOLD ? 2 : 1));
	if (count == 0) {
		return;
	}
	auto &state = *reinterpret_cast<OutlierCountState *>(state_ptr);
	bool eligible = inputs[0].GetVectorType() == VectorType::FLAT_VECTOR && FlatVector::Validity(inputs[0]).AllValid();
	double threshold = 3.0;
	if (WITH_THRESHOLD) {
		eligible = eligible && inputs[1].GetVectorType() == VectorType::CONSTANT_VECTOR &&
		           !ConstantVector::IsNull(inputs[1]);
		if (eligible) {
			threshold = ConstantVector::GetData<double>(inputs[1])[0];
			OutlierCountOperation::ValidateThreshold(state, threshold);
		}
	}
	if (eligible && AppendFlatOutliers(inputs[0], state, count)) {
		state.threshold = threshold;
		return;
	}
	if (WITH_THRESHOLD) {
		AggregateFunction::BinaryUpdate<OutlierCountState, double, double, OutlierCountWithThresholdOperation>(
		    inputs, input_data, input_count, state_ptr, count);
	} else {
		AggregateFunction::UnaryUpdate<OutlierCountState, double, OutlierCountOperation>(
		    inputs, input_data, input_count, state_ptr, count);
	}
}
