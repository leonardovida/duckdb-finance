struct QuantileSpreadState {
	vector<std::pair<double, double>> *values;
	int32_t buckets;
	bool buckets_set;
	bool invalid;
	double scale;
};

struct QuantileSpreadOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<std::pair<double, double>>();
		state.buckets = 5;
		state.buckets_set = false;
		state.invalid = false;
		state.scale = 0.0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double factor, double forward_return, double buckets = 5.0) {
		auto bucket_count = static_cast<int32_t>(std::llround(buckets));
		if (bucket_count <= 1) {
			throw InvalidInputException("fin_quantile_spread: buckets must be greater than 1");
		}
		if (state.buckets_set && state.buckets != bucket_count) {
			throw InvalidInputException("fin_quantile_spread: buckets must be constant within a group");
		}
		state.buckets = bucket_count;
		state.buckets_set = true;
		if (!std::isfinite(factor) || !std::isfinite(forward_return)) {
			// A non-finite factor or return makes the group's spread undefined.
			state.invalid = true;
			return;
		}
		state.values->push_back({factor, forward_return});
		state.scale = std::max(state.scale, std::abs(forward_return));
	}

	template <class INPUT_TYPE, class RETURN_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &factor, const RETURN_TYPE &forward_return,
	                      AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(factor), static_cast<double>(forward_return));
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.buckets_set) {
			return;
		}
		if (target.buckets_set && target.buckets != source.buckets) {
			throw InvalidInputException("fin_quantile_spread: buckets must be constant within a group");
		}
		target.invalid = target.invalid || source.invalid;
		target.buckets = source.buckets;
		target.buckets_set = true;
		target.scale = std::max(target.scale, source.scale);
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		auto n = state.values ? NumericCast<idx_t>(state.values->size()) : idx_t(0);
		if (state.invalid || n == 0) {
			finalize_data.ReturnNull();
			return;
		}
		auto bucket_size = std::max<idx_t>(1, (n + NumericCast<idx_t>(state.buckets) - 1) /
		                                          NumericCast<idx_t>(state.buckets));
		bucket_size = std::min(bucket_size, n);
		auto &values = *state.values;
		auto compare = [](const auto &lhs, const auto &rhs) { return lhs.first < rhs.first; };
		auto lower = bucket_size - 1;
		auto upper = n - bucket_size;
		std::nth_element(values.begin(), values.begin() + lower, values.end(), compare);
		auto bottom_cutoff = values[lower].first;
		if (upper > lower) {
			std::nth_element(values.begin() + lower + 1, values.begin() + upper, values.end(), compare);
		}
		auto top_cutoff = values[upper].first;
		double bottom_sum = 0.0;
		double top_sum = 0.0;
		double bottom_ties = 0.0;
		double top_ties = 0.0;
		double corrections[4] = {0.0, 0.0, 0.0, 0.0};
		idx_t bottom_count = 0, top_count = 0, bottom_tie_count = 0, top_tie_count = 0;
		for (const auto &entry : values) {
			auto value = state.scale > 0.0 ? entry.second / state.scale : 0.0;
			if (entry.first < bottom_cutoff) {
				AddCompensated(value, bottom_sum, corrections[0]);
				bottom_count++;
			} else if (entry.first == bottom_cutoff) {
				AddCompensated(value, bottom_ties, corrections[1]);
				bottom_tie_count++;
			}
			if (entry.first > top_cutoff) {
				AddCompensated(value, top_sum, corrections[2]);
				top_count++;
			} else if (entry.first == top_cutoff) {
				AddCompensated(value, top_ties, corrections[3]);
				top_tie_count++;
			}
		}
		// Share the remaining bucket slots equally across a boundary tie. This
		// avoids an arbitrary row order deciding which tied returns are selected.
		bottom_sum += bottom_ties * (static_cast<double>(bucket_size - bottom_count) / bottom_tie_count);
		top_sum += top_ties * (static_cast<double>(bucket_size - top_count) / top_tie_count);
		target = (top_sum / static_cast<double>(bucket_size) - bottom_sum / static_cast<double>(bucket_size)) * state.scale;
		if (!std::isfinite(target)) {
			finalize_data.ReturnNull();
		}
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
