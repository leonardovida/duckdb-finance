enum class WeightedQuantileMethod : uint8_t { LINEAR, LOWER, HIGHER, NEAREST, MIDPOINT, INVERTED_CDF };

static WeightedQuantileMethod ParseWeightedQuantileMethod(const string &method) {
	auto normalized = StringUtil::Lower(method);
	if (normalized == "linear") {
		return WeightedQuantileMethod::LINEAR;
	}
	if (normalized == "lower") {
		return WeightedQuantileMethod::LOWER;
	}
	if (normalized == "higher") {
		return WeightedQuantileMethod::HIGHER;
	}
	if (normalized == "nearest") {
		return WeightedQuantileMethod::NEAREST;
	}
	if (normalized == "midpoint") {
		return WeightedQuantileMethod::MIDPOINT;
	}
	if (normalized == "inverted_cdf") {
		return WeightedQuantileMethod::INVERTED_CDF;
	}
	throw InvalidInputException("Unknown weighted quantile method '%s'", method);
}

struct WeightedQuantileState {
	vector<std::pair<double, double>> *values;
	double quantile;
	WeightedQuantileMethod method;
	bool parameters_set;
};

struct WeightedQuantileOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<std::pair<double, double>>();
		state.quantile = 0.5;
		state.method = WeightedQuantileMethod::LINEAR;
		state.parameters_set = false;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value, double weight, double quantile, const string &method) {
		if (!std::isfinite(value) || !std::isfinite(weight)) {
			throw InvalidInputException("Weighted quantile values and weights must be finite");
		}
		if (weight < 0.0) {
			throw InvalidInputException("Weighted quantile weights must be non-negative");
		}
		if (!std::isfinite(quantile) || quantile < 0.0 || quantile > 1.0) {
			throw InvalidInputException("Weighted quantile must be finite and in [0, 1]");
		}
		auto parsed_method = ParseWeightedQuantileMethod(method);
		if (state.parameters_set && (state.quantile != quantile || state.method != parsed_method)) {
			throw InvalidInputException("Weighted quantile and method must be constant within a group");
		}
		state.quantile = quantile;
		state.method = parsed_method;
		state.parameters_set = true;
		if (weight > 0.0) {
			state.values->push_back({value, weight});
		}
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.parameters_set) {
			return;
		}
		if (target.parameters_set &&
		    (target.quantile != source.quantile || target.method != source.method)) {
			throw InvalidInputException("Weighted quantile and method must be constant within a group");
		}
		target.quantile = source.quantile;
		target.method = source.method;
		target.parameters_set = true;
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.values || state.values->empty()) {
			finalize_data.ReturnNull();
			return;
		}
		std::sort(state.values->begin(), state.values->end(),
		          [](const auto &lhs, const auto &rhs) { return lhs.first < rhs.first; });
		double total_weight = 0.0;
		for (const auto &entry : *state.values) {
			total_weight += entry.second;
		}
		if (!std::isfinite(total_weight) || total_weight <= 0.0) {
			throw InvalidInputException("Weighted quantile requires a positive finite total weight");
		}

		auto target_weight = state.quantile * total_weight;
		double cumulative = 0.0;
		double previous_cdf = 0.0;
		double previous_value = state.values->front().first;
		for (const auto &entry : *state.values) {
			cumulative += entry.second;
			auto cdf = cumulative / total_weight;
			if (target_weight <= cumulative) {
				if (target_weight == cumulative) {
					target = entry.first;
					return;
				}
				if (state.method == WeightedQuantileMethod::HIGHER ||
				    state.method == WeightedQuantileMethod::INVERTED_CDF || cdf == previous_cdf) {
					target = entry.first;
				} else if (state.method == WeightedQuantileMethod::LOWER) {
					target = previous_value;
				} else if (state.method == WeightedQuantileMethod::MIDPOINT) {
					target = (previous_value + entry.first) / 2.0;
				} else if (state.method == WeightedQuantileMethod::NEAREST) {
					target = state.quantile - previous_cdf <= cdf - state.quantile ? previous_value : entry.first;
				} else {
					auto fraction = (state.quantile - previous_cdf) / (cdf - previous_cdf);
					target = previous_value + fraction * (entry.first - previous_value);
				}
				return;
			}
			previous_cdf = cdf;
			previous_value = entry.first;
		}
		target = state.values->back().first;
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.values;
		state.values = nullptr;
	}
};
