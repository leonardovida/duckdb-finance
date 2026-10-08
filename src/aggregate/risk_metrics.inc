// Core return/risk metrics as fixed-size native aggregates. Their states merge
// exactly, so DuckDB's segment tree evaluates them in sliding window frames with
// the same cost profile as stddev_samp.
//
// Rate convention: every risk-free rate, MAR or threshold argument is an ANNUAL
// decimal rate, converted to a per-period rate geometrically,
// (1 + rate)^(1 / annualization) - 1, before it is compared with the periodic
// returns.

struct RiskMomentsState {
	FinMoments moments;
	FinSum downside;
	double annualization;
	double ddof;
	bool parameters_set;
	bool invalid;
	FinPeriodicRateCache rate_cache;
};

enum class RiskMomentsKind : uint8_t { VOLATILITY, SHARPE, DOWNSIDE_DEVIATION };

template <RiskMomentsKind KIND>
struct RiskMomentsOperation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 1;
	static constexpr bool ORDER_DEPENDENT = false;
	static constexpr bool WINDOW_INCREMENTAL = true;

	static const char *Name() {
		switch (KIND) {
		case RiskMomentsKind::VOLATILITY:
			return "fin_volatility";
		case RiskMomentsKind::SHARPE:
			return "fin_sharpe";
		default:
			return "fin_downside_deviation";
		}
	}

	// Argument layout: volatility (r, annualization, ddof); sharpe and downside
	// deviation (r, rate, annualization).
	static constexpr idx_t ANNUALIZATION_COLUMN = KIND == RiskMomentsKind::VOLATILITY ? 1 : 2;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.moments.Reset();
		state.downside.Reset();
		state.annualization = DEFAULT_ANNUALIZATION;
		state.ddof = 1.0;
		state.parameters_set = false;
		state.invalid = false;
		state.rate_cache = FinPeriodicRateCache();
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		Initialize(state);
	}

	static void ValidateParameter(idx_t column, double value, bool valid) {
		if (column == ANNUALIZATION_COLUMN) {
			if (!valid || !(value > 0.0) || !std::isfinite(value)) {
				throw InvalidInputException("%s: annualization must be positive and finite", Name());
			}
		} else if (KIND == RiskMomentsKind::VOLATILITY && column == 2) {
			if (!valid || !(value >= 0.0) || !std::isfinite(value)) {
				throw InvalidInputException("%s: ddof must be non-negative and finite", Name());
			}
		} else if (valid && (!std::isfinite(value) || value <= -1.0)) {
			throw InvalidInputException("%s: annual rate must be finite and greater than -1", Name());
		}
	}

	template <class STATE>
	static void SetParameters(STATE &state, double annualization, double ddof) {
		if (state.parameters_set) {
			if (state.annualization == annualization && state.ddof == ddof) {
				return;
			}
			throw InvalidInputException("%s: annualization%s must be constant within a group", Name(),
			                            KIND == RiskMomentsKind::VOLATILITY ? " and ddof" : "");
		}
		ValidateParameter(ANNUALIZATION_COLUMN, annualization, true);
		if (KIND == RiskMomentsKind::VOLATILITY) {
			ValidateParameter(2, ddof, true);
		}
		state.annualization = annualization;
		state.ddof = ddof;
		state.parameters_set = true;
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		auto annualization = DEFAULT_ANNUALIZATION;
		auto ddof = 1.0;
		if (input_count > ANNUALIZATION_COLUMN) {
			annualization = row.valid[ANNUALIZATION_COLUMN] ? row.v[ANNUALIZATION_COLUMN]
			                                                : std::numeric_limits<double>::quiet_NaN();
		}
		if (KIND == RiskMomentsKind::VOLATILITY && input_count > 2) {
			ddof = row.valid[2] ? row.v[2] : std::numeric_limits<double>::quiet_NaN();
		}
		SetParameters(state, annualization, ddof);
		auto value = row.v[0];
		if (KIND != RiskMomentsKind::VOLATILITY && input_count > 1) {
			// Rows with a NULL rate are skipped; an invalid rate makes the group NULL.
			if (row.v[1] != 0.0) {
				value -= state.rate_cache.Get(row.v[1], annualization);
			}
		}
		if (!std::isfinite(value)) {
			state.invalid = true;
			return;
		}
		if (KIND == RiskMomentsKind::DOWNSIDE_DEVIATION) {
			state.moments.count += 1.0;
			if (value < 0.0) {
				state.downside.Add(value * value);
			}
			return;
		}
		state.moments.Add(value);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.invalid = target.invalid || source.invalid;
		if (!source.parameters_set) {
			return;
		}
		if (target.parameters_set &&
		    (target.annualization != source.annualization || target.ddof != source.ddof)) {
			throw InvalidInputException("%s: annualization must be constant within a group", Name());
		}
		target.annualization = source.annualization;
		target.ddof = source.ddof;
		target.parameters_set = true;
		if (KIND == RiskMomentsKind::DOWNSIDE_DEVIATION) {
			target.moments.count += source.moments.count;
			target.downside.Merge(source.downside);
			return;
		}
		target.moments.Merge(source.moments);
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		auto n = state.moments.count;
		double result;
		if (state.invalid || n == 0.0) {
			finalize_data.ReturnNull();
			return;
		}
		auto root_annualization = std::sqrt(state.annualization);
		switch (KIND) {
		case RiskMomentsKind::VOLATILITY:
			if (n <= state.ddof) {
				finalize_data.ReturnNull();
				return;
			}
			result = std::sqrt(std::max(0.0, state.moments.m2) / (n - state.ddof)) * root_annualization;
			break;
		case RiskMomentsKind::SHARPE: {
			if (n < 2.0) {
				finalize_data.ReturnNull();
				return;
			}
			auto sd = std::sqrt(std::max(0.0, state.moments.m2) / (n - 1.0));
			if (sd == 0.0) {
				finalize_data.ReturnNull();
				return;
			}
			result = state.moments.mean / sd * root_annualization;
			break;
		}
		default:
			result = std::sqrt(std::max(0.0, state.downside.Value()) / n) * root_annualization;
			break;
		}
		if (!std::isfinite(result)) {
			finalize_data.ReturnNull();
			return;
		}
		target = result;
	}

	template <class STATE>
	static void Destroy(STATE &, AggregateInputData &) {
	}
};

