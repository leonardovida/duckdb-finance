// Bounded mean-variance portfolio optimizer shared by fin_portfolio_optimize
// (table function) and fin_portfolio_optimize_table (via a scalar kernel).
//
// All problems are convex quadratic programs over fully invested weights
// (sum w = 1) with per-asset bounds lb <= w <= ub, solved exactly by a primal
// active-set method (Nocedal & Wright, Numerical Optimization, Algorithm 16.3)
// from a constructed feasible point. The covariance must be symmetric positive
// definite, so every subproblem has a unique solution.

struct PortfolioQPConfig {
	string objective = "min_variance";
	double risk_free = 0.0;
	bool long_only = true;
	double min_weight = std::numeric_limits<double>::quiet_NaN(); // NaN = not given
	double max_weight = std::numeric_limits<double>::quiet_NaN();
	double target_return = std::numeric_limits<double>::quiet_NaN();
	double target_vol = std::numeric_limits<double>::quiet_NaN();
	double risk_aversion = 1.0;
};

// Optional optimizer arguments after (mu, cov); NULL means the default.
static PortfolioQPConfig ReadPortfolioQPConfig(const vector<Value> &inputs, idx_t first, const string &function_name) {
	PortfolioQPConfig config;
	auto arg = [&](idx_t offset) -> const Value * {
		auto index = first + offset;
		return index < inputs.size() && !inputs[index].IsNull() ? &inputs[index] : nullptr;
	};
	auto read_double = [&](idx_t offset, double &target) {
		if (auto value = arg(offset)) {
			target = value->GetValue<double>();
			if (!std::isfinite(target)) {
				throw InvalidInputException("%s: optimizer parameters must be finite", function_name);
			}
		}
	};
	if (auto value = arg(0)) {
		config.objective = value->GetValue<string>();
	}
	read_double(1, config.risk_free);
	if (auto value = arg(2)) {
		config.long_only = value->GetValue<bool>();
	}
	read_double(3, config.min_weight);
	read_double(4, config.max_weight);
	read_double(5, config.target_return);
	read_double(6, config.target_vol);
	read_double(7, config.risk_aversion);
	return config;
}

// Checks that do not depend on the data, so callers can run them at bind time.
static void ValidatePortfolioQPConfig(const PortfolioQPConfig &config, const string &function_name) {
	auto objective = StringUtil::Lower(config.objective);
	StringUtil::Trim(objective);
	if (objective != "min_variance" && objective != "max_sharpe" && objective != "target_return" &&
	    objective != "target_vol" && objective != "max_utility") {
		throw InvalidInputException("%s: unknown objective '%s' (expected min_variance, max_sharpe, target_return, "
		                            "target_vol, or max_utility)",
		                            function_name, objective);
	}
	if (!std::isfinite(config.risk_free)) {
		throw InvalidInputException("%s: risk_free must be finite", function_name);
	}
	if (std::isinf(config.min_weight) || std::isinf(config.max_weight)) {
		throw InvalidInputException("%s: min_weight and max_weight must be finite or NULL", function_name);
	}
	if (config.long_only && config.min_weight < 0.0) {
		throw InvalidInputException("%s: min_weight must be non-negative when long_only is true", function_name);
	}
	if (config.min_weight > config.max_weight || (config.long_only && config.max_weight < 0.0)) {
		throw InvalidInputException("%s: min_weight must not exceed max_weight", function_name);
	}
	if (objective == "target_return" && !std::isfinite(config.target_return)) {
		throw InvalidInputException("%s: target_return must be finite for the target_return objective",
		                            function_name);
	}
	if (objective == "target_vol" && (!std::isfinite(config.target_vol) || config.target_vol <= 0.0)) {
		throw InvalidInputException("%s: target_vol must be positive and finite for the target_vol objective",
		                            function_name);
	}
	if (objective == "max_utility" && (!std::isfinite(config.risk_aversion) || config.risk_aversion <= 0.0)) {
		throw InvalidInputException("%s: risk_aversion must be positive and finite", function_name);
	}
}

struct PortfolioQP {
	idx_t n = 0;
	vector<vector<double>> g;
	vector<double> c;
	vector<vector<double>> a_eq;
	vector<double> b_eq;
	// Inequalities a_in[i]' x >= b_in[i].
	vector<vector<double>> a_in;
	vector<double> b_in;
};

