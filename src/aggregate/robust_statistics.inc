struct RobustStatisticsState {
	vector<double> *values;
	double first_parameter;
	double second_parameter;
	double scale;
	bool parameters_set;
};

struct RobustStatisticsOperationBase {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<double>();
		state.first_parameter = 0.0;
		state.second_parameter = 0.0;
		state.scale = 1.0;
		state.parameters_set = false;
	}

	template <class STATE>
	static void UpdateParameters(STATE &state, double first_parameter, double second_parameter) {
		if (state.parameters_set &&
		    (state.first_parameter != first_parameter || state.second_parameter != second_parameter)) {
			throw InvalidInputException("Aggregate parameters must be constant within a group");
		}
		state.first_parameter = first_parameter;
		state.second_parameter = second_parameter;
		state.parameters_set = true;
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.parameters_set) {
			return;
		}
		UpdateParameters(target, source.first_parameter, source.second_parameter);
		target.scale = std::max(target.scale, source.scale);
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	static double ContinuousQuantile(vector<double> &values, double quantile) {
		if (values.size() == 1) {
			return values[0];
		}
		auto position = quantile * static_cast<double>(values.size() - 1);
		auto lower = static_cast<idx_t>(std::floor(position));
		auto upper = std::min<idx_t>(lower + 1, values.size() - 1);
		auto fraction = position - static_cast<double>(lower);
		std::nth_element(values.begin(), values.begin() + lower, values.end());
		auto lower_value = values[lower];
		if (fraction == 0.0 || upper == lower) {
			return lower_value;
		}
		auto upper_value = *std::min_element(values.begin() + upper, values.end());
		return (1.0 - fraction) * lower_value + fraction * upper_value;
	}

	static void AddToSum(double value, double &sum, double &correction) {
		auto adjusted = value - correction;
		auto next = sum + adjusted;
		correction = (next - sum) - adjusted;
		sum = next;
	}

	template <class STATE>
	static bool Prepare(STATE &state, AggregateFinalizeData &finalize_data) {
		if (!state.values || state.values->empty()) {
			finalize_data.ReturnNull();
			return false;
		}
		return true;
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.values;
		state.values = nullptr;
	}
};

template <bool WINSORIZE>
struct RobustMeanOperation : public RobustStatisticsOperationBase {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double lower_quantile, double upper_quantile) {
		if (!std::isfinite(value)) {
			throw InvalidInputException("Robust mean values must be finite");
		}
		if (!std::isfinite(lower_quantile) || !std::isfinite(upper_quantile) || lower_quantile < 0.0 ||
		    upper_quantile > 1.0 || lower_quantile > upper_quantile) {
			throw InvalidInputException("Robust mean quantiles must satisfy 0 <= lower_q <= upper_q <= 1");
		}
		UpdateParameters(state, lower_quantile, upper_quantile);
		state.scale = std::max(state.scale, std::fabs(value));
		state.values->push_back(value);
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!Prepare(state, finalize_data)) {
			return;
		}
		auto lower = ContinuousQuantile(*state.values, state.first_parameter);
		auto upper = ContinuousQuantile(*state.values, state.second_parameter);
		double sum = 0.0;
		double correction = 0.0;
		idx_t count = 0;
		for (auto value : *state.values) {
			if (WINSORIZE) {
				AddToSum(std::max(lower, std::min(value, upper)) / state.scale, sum, correction);
				count++;
			} else if (value >= lower && value <= upper) {
				AddToSum(value / state.scale, sum, correction);
				count++;
			}
		}
		if (count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = (sum / static_cast<double>(count)) * state.scale;
	}
};

struct HistoricalCvarOperation : public RobustStatisticsOperationBase {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double confidence, double loss_positive) {
		if (!std::isfinite(value)) {
			throw InvalidInputException("CVaR returns must be finite");
		}
		if (!std::isfinite(confidence) || confidence <= 0.0 || confidence >= 1.0) {
			throw InvalidInputException("CVaR confidence must be finite and in (0, 1)");
		}
		if (loss_positive != 0.0 && loss_positive != 1.0) {
			throw InvalidInputException("CVaR loss-positive flag must be boolean");
		}
		UpdateParameters(state, confidence, loss_positive);
		state.scale = std::max(state.scale, std::fabs(value));
		state.values->push_back(value);
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!Prepare(state, finalize_data)) {
			return;
		}
		auto threshold = ContinuousQuantile(*state.values, 1.0 - state.first_parameter);
		double sum = 0.0;
		double correction = 0.0;
		idx_t count = 0;
		for (auto value : *state.values) {
			if (value <= threshold) {
				AddToSum(value / state.scale, sum, correction);
				count++;
			}
		}
		auto tail_mean = (sum / static_cast<double>(count)) * state.scale;
		target = state.second_parameter == 1.0 ? -tail_mean : tail_mean;
	}
};

struct WeightedMomentsState {
	double weight_sum;
	double mean;
	double m2;
	double ddof;
	bool parameters_set;
};

template <bool RETURN_MEAN>
struct WeightedMomentsOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.weight_sum = 0.0;
		state.mean = 0.0;
		state.m2 = 0.0;
		state.ddof = 0.0;
		state.parameters_set = false;
	}

	template <class STATE>
	static void UpdateParameters(STATE &state, double ddof) {
		if (state.parameters_set && state.ddof != ddof) {
			throw InvalidInputException("Weighted variance ddof must be constant within a group");
		}
		state.ddof = ddof;
		state.parameters_set = true;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value, double weight, double ddof) {
		if (!std::isfinite(value) || !std::isfinite(weight)) {
			throw InvalidInputException("Weighted values and weights must be finite");
		}
		if (weight < 0.0) {
			throw InvalidInputException("Weighted statistics require non-negative weights");
		}
		if (!std::isfinite(ddof) || ddof < 0.0) {
			throw InvalidInputException("Weighted variance ddof must be non-negative and finite");
		}
		UpdateParameters(state, ddof);
		if (weight == 0.0) {
			return;
		}
		if (state.weight_sum == 0.0) {
			state.weight_sum = weight;
			state.mean = value;
			return;
		}
		auto combined_weight = state.weight_sum + weight;
		auto delta = value - state.mean;
		state.mean += delta * (weight / combined_weight);
		if (!RETURN_MEAN) {
			state.m2 += weight * delta * (value - state.mean);
		}
		state.weight_sum = combined_weight;
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.parameters_set) {
			return;
		}
		UpdateParameters(target, source.ddof);
		if (source.weight_sum == 0.0) {
			return;
		}
		if (target.weight_sum == 0.0) {
			target.weight_sum = source.weight_sum;
			target.mean = source.mean;
			target.m2 = source.m2;
			return;
		}
		auto combined_weight = target.weight_sum + source.weight_sum;
		auto delta = source.mean - target.mean;
		if (!RETURN_MEAN) {
			target.m2 += source.m2 + delta * (delta * (source.weight_sum / combined_weight)) * target.weight_sum;
		}
		target.mean += delta * (source.weight_sum / combined_weight);
		target.weight_sum = combined_weight;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!std::isfinite(state.weight_sum) || !std::isfinite(state.mean) ||
		    (!RETURN_MEAN && !std::isfinite(state.m2)) || state.weight_sum <= 0.0 ||
		    (!RETURN_MEAN && state.weight_sum <= state.ddof)) {
			finalize_data.ReturnNull();
			return;
		}
		target = RETURN_MEAN ? state.mean : std::max(0.0, state.m2) / (state.weight_sum - state.ddof);
	}
};