//===--------------------------------------------------------------------===//
// Total return
//===--------------------------------------------------------------------===//
// Compounds in log space: simple returns via sum(log1p(r)), log returns via
// sum(r), then expm1. Avoids overflow of the intermediate wealth product.
enum class ReturnMethod : uint8_t { SIMPLE = 1, LOG = 2 };

struct TotalReturnState {
	FinSum log_sum;
	idx_t count;
	double method;
	bool method_set;
	bool total_loss;
	bool invalid;
};

struct TotalReturnOperation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 1;
	static constexpr bool ORDER_DEPENDENT = false;
	static constexpr bool WINDOW_INCREMENTAL = true;

	static double ParseText(idx_t, string_t text) {
		if (FinTextEquals(text, "simple") || FinTextEquals(text, "arithmetic") || FinTextEquals(text, "pct") ||
		    FinTextEquals(text, "percent")) {
			return static_cast<double>(ReturnMethod::SIMPLE);
		}
		if (FinTextEquals(text, "log") || FinTextEquals(text, "ln") || FinTextEquals(text, "continuous")) {
			return static_cast<double>(ReturnMethod::LOG);
		}
		throw InvalidInputException("fin_total_return: unknown method '%s'; supported methods are 'simple' and 'log'",
		                            text.GetString());
	}

	static void ValidateParameter(idx_t, double, bool valid) {
		if (!valid) {
			throw InvalidInputException("fin_total_return: method must not be NULL");
		}
	}

	template <class STATE>
	static void Initialize(STATE &state) {
		state.log_sum.Reset();
		state.count = 0;
		state.method = static_cast<double>(ReturnMethod::SIMPLE);
		state.method_set = false;
		state.total_loss = false;
		state.invalid = false;
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		Initialize(state);
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		auto method = static_cast<double>(ReturnMethod::SIMPLE);
		if (input_count > 1) {
			ValidateParameter(1, row.v[1], row.valid[1]);
			method = row.v[1];
		}
		if (state.method_set && state.method != method) {
			throw InvalidInputException("fin_total_return: method must be constant within a group");
		}
		state.method = method;
		state.method_set = true;
		auto value = row.v[0];
		state.count++;
		if (!std::isfinite(value)) {
			state.invalid = true;
			return;
		}
		if (method == static_cast<double>(ReturnMethod::LOG)) {
			state.log_sum.Add(value);
		} else if (value < -1.0) {
			state.invalid = true;
		} else if (value == -1.0) {
			state.total_loss = true;
		} else {
			state.log_sum.Add(std::log1p(value));
		}
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.method_set) {
			return;
		}
		if (target.method_set && target.method != source.method) {
			throw InvalidInputException("fin_total_return: method must be constant within a group");
		}
		target.method = source.method;
		target.method_set = true;
		target.count += source.count;
		target.total_loss = target.total_loss || source.total_loss;
		target.invalid = target.invalid || source.invalid;
		target.log_sum.Merge(source.log_sum);
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		if (state.total_loss) {
			target = -1.0;
			return;
		}
		auto result = std::expm1(state.log_sum.Value());
		if (!std::isfinite(result)) {
			finalize_data.ReturnNull();
			return;
		}
		target = result;
	}

	template <class STATE>
	static void Destroy(STATE &, AggregateInputData &) {
	}
};

