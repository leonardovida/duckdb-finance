enum class WeightedQuantileMethod : uint8_t { LINEAR, LOWER, HIGHER, NEAREST, MIDPOINT, INVERTED_CDF };

static WeightedQuantileMethod ParseWeightedQuantileMethod(string_t method) {
	if (FinTextEquals(method, "linear")) {
		return WeightedQuantileMethod::LINEAR;
	}
	if (FinTextEquals(method, "lower")) {
		return WeightedQuantileMethod::LOWER;
	}
	if (FinTextEquals(method, "higher")) {
		return WeightedQuantileMethod::HIGHER;
	}
	if (FinTextEquals(method, "nearest")) {
		return WeightedQuantileMethod::NEAREST;
	}
	if (FinTextEquals(method, "midpoint")) {
		return WeightedQuantileMethod::MIDPOINT;
	}
	if (FinTextEquals(method, "inverted_cdf")) {
		return WeightedQuantileMethod::INVERTED_CDF;
	}
	throw InvalidInputException("fin_weighted_quantile: unknown method '%s'; supported methods are 'linear', "
	                            "'lower', 'higher', 'nearest', 'midpoint' and 'inverted_cdf'",
	                            method.GetString());
}

struct WeightedQuantileState {
	vector<std::pair<double, double>> *values;
	FinWindowAux *window;
	FinRankPartition *rank_partition;
	FinRankFrame *rank_frame;
	double quantile;
	WeightedQuantileMethod method;
	bool parameters_set;
	bool invalid;
	double weight_scale;
};

// Picks the quantile once the cumulative weight first reaches the target at an
// observation: previous_weight and previous_value describe the observation
// before it in (value, weight) order.
static double WeightedQuantilePick(WeightedQuantileMethod method, double target_weight, double previous_weight,
                                   double cumulative, double previous_value, double value) {
	if (target_weight == cumulative) {
		return value;
	}
	if (method == WeightedQuantileMethod::HIGHER || method == WeightedQuantileMethod::INVERTED_CDF ||
	    cumulative == previous_weight) {
		return value;
	}
	if (method == WeightedQuantileMethod::LOWER) {
		return previous_value;
	}
	if (method == WeightedQuantileMethod::MIDPOINT) {
		return ConvexCombination(previous_value, value, 0.5);
	}
	if (method == WeightedQuantileMethod::NEAREST) {
		return target_weight - previous_weight <= cumulative - target_weight ? previous_value : value;
	}
	auto fraction = (target_weight - previous_weight) / (cumulative - previous_weight);
	return ConvexCombination(previous_value, value, std::min(1.0, std::max(0.0, fraction)));
}

