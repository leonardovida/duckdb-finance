struct OutlierCountState {
	vector<double> *values;
	double threshold;
};

struct OutlierCountOperation : public UnaryDoubleUpdateOperation<OutlierCountOperation> {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<double>();
		state.threshold = 3.0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (std::isfinite(value)) {
			state.values->push_back(value);
		}
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.values || source.values->empty()) {
			return;
		}
		if (target.values && !target.values->empty() && target.threshold != source.threshold) {
			throw InvalidInputException("Outlier threshold must be constant within a group");
		}
		target.threshold = source.threshold;
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &) {
		auto n = state.values ? NumericCast<idx_t>(state.values->size()) : idx_t(0);
		if (n < 2) {
			target = 0;
			return;
		}
		double sum = 0.0;
		for (auto value : *state.values) {
			sum += value;
		}
		auto mean = sum / static_cast<double>(n);
		double sum_sq = 0.0;
		for (auto value : *state.values) {
			auto diff = value - mean;
			sum_sq += diff * diff;
		}
		auto variance = sum_sq / static_cast<double>(n - 1);
		if (variance <= 0.0) {
			target = 0;
			return;
		}
		auto stddev = std::sqrt(variance);
		int64_t outliers = 0;
		for (auto value : *state.values) {
			if (std::abs(value - mean) / stddev > state.threshold) {
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
		if (threshold <= 0.0 || !std::isfinite(threshold)) {
			throw InvalidInputException("Outlier threshold must be positive and finite");
		}
		if (state.values && !state.values->empty() && state.threshold != threshold) {
			throw InvalidInputException("Outlier threshold must be constant within a group");
		}
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