static double PortfolioQPDot(const vector<double> &a, const vector<double> &b) {
	double sum = 0.0;
	for (idx_t i = 0; i < a.size(); i++) {
		sum += a[i] * b[i];
	}
	return sum;
}

// Gaussian elimination with partial pivoting; false when (numerically) singular.
static bool PortfolioQPSolveDense(vector<vector<double>> m, vector<double> &rhs) {
	auto n = rhs.size();
	double scale = 0.0;
	for (auto &row : m) {
		for (auto v : row) {
			scale = std::max(scale, std::fabs(v));
		}
	}
	if (scale == 0.0) {
		return false;
	}
	for (idx_t col = 0; col < n; col++) {
		idx_t pivot = col;
		for (idx_t r = col + 1; r < n; r++) {
			if (std::fabs(m[r][col]) > std::fabs(m[pivot][col])) {
				pivot = r;
			}
		}
		if (std::fabs(m[pivot][col]) <= 1e-14 * scale) {
			return false;
		}
		std::swap(m[pivot], m[col]);
		std::swap(rhs[pivot], rhs[col]);
		for (idx_t r = col + 1; r < n; r++) {
			auto factor = m[r][col] / m[col][col];
			if (factor == 0.0) {
				continue;
			}
			for (idx_t k = col; k < n; k++) {
				m[r][k] -= factor * m[col][k];
			}
			rhs[r] -= factor * rhs[col];
		}
	}
	for (idx_t i = n; i-- > 0;) {
		double sum = rhs[i];
		for (idx_t k = i + 1; k < n; k++) {
			sum -= m[i][k] * rhs[k];
		}
		rhs[i] = sum / m[i][i];
	}
	return true;
}

// Primal active-set QP: min 1/2 x'Gx + c'x subject to the equalities and
// inequalities of `qp`. `x` must be feasible on entry and holds the solution
// on success. `working` lists inequality indices to start from (they must be
// active at x and linearly independent of the equalities); it holds the final
// active set, so consecutive solves over the same feasible set warm start.
static bool PortfolioQPSolve(const PortfolioQP &qp, vector<double> &x, vector<idx_t> &working) {
	auto n = qp.n;
	auto n_eq = qp.a_eq.size();
	vector<double> in_norm(qp.a_in.size());
	for (idx_t i = 0; i < qp.a_in.size(); i++) {
		double s = 0.0;
		for (auto v : qp.a_in[i]) {
			s += std::fabs(v);
		}
		in_norm[i] = s;
	}
	vector<bool> in_working(qp.a_in.size(), false);
	vector<idx_t> filtered;
	for (auto i : working) {
		if (i < qp.a_in.size() && !in_working[i] &&
		    std::fabs(PortfolioQPDot(qp.a_in[i], x) - qp.b_in[i]) <= 1e-12 * (1.0 + std::fabs(qp.b_in[i]))) {
			in_working[i] = true;
			filtered.push_back(i);
		}
	}
	working = std::move(filtered);
	idx_t max_iterations = 200 + 20 * (n + qp.a_in.size());
	for (idx_t iteration = 0; iteration < max_iterations; iteration++) {
		vector<double> grad(n);
		for (idx_t r = 0; r < n; r++) {
			grad[r] = PortfolioQPDot(qp.g[r], x) + qp.c[r];
		}
		auto m = n_eq + working.size();
		auto size = n + m;
		vector<vector<double>> kkt(size, vector<double>(size, 0.0));
		vector<double> rhs(size, 0.0);
		for (idx_t r = 0; r < n; r++) {
			for (idx_t k = 0; k < n; k++) {
				kkt[r][k] = qp.g[r][k];
			}
			rhs[r] = -grad[r];
		}
		for (idx_t j = 0; j < m; j++) {
			auto &row = j < n_eq ? qp.a_eq[j] : qp.a_in[working[j - n_eq]];
			for (idx_t k = 0; k < n; k++) {
				kkt[n + j][k] = row[k];
				kkt[k][n + j] = -row[k];
			}
		}
		if (!PortfolioQPSolveDense(std::move(kkt), rhs)) {
			return false;
		}
		double p_norm = 0.0;
		double x_norm = 1.0;
		for (idx_t k = 0; k < n; k++) {
			p_norm = std::max(p_norm, std::fabs(rhs[k]));
			x_norm = std::max(x_norm, std::fabs(x[k]));
		}
		if (p_norm <= 1e-13 * x_norm) {
			// Stationary on the working face: drop the most negative multiplier.
			double grad_norm = 1e-300;
			for (auto v : grad) {
				grad_norm = std::max(grad_norm, std::fabs(v));
			}
			idx_t drop = DConstants::INVALID_INDEX;
			double most_negative = -1e-11 * grad_norm;
			for (idx_t j = 0; j < working.size(); j++) {
				auto lambda = rhs[n + n_eq + j];
				if (lambda < most_negative) {
					most_negative = lambda;
					drop = j;
				}
			}
			if (drop == DConstants::INVALID_INDEX) {
				return true;
			}
			in_working[working[drop]] = false;
			working.erase(working.begin() + NumericCast<int64_t>(drop));
			continue;
		}
		double alpha = 1.0;
		idx_t blocking = DConstants::INVALID_INDEX;
		for (idx_t i = 0; i < qp.a_in.size(); i++) {
			if (in_working[i]) {
				continue;
			}
			double ap = 0.0;
			for (idx_t k = 0; k < n; k++) {
				ap += qp.a_in[i][k] * rhs[k];
			}
			if (ap >= -1e-14 * in_norm[i] * p_norm) {
				continue;
			}
			auto ratio = std::max(0.0, (qp.b_in[i] - PortfolioQPDot(qp.a_in[i], x)) / ap);
			if (ratio < alpha) {
				alpha = ratio;
				blocking = i;
			}
		}
		for (idx_t k = 0; k < n; k++) {
			x[k] += alpha * rhs[k];
		}
		if (blocking != DConstants::INVALID_INDEX) {
			in_working[blocking] = true;
			working.push_back(blocking);
		}
	}
	return false;
}

