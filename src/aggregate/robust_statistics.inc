// History-keeping statistics: trimmed/winsorized means and tail risk (VaR/CVaR).
// Values are retained for exact order statistics; windowed use rebuilds a frame
// into one reusable local state instead of combining per-row histories.
struct HistoryState {
	vector<double> *values;
	FinWindowAux *window;
	double parameters[3];
	bool parameters_set;
	bool invalid;
};

struct HistoryOperationBase : public FinOperationDefaults {
	static constexpr bool VALUE_REPLAY = true;
	static constexpr bool ORDER_DEPENDENT = false;
	static constexpr bool WINDOW_INCREMENTAL = true;
	static constexpr idx_t REQUIRED_ARGS = 1;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<double>();
		state.window = nullptr;
		WindowReset(state);
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		state.values->clear();
		state.parameters_set = false;
		state.invalid = false;
	}

	template <class STATE>
	static void SetParameters(STATE &state, const double (&parameters)[3], const char *name) {
		if (state.parameters_set && (state.parameters[0] != parameters[0] || state.parameters[1] != parameters[1] ||
		                             state.parameters[2] != parameters[2])) {
			throw InvalidInputException("%s: parameters must be constant within a group", name);
		}
		state.parameters[0] = parameters[0];
		state.parameters[1] = parameters[1];
		state.parameters[2] = parameters[2];
		state.parameters_set = true;
	}

	template <class STATE>
	static void AddValue(STATE &state, double value) {
		if (!std::isfinite(value)) {
			state.invalid = true;
			return;
		}
		state.values->push_back(value);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.parameters_set) {
			return;
		}
		if (target.parameters_set &&
		    (target.parameters[0] != source.parameters[0] || target.parameters[1] != source.parameters[1] ||
		     target.parameters[2] != source.parameters[2])) {
			throw InvalidInputException("Aggregate parameters must be constant within a group");
		}
		target.parameters[0] = source.parameters[0];
		target.parameters[1] = source.parameters[1];
		target.parameters[2] = source.parameters[2];
		target.parameters_set = true;
		target.invalid = target.invalid || source.invalid;
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class STATE>
	static bool Prepare(STATE &state, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.values->empty()) {
			finalize_data.ReturnNull();
			return false;
		}
		return true;
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.values;
		state.values = nullptr;
		delete state.window;
		state.window = nullptr;
	}
};

template <bool WINSORIZE>
struct RobustMeanOperation : public HistoryOperationBase {
	static const char *Name() {
		return WINSORIZE ? "fin_winsorized_mean" : "fin_trimmed_mean";
	}

	static void ValidateParameter(idx_t, double quantile, bool) {
		if (!std::isfinite(quantile) || quantile < 0.0 || quantile > 1.0) {
			throw InvalidInputException("%s: quantile bounds must satisfy 0 <= lower_q <= upper_q <= 1", Name());
		}
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double parameters[3] = {0.05, 0.95, 0.0};
		if (input_count > 1) {
			parameters[0] = row.v[1];
			parameters[1] = row.v[2];
		}
		if (!state.parameters_set || state.parameters[0] != parameters[0] || state.parameters[1] != parameters[1]) {
			ValidateParameter(1, parameters[0], true);
			ValidateParameter(2, parameters[1], true);
			if (parameters[0] > parameters[1]) {
				throw InvalidInputException("%s: quantile bounds must satisfy 0 <= lower_q <= upper_q <= 1", Name());
			}
		}
		SetParameters(state, parameters, Name());
		AddValue(state, row.v[0]);
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!Prepare(state, finalize_data)) {
			return;
		}
		auto &values = *state.values;
		auto lower = FinContinuousQuantile(values, state.parameters[0]);
		auto upper = FinContinuousQuantile(values, state.parameters[1]);
		double scale = 1.0;
		for (auto value : values) {
			scale = std::max(scale, std::fabs(value));
		}
		FinSum sum;
		sum.Reset();
		idx_t count = 0;
		for (auto value : values) {
			if (WINSORIZE) {
				sum.Add(std::max(lower, std::min(value, upper)) / scale);
				count++;
			} else if (value >= lower && value <= upper) {
				sum.Add(value / scale);
				count++;
			}
		}
		if (count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = (sum.Value() / static_cast<double>(count)) * scale;
	}
};

enum class TailRiskMethod : uint8_t { HISTORICAL = 1, PARAMETRIC = 2, CORNISH_FISHER = 3 };

// Value at risk and expected shortfall at confidence c with tail probability
// q = 1 - c. Historical uses the linear-interpolation q-quantile (quantile_cont)
// and, for CVaR, the mean of observations at or below it. Parametric uses the
// sample mean and sample standard deviation (ddof 1) with a normal quantile;
// Cornish-Fisher adjusts that quantile with population skewness and excess
// kurtosis (Zangari 1996, Favre and Galeano 2002).
template <bool CVAR>
struct TailRiskOperation : public HistoryOperationBase {
	static const char *Name() {
		return CVAR ? "fin_cvar" : "fin_var";
	}