//===--------------------------------------------------------------------===//
// Beta
//===--------------------------------------------------------------------===//
// OLS slope of r on benchmark_r over rows where both are non-NULL:
// cov(r, b) / var(b), with single-pass co-moments merged pairwise.
struct BetaState {
	double count;
	double mean_x;
	double mean_y;
	double cxy;
	double m2x;
	bool invalid;
};

struct BetaOperation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 2;
	static constexpr bool ORDER_DEPENDENT = false;
	static constexpr bool WINDOW_INCREMENTAL = true;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.count = state.mean_x = state.mean_y = state.cxy = state.m2x = 0.0;
		state.invalid = false;
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		Initialize(state);
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t) {
		auto y = row.v[0];
		auto x = row.v[1];
		if (!std::isfinite(x) || !std::isfinite(y)) {
			state.invalid = true;
			return;
		}
		state.count += 1.0;
		auto dx = x - state.mean_x;
		state.mean_x += dx / state.count;
		state.mean_y += (y - state.mean_y) / state.count;
		state.cxy += dx * (y - state.mean_y);
		state.m2x += dx * (x - state.mean_x);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.invalid = target.invalid || source.invalid;
		if (source.count == 0.0) {
			return;
		}
		if (target.count == 0.0) {
			auto invalid = target.invalid;
			target = source;
			target.invalid = invalid;
			return;
		}
		auto total = target.count + source.count;
		auto dx = source.mean_x - target.mean_x;
		auto dy = source.mean_y - target.mean_y;
		auto weight = target.count * source.count / total;
		target.cxy += source.cxy + dx * dy * weight;
		target.m2x += source.m2x + dx * dx * weight;
		target.mean_x += dx * (source.count / total);
		target.mean_y += dy * (source.count / total);
		target.count = total;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.count < 2.0 || !(state.m2x > 0.0)) {
			finalize_data.ReturnNull();
			return;
		}
		auto result = state.cxy / state.m2x;
		if (!std::isfinite(result)) {
			finalize_data.ReturnNull();
			return;
		}
		target = result;
	}

	template <class STATE>
	static void Destroy(STATE &, AggregateInputData &) {
	}
};

//===--------------------------------------------------------------------===//
// GARCH(1,1) one-step-ahead variance forecast
//===--------------------------------------------------------------------===//
// Filters the ordered returns through sigma2_{t+1} = omega + alpha r_t^2 +
// beta sigma2_t starting from sigma2_1 = initial_var (default: the sample
// variance of the returns, ddof 1) and returns annualization * sigma2_{n+1}.
// The recursion is affine in the seed: sigma2_{n+1} = A + B * sigma2_1, so the
// state keeps (A, B) and ordered blocks merge as A = A_R + B_R A_L, B = B_L B_R.
struct Garch11State {
	double affine;
	double decay;
	FinMoments moments;
	double omega;
	double alpha;
	double beta;
	double initial_var;
	double annualization;
	bool parameters_set;
	bool invalid;
};