struct PortfolioBounds {
	vector<double> lb;
	vector<double> ub;
};

// Budget-constrained QP over w: sum w = 1 (plus optional extra equalities)
// and the finite bounds.
static PortfolioQP PortfolioBudgetQP(const vector<vector<double>> &g, const vector<double> &c,
                                     const PortfolioBounds &bounds) {
	PortfolioQP qp;
	qp.n = c.size();
	qp.g = g;
	qp.c = c;
	qp.a_eq.push_back(vector<double>(qp.n, 1.0));
	qp.b_eq.push_back(1.0);
	for (idx_t i = 0; i < qp.n; i++) {
		if (std::isfinite(bounds.lb[i])) {
			vector<double> row(qp.n, 0.0);
			row[i] = 1.0;
			qp.a_in.push_back(std::move(row));
			qp.b_in.push_back(bounds.lb[i]);
		}
		if (std::isfinite(bounds.ub[i])) {
			vector<double> row(qp.n, 0.0);
			row[i] = -1.0;
			qp.a_in.push_back(std::move(row));
			qp.b_in.push_back(-bounds.ub[i]);
		}
	}
	return qp;
}

// Linear program max mu'w subject to sum w = 1, lb <= w <= ub. The optimum
// (when bounded) fills assets in descending mu order to their upper bounds,
// one asset taking the remainder. Returns true with `w` set when bounded;
// false when unbounded, with `up`/`down` the assets of an improving ray.
static bool PortfolioMaxReturnLP(const vector<double> &mu, const PortfolioBounds &bounds, vector<double> &w,
                                 idx_t &up, idx_t &down) {
	auto n = mu.size();
	up = DConstants::INVALID_INDEX;
	down = DConstants::INVALID_INDEX;
	for (idx_t i = 0; i < n; i++) {
		if (!std::isfinite(bounds.ub[i]) && (up == DConstants::INVALID_INDEX || mu[i] > mu[up])) {
			up = i;
		}
		if (!std::isfinite(bounds.lb[i]) && (down == DConstants::INVALID_INDEX || mu[i] < mu[down])) {
			down = i;
		}
	}
	if (up != DConstants::INVALID_INDEX && down != DConstants::INVALID_INDEX && mu[up] > mu[down]) {
		return false;
	}
	vector<idx_t> order(n);
	std::iota(order.begin(), order.end(), 0);
	std::stable_sort(order.begin(), order.end(), [&](idx_t a, idx_t b) { return mu[a] > mu[b]; });
	for (idx_t k = 0; k < n; k++) {
		bool finite = true;
		double others = 0.0;
		for (idx_t j = 0; j < n && finite; j++) {
			if (j == k) {
				continue;
			}
			auto value = j < k ? bounds.ub[order[j]] : bounds.lb[order[j]];
			finite = std::isfinite(value);
			others += value;
		}
		if (!finite) {
			continue;
		}
		auto pivot = order[k];
		auto remainder = 1.0 - others;
		auto tol = 1e-12 * (1.0 + std::fabs(remainder));
		if (remainder < bounds.lb[pivot] - tol || remainder > bounds.ub[pivot] + tol) {
			continue;
		}
		w.assign(n, 0.0);
		for (idx_t j = 0; j < n; j++) {
			w[order[j]] = j < k ? bounds.ub[order[j]] : bounds.lb[order[j]];
		}
		w[pivot] = std::min(std::max(remainder, bounds.lb[pivot]), bounds.ub[pivot]);
		return true;
	}
	// Only exact mu ties between assets with infinite bounds leave no finite
	// vertex; every feasible point is then optimal along those assets. Build one
	// by starting from the bounds nearest zero and absorbing the remainder in an
	// asset with unlimited room.
	w.assign(n, 0.0);
	double total = 0.0;
	for (idx_t i = 0; i < n; i++) {
		w[i] = std::min(std::max(0.0, bounds.lb[i]), bounds.ub[i]);
		total += w[i];
	}
	auto remainder = 1.0 - total;
	for (idx_t i = 0; i < n && remainder != 0.0; i++) {
		auto room = remainder > 0.0 ? bounds.ub[i] - w[i] : bounds.lb[i] - w[i];
		auto move = remainder > 0.0 ? std::min(remainder, room) : std::max(remainder, room);
		w[i] += move;
		remainder -= move;
	}
	return true;
}