	static double ParseText(idx_t, string_t text) {
		if (FinTextEquals(text, "historical")) {
			return static_cast<double>(TailRiskMethod::HISTORICAL);
		}
		if (FinTextEquals(text, "parametric") || FinTextEquals(text, "gaussian") || FinTextEquals(text, "normal")) {
			return static_cast<double>(TailRiskMethod::PARAMETRIC);
		}
		if (!CVAR && (FinTextEquals(text, "cornish_fisher") || FinTextEquals(text, "modified"))) {
			return static_cast<double>(TailRiskMethod::CORNISH_FISHER);
		}
		throw InvalidInputException(CVAR ? "fin_cvar: unknown method '%s'; supported methods are 'historical' and "
		                                   "'parametric'"
		                                 : "fin_var: unknown method '%s'; supported methods are 'historical', "
		                                   "'parametric' and 'cornish_fisher'",
		                            text.GetString());
	}

	static void ValidateParameter(idx_t column, double value, bool valid) {
		if (column == 1 && (!std::isfinite(value) || value <= 0.0 || value >= 1.0)) {
			throw InvalidInputException("%s: confidence must be finite and in (0, 1)", Name());
		}
		if (!valid) {
			throw InvalidInputException("%s: %s must not be NULL", Name(), column == 2 ? "method" : "loss_positive");
		}
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double parameters[3] = {0.95, static_cast<double>(TailRiskMethod::HISTORICAL), 1.0};
		for (idx_t c = 1; c < input_count; c++) {
			parameters[c - 1] = row.valid[c] ? row.v[c] : std::numeric_limits<double>::quiet_NaN();
		}
		if (!state.parameters_set || state.parameters[0] != parameters[0] || state.parameters[1] != parameters[1] ||
		    state.parameters[2] != parameters[2]) {
			for (idx_t c = 1; c < input_count; c++) {
				ValidateParameter(c, parameters[c - 1], row.valid[c]);
			}
		}
		SetParameters(state, parameters, Name());
		AddValue(state, row.v[0]);
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!Prepare(state, finalize_data)) {
			return;
		}
		auto &values = *state.values;
		auto tail = 1.0 - state.parameters[0];
		auto method = static_cast<TailRiskMethod>(static_cast<uint8_t>(state.parameters[1]));
		double result;
		if (method == TailRiskMethod::HISTORICAL) {
			auto threshold = FinContinuousQuantile(values, tail);
			if (!CVAR) {
				result = threshold;
			} else {
				// Running mean of the tail avoids overflow for huge finite inputs.
				double mean = 0.0;
				double count = 0.0;
				for (auto value : values) {
					if (value <= threshold) {
						count += 1.0;
						mean += (value - mean) / count;
					}
				}
				result = mean;
			}
		} else {
			auto n = static_cast<double>(values.size());
			if (values.size() < 2) {
				finalize_data.ReturnNull();
				return;
			}
			FinSum sum;
			sum.Reset();
			for (auto value : values) {
				sum.Add(value);
			}
			auto mean = sum.Value() / n;
			FinSum m2, m3, m4;
			m2.Reset();
			m3.Reset();
			m4.Reset();
			for (auto value : values) {
				auto d = value - mean;
				m2.Add(d * d);
				m3.Add(d * d * d);
				m4.Add(d * d * d * d);
			}
			auto sd = std::sqrt(m2.Value() / (n - 1.0));
			auto z = FinNormalQuantile(tail);
			if (method == TailRiskMethod::CORNISH_FISHER && m2.Value() > 0.0) {
				auto pm2 = m2.Value() / n;
				auto skew = (m3.Value() / n) / std::pow(pm2, 1.5);
				auto kurt = (m4.Value() / n) / (pm2 * pm2) - 3.0;
				z = z + (z * z - 1.0) * skew / 6.0 + (z * z * z - 3.0 * z) * kurt / 24.0 -
				    (2.0 * z * z * z - 5.0 * z) * skew * skew / 36.0;
			}
			result = CVAR ? mean - sd * FinNormalPdf(z) / tail : mean + sd * z;
		}
		result = state.parameters[2] != 0.0 ? -result : result;
		if (!std::isfinite(result)) {
			finalize_data.ReturnNull();
			return;
		}
		target = result;
	}
};

struct WeightedMomentsState {
	double weight_sum;
	double mean;
	double m2;
	double ddof;
	bool parameters_set;
	bool invalid;
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
		state.invalid = false;
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
		if (!std::isfinite(ddof) || ddof < 0.0) {
			throw InvalidInputException("fin_weighted_var: ddof must be non-negative and finite");
		}
		UpdateParameters(state, ddof);
		if (!std::isfinite(value) || !std::isfinite(weight) || weight < 0.0) {
			// Non-finite observations or negative weights make the group's moments undefined.
			state.invalid = true;
			return;
		}
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
		target.invalid = target.invalid || source.invalid;
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
		if (state.invalid || !std::isfinite(state.weight_sum) || !std::isfinite(state.mean) ||
		    (!RETURN_MEAN && !std::isfinite(state.m2)) || state.weight_sum <= 0.0 ||
		    (!RETURN_MEAN && state.weight_sum <= state.ddof)) {
			finalize_data.ReturnNull();
			return;
		}
		target = RETURN_MEAN ? state.mean : std::max(0.0, state.m2) / (state.weight_sum - state.ddof);
	}
};
