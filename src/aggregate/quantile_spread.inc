struct QuantileSpreadState {
	vector<std::pair<double, double>> *values;
	int32_t buckets;
};

struct QuantileSpreadOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<std::pair<double, double>>();
		state.buckets = 5;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double factor, double forward_return, double buckets = 5.0) {
		if (!std::isfinite(factor) || !std::isfinite(forward_return)) {
			return;
		}
		auto bucket_count = static_cast<int32_t>(std::llround(buckets));
		if (bucket_count <= 1) {
			throw InvalidInputException("Quantile spread buckets must be greater than 1");
		}
		state.buckets = bucket_count;
		state.values->push_back({factor, forward_return});
	}

	template <class INPUT_TYPE, class RETURN_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &factor, const RETURN_TYPE &forward_return,
	                      AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(factor), static_cast<double>(forward_return));
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.values || source.values->empty()) {
			return;
		}
		target.buckets = source.buckets;
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		auto n = state.values ? NumericCast<idx_t>(state.values->size()) : idx_t(0);
		if (n == 0) {
			finalize_data.ReturnNull();
			return;
		}
		std::sort(state.values->begin(), state.values->end(),
		          [](const auto &lhs, const auto &rhs) { return lhs.first < rhs.first; });
		auto bucket_size = std::max<idx_t>(1, (n + NumericCast<idx_t>(state.buckets) - 1) /
		                                          NumericCast<idx_t>(state.buckets));
		bucket_size = std::min(bucket_size, n);
		double bottom_sum = 0.0;
		double top_sum = 0.0;
		for (idx_t i = 0; i < bucket_size; i++) {
			bottom_sum += (*state.values)[i].second;
			top_sum += (*state.values)[n - bucket_size + i].second;
		}
		target = top_sum / static_cast<double>(bucket_size) - bottom_sum / static_cast<double>(bucket_size);
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

struct QuantileSpreadWithBucketsOperation : public QuantileSpreadOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double factor, double forward_return, double buckets) {
		QuantileSpreadOperation::UpdateValue(state, factor, forward_return, buckets);
	}
};
