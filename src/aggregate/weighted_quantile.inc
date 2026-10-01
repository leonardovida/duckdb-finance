enum class WeightedQuantileMethod : uint8_t { LINEAR, LOWER, HIGHER, NEAREST, MIDPOINT, INVERTED_CDF };

static WeightedQuantileMethod ParseWeightedQuantileMethod(const string &method) {
	// The documented lowercase spellings are the hot path; retain case-insensitive
	// compatibility without allocating a lowercase string for every observation.
	if (method == "linear") {
		return WeightedQuantileMethod::LINEAR;
	}
	if (method == "lower") {
		return WeightedQuantileMethod::LOWER;
	}
	if (method == "higher") {
		return WeightedQuantileMethod::HIGHER;
	}
	if (method == "nearest") {
		return WeightedQuantileMethod::NEAREST;
	}
	if (method == "midpoint") {
		return WeightedQuantileMethod::MIDPOINT;
	}
	if (method == "inverted_cdf") {
		return WeightedQuantileMethod::INVERTED_CDF;
	}
	auto normalized = StringUtil::Lower(method);
	if (normalized != method) {
		return ParseWeightedQuantileMethod(normalized);
	}
	throw InvalidInputException("Unknown weighted quantile method '%s'", method);
}

struct WeightedQuantileState {
	vector<std::pair<double, double>> *values;
	double quantile;
	WeightedQuantileMethod method;
	bool parameters_set;
	double weight_scale;
};

struct WeightedQuantileOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<std::pair<double, double>>();
		state.quantile = 0.5;
		state.method = WeightedQuantileMethod::LINEAR;
		state.parameters_set = false;
		state.weight_scale = 0.0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value, double weight, double quantile, WeightedQuantileMethod parsed_method) {
		if (!std::isfinite(value) || !std::isfinite(weight)) {
			throw InvalidInputException("Weighted quantile values and weights must be finite");
		}
		if (weight < 0.0) {
			throw InvalidInputException("Weighted quantile weights must be non-negative");
		}
		if (!std::isfinite(quantile) || quantile < 0.0 || quantile > 1.0) {
			throw InvalidInputException("Weighted quantile must be finite and in [0, 1]");
		}
		if (state.parameters_set && (state.quantile != quantile || state.method != parsed_method)) {
			throw InvalidInputException("Weighted quantile and method must be constant within a group");
		}
		state.quantile = quantile;
		state.method = parsed_method;
		state.parameters_set = true;
		if (weight > 0.0) {
			state.values->push_back({value, weight});
			state.weight_scale = std::max(state.weight_scale, weight);
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
		target.weight_scale = std::max(target.weight_scale, source.weight_scale);
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.values || state.values->empty()) {
			finalize_data.ReturnNull();
			return;
		}
		auto first_value = state.values->front().first;
		if (std::all_of(state.values->begin(), state.values->end(),
		                [first_value](const auto &entry) { return entry.first == first_value; })) {
			target = first_value;
			return;
		}
		if (state.quantile == 0.0 || state.quantile == 1.0) {
			auto extrema = std::minmax_element(state.values->begin(), state.values->end(),
			                                  [](const auto &lhs, const auto &rhs) { return lhs.first < rhs.first; });
			target = state.quantile == 0.0 ? extrema.first->first : extrema.second->first;
			return;
		}
		std::sort(state.values->begin(), state.values->end(),
		          [](const auto &lhs, const auto &rhs) { return lhs.first < rhs.first; });
		// Canonicalize weights only inside value ties. Distinct observations need
		// a single value comparison in the full sort, while interpolation knots
		// remain independent of the input order when tied weights differ.
		auto begin = state.values->begin();
		while (begin != state.values->end()) {
			auto end = begin + 1;
			while (end != state.values->end() && end->first == begin->first) {
				end++;
			}
			if (end - begin > 1) {
				std::sort(begin, end, [](const auto &lhs, const auto &rhs) { return lhs.second < rhs.second; });
			}
			begin = end;
		}
		auto inverse_scale = 1.0 / state.weight_scale;
		auto normalize_weight = [&](double weight) {
			if (weight == state.weight_scale) {
				return 1.0;
			}
			return std::isfinite(inverse_scale) ? weight * inverse_scale : weight / state.weight_scale;
		};
		double total_weight = 0.0;
		double correction = 0.0;
		for (const auto &entry : *state.values) {
			AddCompensated(normalize_weight(entry.second), total_weight, correction);
		}

		auto target_weight = state.quantile * total_weight;
		double cumulative = 0.0;
		double previous_weight = 0.0;
		double previous_value = state.values->front().first;
		correction = 0.0;
		for (const auto &entry : *state.values) {
			AddCompensated(normalize_weight(entry.second), cumulative, correction);
			if (target_weight <= cumulative) {
				if (target_weight == cumulative) {
					target = entry.first;
					return;
				}
				if (state.method == WeightedQuantileMethod::HIGHER ||
				    state.method == WeightedQuantileMethod::INVERTED_CDF || cumulative == previous_weight) {
					target = entry.first;
				} else if (state.method == WeightedQuantileMethod::LOWER) {
					target = previous_value;
				} else if (state.method == WeightedQuantileMethod::MIDPOINT) {
					target = ConvexCombination(previous_value, entry.first, 0.5);
				} else if (state.method == WeightedQuantileMethod::NEAREST) {
					target = target_weight - previous_weight <= cumulative - target_weight ? previous_value : entry.first;
				} else {
					auto fraction = (target_weight - previous_weight) / (cumulative - previous_weight);
					target = ConvexCombination(previous_value, entry.first, std::min(1.0, std::max(0.0, fraction)));
				}
				return;
			}
			previous_weight = cumulative;
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