struct Garch11Operation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 1;
	static bool NullableArgument(idx_t column) {
		return column == 4;
	}
	static constexpr bool ORDER_DEPENDENT = true;
	static constexpr bool WINDOW_INCREMENTAL = true;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.affine = 0.0;
		state.decay = 1.0;
		state.moments.Reset();
		state.omega = state.alpha = state.beta = 0.0;
		state.initial_var = std::numeric_limits<double>::quiet_NaN();
		state.annualization = DEFAULT_ANNUALIZATION;
		state.parameters_set = false;
		state.invalid = false;
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		Initialize(state);
	}

	static void ValidateParameter(idx_t column, double value, bool valid) {
		switch (column) {
		case 1:
		case 2:
		case 3:
			if (!valid || !std::isfinite(value) || value < 0.0) {
				throw InvalidInputException("fin_garch11_forecast: omega, alpha and beta must be finite and non-negative");
			}
			break;
		case 4:
			if (valid && (!std::isfinite(value) || value < 0.0)) {
				throw InvalidInputException("fin_garch11_forecast: initial_var must be NULL or finite and non-negative");
			}
			break;
		default:
			if (!valid || !(value > 0.0) || !std::isfinite(value)) {
				throw InvalidInputException("fin_garch11_forecast: annualization must be positive and finite");
			}
			break;
		}
	}

	static bool SameParameter(double left, double right) {
		return left == right || (std::isnan(left) && std::isnan(right));
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double parameters[5] = {row.v[1], row.v[2], row.v[3], std::numeric_limits<double>::quiet_NaN(),
		                        DEFAULT_ANNUALIZATION};
		if (input_count > 4) {
			parameters[3] = row.valid[4] ? row.v[4] : std::numeric_limits<double>::quiet_NaN();
		}
		if (input_count > 5) {
			parameters[4] = row.valid[5] ? row.v[5] : std::numeric_limits<double>::quiet_NaN();
		}
		if (!state.parameters_set || !SameParameter(state.omega, parameters[0]) ||
		    !SameParameter(state.alpha, parameters[1]) || !SameParameter(state.beta, parameters[2]) ||
		    !SameParameter(state.initial_var, parameters[3]) || !SameParameter(state.annualization, parameters[4])) {
			if (!row.valid[1] || !row.valid[2] || !row.valid[3]) {
				throw InvalidInputException("fin_garch11_forecast: omega, alpha and beta must not be NULL");
			}
			for (idx_t c = 1; c <= 3; c++) {
				ValidateParameter(c, parameters[c - 1], true);
			}
			ValidateParameter(4, parameters[3], !std::isnan(parameters[3]));
			ValidateParameter(5, parameters[4], input_count <= 5 || row.valid[5]);
			if (state.parameters_set) {
				throw InvalidInputException("fin_garch11_forecast: parameters must be constant within a group");
			}
			state.omega = parameters[0];
			state.alpha = parameters[1];
			state.beta = parameters[2];
			state.initial_var = parameters[3];
			state.annualization = parameters[4];
			state.parameters_set = true;
		}
		auto value = row.v[0];
		if (!std::isfinite(value)) {
			state.invalid = true;
			return;
		}
		state.affine = state.omega + state.alpha * value * value + state.beta * state.affine;
		state.decay *= state.beta;
		state.moments.Add(value);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.invalid = target.invalid || source.invalid;
		if (!source.parameters_set) {
			return;
		}
		if (!target.parameters_set) {
			auto invalid = target.invalid;
			target = source;
			target.invalid = invalid;
			return;
		}
		if (!SameParameter(target.omega, source.omega) || !SameParameter(target.alpha, source.alpha) ||
		    !SameParameter(target.beta, source.beta) || !SameParameter(target.initial_var, source.initial_var) ||
		    !SameParameter(target.annualization, source.annualization)) {
			throw InvalidInputException("fin_garch11_forecast: parameters must be constant within a group");
		}
		// target is the earlier block, source the later one.
		target.affine = source.affine + source.decay * target.affine;
		target.decay *= source.decay;
		target.moments.Merge(source.moments);
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.moments.count == 0.0) {
			finalize_data.ReturnNull();
			return;
		}
		auto seed = state.initial_var;
		if (std::isnan(seed)) {
			if (state.moments.count < 2.0) {
				finalize_data.ReturnNull();
				return;
			}
			seed = std::max(0.0, state.moments.m2) / (state.moments.count - 1.0);
		}
		auto variance = state.affine + (state.decay == 0.0 ? 0.0 : state.decay * seed);
		auto result = variance * state.annualization;
		if (!std::isfinite(result)) {
			finalize_data.ReturnNull();
			return;
		}
		target = result;
	}

	template <class STATE>
	static void Destroy(STATE &, AggregateInputData &) {
	}
};