struct WeightedQuantileOperation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 3;
	static constexpr bool ORDER_DEPENDENT = false;
	static constexpr bool WINDOW_INCREMENTAL = true;
	static constexpr idx_t RANK_CONFIG_COLUMN = 2;
	static constexpr bool RANK_SCALE_MASSES = true;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<std::pair<double, double>>();
		state.window = nullptr;
		state.rank_partition = nullptr;
		state.rank_frame = nullptr;
		WindowReset(state);
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		state.values->clear();
		state.quantile = 0.5;
		state.method = WeightedQuantileMethod::LINEAR;
		state.parameters_set = false;
		state.invalid = false;
		state.weight_scale = 0.0;
	}

	static double ParseText(idx_t, string_t text) {
		return static_cast<double>(ParseWeightedQuantileMethod(text));
	}

	static void ValidateParameter(idx_t column, double value, bool valid) {
		if (column == 2 && (!std::isfinite(value) || value < 0.0 || value > 1.0)) {
			throw InvalidInputException("fin_weighted_quantile: q must be finite and in [0, 1]");
		}
		if (column == 3 && !valid) {
			throw InvalidInputException("fin_weighted_quantile: method must not be NULL");
		}
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		auto method = WeightedQuantileMethod::LINEAR;
		if (input_count > 3) {
			ValidateParameter(3, row.v[3], row.valid[3]);
			method = static_cast<WeightedQuantileMethod>(static_cast<uint8_t>(row.v[3]));
		}
		UpdateValue(state, row.v[0], row.v[1], row.v[2], method);
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value, double weight, double quantile, WeightedQuantileMethod parsed_method) {
		if (!state.parameters_set || state.quantile != quantile) {
			ValidateParameter(2, quantile, true);
		}
		if (state.parameters_set && (state.quantile != quantile || state.method != parsed_method)) {
			throw InvalidInputException("fin_weighted_quantile: q and method must be constant within a group");
		}
		state.quantile = quantile;
		state.method = parsed_method;
		state.parameters_set = true;
		if (!std::isfinite(value) || !std::isfinite(weight) || weight < 0.0) {
			// Non-finite observations or negative weights make the distribution undefined.
			state.invalid = true;
			return;
		}
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
			throw InvalidInputException("fin_weighted_quantile: q and method must be constant within a group");
		}
		target.invalid = target.invalid || source.invalid;
		target.quantile = source.quantile;
		target.method = source.method;
		target.parameters_set = true;
		target.weight_scale = std::max(target.weight_scale, source.weight_scale);
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || !state.values || state.values->empty()) {
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
				target = WeightedQuantilePick(state.method, target_weight, previous_weight, cumulative, previous_value,
				                              entry.first);
				return;
			}
			previous_weight = cumulative;
			previous_value = entry.first;
		}
		target = state.values->back().first;
	}

	// Window frames: entries are ranked by (value, weight) and the frame walk
	// below follows the grouped walk. Weights are summed in a different order, so
	// only the linear method, which is continuous where the cumulative weight
	// meets the target, uses the index; the discrete methods would pick another
	// observation at exact ties and keep the frame-by-frame evaluator.
	static FinRankEntry RankEntry(const FinRow &row, double &, double &key, double &mass) {
		key = row.v[0];
		mass = row.v[1];
		if (!std::isfinite(key) || !std::isfinite(mass) || mass < 0.0) {
			return FinRankEntry::INVALID;
		}
		return mass > 0.0 ? FinRankEntry::ENTRY : FinRankEntry::SKIP;
	}

	template <class STATE>
	static void RankConfigure(const STATE &state, double *parameters) {
		parameters[0] = state.quantile;
		parameters[1] = static_cast<double>(state.method);
	}

	static bool RankWindow(const double *parameters) {
		return static_cast<WeightedQuantileMethod>(static_cast<uint8_t>(parameters[1])) ==
		       WeightedQuantileMethod::LINEAR;
	}

	template <class T>
	static void RankFinalize(const double *parameters, const FinRankFrame &frame, T &target,
	                         AggregateFinalizeData &) {
		const auto quantile = parameters[0];
		const auto method = static_cast<WeightedQuantileMethod>(static_cast<uint8_t>(parameters[1]));
		const auto &keys = frame.partition->keys;
		const auto &masses = frame.partition->masses;
		auto minimum = frame.Select(0);
		auto maximum = frame.Select(static_cast<idx_t>(frame.total - 1));
		if (minimum == maximum || quantile == 0.0) {
			target = minimum;
			return;
		}
		if (quantile == 1.0) {
			target = maximum;
			return;
		}
		auto target_weight = quantile * frame.PrefixSum(keys.size()).Value();
		FinSum before;
		auto rank = frame.SearchMass(target_weight, before);
		if (rank >= keys.size()) {
			target = maximum;
			return;
		}
		// Equal (value, weight) rows share a rank; the target falls on its first
		// row only when that row alone reaches it.
		auto first = before;
		first.Add(masses[rank]);
		if (first.Value() < target_weight) {
			target = keys[rank];
			return;
		}
		auto below = frame.PrefixCount(rank);
		auto previous_value = below > 0 ? frame.Select(static_cast<idx_t>(below - 1)) : keys[rank];
		target = WeightedQuantilePick(method, target_weight, before.Value(), first.Value(), previous_value,
		                              keys[rank]);
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.values;
		state.values = nullptr;
		delete state.window;
		state.window = nullptr;
		delete state.rank_partition;
		state.rank_partition = nullptr;
		delete state.rank_frame;
		state.rank_frame = nullptr;
	}
};