// Any feasible fully invested portfolio.
static vector<double> PortfolioFeasiblePoint(const vector<double> &mu, const PortfolioBounds &bounds) {
	vector<double> w;
	idx_t up, down;
	if (PortfolioMaxReturnLP(mu, bounds, w, up, down)) {
		return w;
	}
	auto n = mu.size();
	w.assign(n, 0.0);
	double others = 0.0;
	for (idx_t i = 0; i < n; i++) {
		if (i != up) {
			w[i] = std::min(std::max(0.0, bounds.lb[i]), bounds.ub[i]);
			others += w[i];
		}
	}
	w[up] = 1.0 - others;
	if (w[up] < bounds.lb[up]) {
		w[down] -= bounds.lb[up] - w[up];
		w[up] = bounds.lb[up];
	}
	return w;
}

static double PortfolioQPVariance(const vector<vector<double>> &cov, const vector<double> &w) {
	double variance = 0.0;
	for (idx_t r = 0; r < w.size(); r++) {
		variance += w[r] * PortfolioQPDot(cov[r], w);
	}
	return std::max(variance, 0.0);
}

static bool PortfolioMuIsConstant(const vector<double> &mu) {
	auto minmax = std::minmax_element(mu.begin(), mu.end());
	return *minmax.second - *minmax.first <= 1e-15 * std::max(1.0, std::fabs(*minmax.second));
}

static vector<double> PortfolioQPRun(const PortfolioQP &qp, vector<double> x, vector<idx_t> &working,
                                     const string &function_name) {
	if (!PortfolioQPSolve(qp, x, working)) {
		throw InvalidInputException("%s: optimizer did not converge", function_name);
	}
	return x;
}

static vector<double> PortfolioMinVarianceAtReturn(const vector<vector<double>> &cov, const vector<double> &mu,
                                                   const PortfolioBounds &bounds, double target,
                                                   const vector<double> &start, const string &function_name) {
	auto qp = PortfolioBudgetQP(cov, vector<double>(mu.size(), 0.0), bounds);
	if (!PortfolioMuIsConstant(mu)) {
		qp.a_eq.push_back(mu);
		qp.b_eq.push_back(target);
	}
	vector<idx_t> working;
	return PortfolioQPRun(qp, start, working, function_name);
}