//===--------------------------------------------------------------------===//
// Yang-Zhang (2000) volatility
//===--------------------------------------------------------------------===//
// For ordered bars 1..N, the n = N - 1 periods t = 2..N use the overnight
// return o_t = ln(O_t / C_{t-1}), open-to-close c_t = ln(C_t / O_t) and the
// Rogers-Satchell term rs_t. sigma^2 = var(o) + k var(c) + (1 - k) mean(rs) with
// sample variances and k = 0.34 / (1.34 + (n + 1) / (n - 1)); the result is
// sqrt(annualization * sigma^2). Bars with non-positive prices, high below
// low, or open/close outside [low, high] make the group NULL.
struct YangZhangState {
	bool has_first;
	bool invalid;
	double first_open;
	double first_c;
	double first_rs;
	double last_close;
	FinMoments overnight;
	FinMoments open_close;
	FinSum rogers_satchell;
	double annualization;
	bool annualization_set;
};

struct YangZhangOperation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 4;
	static constexpr bool ORDER_DEPENDENT = true;
	static constexpr bool WINDOW_INCREMENTAL = true;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.has_first = false;
		state.invalid = false;
		state.first_open = state.first_c = state.first_rs = state.last_close = 0.0;
		state.overnight.Reset();
		state.open_close.Reset();
		state.rogers_satchell.Reset();
		state.annualization = DEFAULT_ANNUALIZATION;
		state.annualization_set = false;
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		Initialize(state);
	}

	static void ValidateParameter(idx_t, double value, bool valid) {
		if (!valid || !(value > 0.0) || !std::isfinite(value)) {
			throw InvalidInputException("fin_yang_zhang_vol: annualization must be positive and finite");
		}
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		if (input_count > 4) {
			auto annualization = row.valid[4] ? row.v[4] : std::numeric_limits<double>::quiet_NaN();
			if (!state.annualization_set || annualization != state.annualization) {
				ValidateParameter(4, annualization, row.valid[4]);
				if (state.annualization_set) {
					throw InvalidInputException("fin_yang_zhang_vol: annualization must be constant within a group");
				}
				state.annualization = annualization;
				state.annualization_set = true;
			}
		}
		auto open = row.v[0], high = row.v[1], low = row.v[2], close = row.v[3];
		if (!(open > 0.0 && high > 0.0 && low > 0.0 && close > 0.0) || !std::isfinite(open) ||
		    !std::isfinite(high) || !std::isfinite(low) || !std::isfinite(close) || high < low || open > high ||
		    open < low || close > high || close < low) {
			state.invalid = true;
			return;
		}
		auto c = std::log(close / open);
		auto rs = std::log(high / close) * std::log(high / open) + std::log(low / close) * std::log(low / open);
		if (!state.has_first) {
			state.has_first = true;
			state.first_open = open;
			state.first_c = c;
			state.first_rs = rs;
		} else {
			state.overnight.Add(std::log(open / state.last_close));
			state.open_close.Add(c);
			state.rogers_satchell.Add(rs);
		}
		state.last_close = close;
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.invalid = target.invalid || source.invalid;
		if (source.annualization_set) {
			if (target.annualization_set && target.annualization != source.annualization) {
				throw InvalidInputException("fin_yang_zhang_vol: annualization must be constant within a group");
			}
			target.annualization = source.annualization;
			target.annualization_set = true;
		}
		if (!source.has_first) {
			return;
		}
		if (!target.has_first) {
			auto invalid = target.invalid;
			target = source;
			target.invalid = invalid;
			return;
		}
		// target precedes source: the source's first bar now has a previous close.
		target.overnight.Add(std::log(source.first_open / target.last_close));
		target.open_close.Add(source.first_c);
		target.rogers_satchell.Add(source.first_rs);
		target.overnight.Merge(source.overnight);
		target.open_close.Merge(source.open_close);
		target.rogers_satchell.Merge(source.rogers_satchell);
		target.last_close = source.last_close;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		auto n = state.overnight.count;
		if (state.invalid || n < 2.0) {
			finalize_data.ReturnNull();
			return;
		}
		auto k = 0.34 / (1.34 + (n + 1.0) / (n - 1.0));
		auto variance = std::max(0.0, state.overnight.m2) / (n - 1.0) +
		                k * std::max(0.0, state.open_close.m2) / (n - 1.0) +
		                (1.0 - k) * state.rogers_satchell.Value() / n;
		if (!(variance >= 0.0)) {
			finalize_data.ReturnNull();
			return;
		}
		auto result = std::sqrt(state.annualization * variance);
		if (!std::isfinite(result)) {
			finalize_data.ReturnNull();
			return;
		}
		target = result;
	}

	template <class STATE>
	static void Destroy(STATE &, AggregateInputData &) {
	}
};