static vector<double> PortfolioOptimizeSolveRaw(const vector<double> &mu, const vector<vector<double>> &cov,
                                                const PortfolioQPConfig &config, const string &function_name) {
	ValidatePortfolioQPConfig(config, function_name);
	auto n = mu.size();
	if (n == 0) {
		throw InvalidInputException("%s: mu must not be empty", function_name);
	}
	if (cov.size() != n) {
		throw InvalidInputException("%s: covariance must be %llu x %llu to match mu", function_name,
		                            static_cast<unsigned long long>(n), static_cast<unsigned long long>(n));
	}
	for (idx_t i = 0; i < n; i++) {
		if (!std::isfinite(mu[i])) {
			throw InvalidInputException("%s: mu values must be finite", function_name);
		}
		if (cov[i].size() != n) {
			throw InvalidInputException("%s: covariance must be square", function_name);
		}
		for (idx_t j = 0; j < n; j++) {
			if (!std::isfinite(cov[i][j])) {
				throw InvalidInputException("%s: covariance values must be finite", function_name);
			}
			if (std::fabs(cov[i][j] - cov[j][i]) >
			    1e-10 * std::max(1.0, std::max(std::fabs(cov[i][j]), std::fabs(cov[j][i])))) {
				throw InvalidInputException("%s: covariance must be symmetric", function_name);
			}
		}
	}
	// Cholesky positive-definiteness check.
	{
		vector<vector<double>> l(n, vector<double>(n, 0.0));
		for (idx_t j = 0; j < n; j++) {
			double diag = cov[j][j];
			for (idx_t k = 0; k < j; k++) {
				diag -= l[j][k] * l[j][k];
			}
			if (!(diag > 1e-14 * std::max(1e-300, std::fabs(cov[j][j])))) {
				throw InvalidInputException("%s: covariance must be positive definite", function_name);
			}
			l[j][j] = std::sqrt(diag);
			for (idx_t i = j + 1; i < n; i++) {
				double s = cov[i][j];
				for (idx_t k = 0; k < j; k++) {
					s -= l[i][k] * l[j][k];
				}
				l[i][j] = s / l[j][j];
			}
		}
	}
	auto objective = StringUtil::Lower(config.objective);
	StringUtil::Trim(objective);
	auto inf = std::numeric_limits<double>::infinity();
	double lb = std::isnan(config.min_weight) ? (config.long_only ? 0.0 : -inf) : config.min_weight;
	double ub = std::isnan(config.max_weight) ? inf : config.max_weight;
	if (lb * double(n) > 1.0 + 1e-12 || ub * double(n) < 1.0 - 1e-12) {
		throw InvalidInputException("%s: no fully invested portfolio satisfies min_weight and max_weight for %llu "
		                            "assets",
		                            function_name, static_cast<unsigned long long>(n));
	}
	PortfolioBounds bounds {vector<double>(n, lb), vector<double>(n, ub)};
	vector<double> zero(n, 0.0);

	if (objective == "min_variance") {
		auto qp = PortfolioBudgetQP(cov, zero, bounds);
		vector<idx_t> working;
		return PortfolioQPRun(qp, PortfolioFeasiblePoint(mu, bounds), working, function_name);
	}
	if (objective == "max_utility") {
		if (!std::isfinite(config.risk_aversion) || config.risk_aversion <= 0.0) {
			throw InvalidInputException("%s: risk_aversion must be positive and finite", function_name);
		}
		vector<vector<double>> g(n, vector<double>(n));
		vector<double> c(n);
		for (idx_t i = 0; i < n; i++) {
			for (idx_t j = 0; j < n; j++) {
				g[i][j] = config.risk_aversion * cov[i][j];
			}
			c[i] = -mu[i];
		}
		auto qp = PortfolioBudgetQP(g, c, bounds);
		vector<idx_t> working;
		return PortfolioQPRun(qp, PortfolioFeasiblePoint(mu, bounds), working, function_name);
	}
	if (objective == "target_return") {
		if (!std::isfinite(config.target_return)) {
			throw InvalidInputException("%s: target_return must be finite for the target_return objective",
			                            function_name);
		}
		auto target = config.target_return;
		vector<double> hi, lo;
		idx_t up_hi, down_hi, up_lo, down_lo;
		auto neg_mu = mu;
		for (auto &v : neg_mu) {
			v = -v;
		}
		bool hi_bounded = PortfolioMaxReturnLP(mu, bounds, hi, up_hi, down_hi);
		bool lo_bounded = PortfolioMaxReturnLP(neg_mu, bounds, lo, up_lo, down_lo);
		auto ret_tol = 1e-12 * std::max(1.0, std::fabs(target));
		if ((hi_bounded && target > PortfolioQPDot(mu, hi) + ret_tol) ||
		    (lo_bounded && target < PortfolioQPDot(mu, lo) - ret_tol) ||
		    (PortfolioMuIsConstant(mu) && std::fabs(target - mu[0]) > ret_tol)) {
			throw InvalidInputException("%s: target_return %g is not attainable with these bounds", function_name,
			                            target);
		}
		auto start = lo_bounded ? lo : (hi_bounded ? hi : PortfolioFeasiblePoint(mu, bounds));
		auto start_return = PortfolioQPDot(mu, start);
		if (std::fabs(start_return - target) > ret_tol) {
			if (target > start_return) {
				if (hi_bounded) {
					auto t = (target - start_return) / (PortfolioQPDot(mu, hi) - start_return);
					for (idx_t i = 0; i < n; i++) {
						start[i] += std::min(1.0, t) * (hi[i] - start[i]);
					}
				} else {
					auto t = (target - start_return) / (mu[up_hi] - mu[down_hi]);
					start[up_hi] += t;
					start[down_hi] -= t;
				}
			} else {
				// Only reachable when the minimum return is unbounded: move along the
				// ray that lowers mu'w (up_lo has the lower mu and no upper bound).
				auto t = (start_return - target) / (mu[down_lo] - mu[up_lo]);
				start[up_lo] += t;
				start[down_lo] -= t;
			}
		}
		return PortfolioMinVarianceAtReturn(cov, mu, bounds, target, start, function_name);
	}
	if (objective == "target_vol") {
		if (!std::isfinite(config.target_vol) || config.target_vol <= 0.0) {
			throw InvalidInputException("%s: target_vol must be positive and finite for the target_vol objective",
			                            function_name);
		}
		auto target = config.target_vol;
		auto min_var_qp = PortfolioBudgetQP(cov, zero, bounds);
		vector<idx_t> working;
		auto start = PortfolioFeasiblePoint(mu, bounds);
		auto w_mv = PortfolioQPRun(min_var_qp, start, working, function_name);
		auto vol_mv = std::sqrt(PortfolioQPVariance(cov, w_mv));
		if (target < vol_mv * (1.0 - 1e-12)) {
			throw InvalidInputException("%s: target_vol %g is below the minimum attainable volatility %g",
			                            function_name, target, vol_mv);
		}
		if (target <= vol_mv * (1.0 + 1e-12) || PortfolioMuIsConstant(mu)) {
			return w_mv;
		}
		vector<double> hi;
		idx_t up, down;
		if (PortfolioMaxReturnLP(mu, bounds, hi, up, down)) {
			// Least-variance portfolio among those with the maximum return.
			auto top = PortfolioMinVarianceAtReturn(cov, mu, bounds, PortfolioQPDot(mu, hi), hi, function_name);
			if (std::sqrt(PortfolioQPVariance(cov, top)) <= target) {
				return top;
			}
		}
		// Otherwise the answer is the efficient portfolio max mu'w - lambda/2 w'Sw
		// whose volatility equals the target; volatility falls as lambda grows.
		auto solve_lambda = [&](double lambda, vector<double> &x, vector<idx_t> &active) {
			vector<vector<double>> g(n, vector<double>(n));
			vector<double> c(n);
			for (idx_t i = 0; i < n; i++) {
				for (idx_t j = 0; j < n; j++) {
					g[i][j] = lambda * cov[i][j];
				}
				c[i] = -mu[i];
			}
			auto qp = PortfolioBudgetQP(g, c, bounds);
			x = PortfolioQPRun(qp, x, active, function_name);
			return std::sqrt(PortfolioQPVariance(cov, x));
		};
		vector<double> x = w_mv;
		vector<idx_t> active = working;
		double lambda_hi = 1.0; // volatility <= target
		double lambda_lo = 1.0; // volatility >= target
		auto vol = solve_lambda(1.0, x, active);
		vector<double> best = x;
		if (vol > target) {
			while (vol > target) {
				lambda_lo = lambda_hi;
				lambda_hi *= 4.0;
				if (lambda_hi > 1e300) {
					return w_mv;
				}
				vol = solve_lambda(lambda_hi, x, active);
			}
			best = x;
		} else {
			best = x;
			while (vol <= target) {
				lambda_hi = lambda_lo;
				best = x;
				lambda_lo /= 4.0;
				if (lambda_lo < 1e-300) {
					return best;
				}
				vol = solve_lambda(lambda_lo, x, active);
			}
		}
		for (idx_t iteration = 0; iteration < 200 && lambda_hi / lambda_lo > 1.0 + 1e-15; iteration++) {
			auto mid = std::sqrt(lambda_hi * lambda_lo);
			if (mid <= lambda_lo || mid >= lambda_hi) {
				break;
			}
			vol = solve_lambda(mid, x, active);
			if (vol <= target) {
				lambda_hi = mid;
				best = x;
				if (vol >= target * (1.0 - 1e-15)) {
					break;
				}
			} else {
				lambda_lo = mid;
			}
		}
		return best;
	}
	// max_sharpe: max (mu - rf)'w / sqrt(w'Sw) via the homogenized problem
	// min y'Sy s.t. (mu - rf)'y = 1 and the bounds scaled by k = sum y >= 0,
	// with w = y / k (Cornuejols & Tutuncu, Optimization Methods in Finance, 8.2).
	vector<double> excess(n);
	for (idx_t i = 0; i < n; i++) {
		excess[i] = mu[i] - config.risk_free;
	}
	vector<double> w0;
	idx_t up, down;
	if (PortfolioMaxReturnLP(excess, bounds, w0, up, down)) {
		if (PortfolioQPDot(excess, w0) <= 1e-15 * std::max(1.0, std::fabs(config.risk_free))) {
			throw InvalidInputException("%s: no feasible portfolio has expected return above risk_free", function_name);
		}
	} else {
		w0 = PortfolioFeasiblePoint(excess, bounds);
		auto gap = PortfolioQPDot(excess, w0);
		auto t = std::max(0.0, -gap) / (excess[up] - excess[down]) + 1.0;
		w0[up] += t;
		w0[down] -= t;
	}
	auto scale = PortfolioQPDot(excess, w0);
	PortfolioQP qp;
	qp.n = n;
	qp.g = cov;
	qp.c = zero;
	qp.a_eq.push_back(excess);
	qp.b_eq.push_back(1.0);
	for (idx_t i = 0; i < n; i++) {
		if (std::isfinite(lb)) {
			vector<double> row(n, -lb);
			row[i] += 1.0;
			qp.a_in.push_back(std::move(row));
			qp.b_in.push_back(0.0);
		}
		if (std::isfinite(ub)) {
			vector<double> row(n, ub);
			row[i] -= 1.0;
			qp.a_in.push_back(std::move(row));
			qp.b_in.push_back(0.0);
		}
	}
	qp.a_in.push_back(vector<double>(n, 1.0));
	qp.b_in.push_back(0.0);
	// Drop all-zero rows (a bound equal to 1 with a single asset).
	for (idx_t i = qp.a_in.size(); i-- > 0;) {
		bool zero_row = true;
		for (auto v : qp.a_in[i]) {
			zero_row = zero_row && v == 0.0;
		}
		if (zero_row) {
			qp.a_in.erase(qp.a_in.begin() + NumericCast<int64_t>(i));
			qp.b_in.erase(qp.b_in.begin() + NumericCast<int64_t>(i));
		}
	}
	vector<double> y(n);
	for (idx_t i = 0; i < n; i++) {
		y[i] = w0[i] / scale;
	}
	vector<idx_t> working;
	y = PortfolioQPRun(qp, y, working, function_name);
	double kappa = 0.0;
	double y_norm = 0.0;
	for (auto v : y) {
		kappa += v;
		y_norm = std::max(y_norm, std::fabs(v));
	}
	if (!(kappa > 1e-12 * y_norm)) {
		throw InvalidInputException("%s: the maximum Sharpe ratio is not attained by a fully invested portfolio "
		                            "(add weight bounds)",
		                            function_name);
	}
	for (auto &v : y) {
		v /= kappa;
	}
	return y;
}

static vector<double> PortfolioOptimizeSolve(const vector<double> &mu, const vector<vector<double>> &cov,
                                             const PortfolioQPConfig &config, const string &function_name) {
	auto weights = PortfolioOptimizeSolveRaw(mu, cov, config, function_name);
	// Snap rounding residue onto the bounds (for example 1e-17 for an excluded asset).
	auto lb = std::isnan(config.min_weight) ? (config.long_only ? 0.0 : -std::numeric_limits<double>::infinity())
	                                        : config.min_weight;
	auto ub = std::isnan(config.max_weight) ? std::numeric_limits<double>::infinity() : config.max_weight;
	for (auto &w : weights) {
		if (std::fabs(w - lb) <= 1e-14) {
			w = lb;
		} else if (std::fabs(w - ub) <= 1e-14) {
			w = ub;
		}
	}
	return weights;
}
