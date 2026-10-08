// Small dense linear algebra and quadratic programming used by the portfolio
// table functions. Problem sizes are the number of assets (typically < 1000).

using FinanceMatrix = vector<vector<double>>;

// Solve M x = rhs in place with Gaussian elimination and partial pivoting.
// Returns false when M is numerically singular.
static bool SolveDense(FinanceMatrix m, vector<double> &rhs) {
	auto n = rhs.size();
	double scale = 0.0;
	for (auto &row : m) {
		for (auto v : row) {
			scale = std::max(scale, std::fabs(v));
		}
	}
	if (!(scale > 0.0)) {
		return false;
	}
	for (idx_t col = 0; col < n; col++) {
		idx_t pivot = col;
		for (idx_t r = col + 1; r < n; r++) {
			if (std::fabs(m[r][col]) > std::fabs(m[pivot][col])) {
				pivot = r;
			}
		}
		if (std::fabs(m[pivot][col]) <= 1e-13 * scale) {
			return false;
		}
		std::swap(m[pivot], m[col]);
		std::swap(rhs[pivot], rhs[col]);
		for (idx_t r = col + 1; r < n; r++) {
			auto factor = m[r][col] / m[col][col];
			if (factor == 0.0) {
				continue;
			}
			for (idx_t c = col; c < n; c++) {
				m[r][c] -= factor * m[col][c];
			}
			rhs[r] -= factor * rhs[col];
		}
	}
	for (idx_t i = n; i-- > 0;) {
		double sum = rhs[i];
		for (idx_t c = i + 1; c < n; c++) {
			sum -= m[i][c] * rhs[c];
		}
		rhs[i] = sum / m[i][i];
	}
	return true;
}

// Minimize 1/2 x'Gx subject to A x = b over the free variables (the others are
// fixed at zero), by solving the KKT system. Returns false when it is singular.
static bool SolveEqualityQP(const FinanceMatrix &g, const FinanceMatrix &a, const vector<double> &b,
                            const vector<bool> &free, vector<double> &x) {
	vector<idx_t> index;
	for (idx_t i = 0; i < free.size(); i++) {
		if (free[i]) {
			index.push_back(i);
		}
	}
	auto nf = index.size();
	auto m = a.size();
	FinanceMatrix kkt(nf + m, vector<double>(nf + m, 0.0));
	vector<double> rhs(nf + m, 0.0);
	for (idx_t i = 0; i < nf; i++) {
		for (idx_t j = 0; j < nf; j++) {
			kkt[i][j] = g[index[i]][index[j]];
		}
		for (idx_t k = 0; k < m; k++) {
			kkt[i][nf + k] = -a[k][index[i]];
			kkt[nf + k][i] = a[k][index[i]];
		}
	}
	for (idx_t k = 0; k < m; k++) {
		rhs[nf + k] = b[k];
	}
	if (!SolveDense(std::move(kkt), rhs)) {
		return false;
	}
	x.assign(free.size(), 0.0);
	for (idx_t i = 0; i < nf; i++) {
		x[index[i]] = rhs[i];
	}
	return true;
}

// Minimize 1/2 x'Gx subject to A x = b, x >= 0 with a Mehrotra predictor-corrector
// primal-dual interior-point method, then polish on the detected support by an
// exact equality-constrained solve. Returns false when it does not converge.
static bool SolveNonNegativeQP(const FinanceMatrix &g_input, const FinanceMatrix &a, const vector<double> &b,
                               vector<double> &result) {
	auto n = g_input.size();
	auto m = a.size();
	double g_scale = 0.0;
	for (idx_t i = 0; i < n; i++) {
		g_scale = std::max(g_scale, std::fabs(g_input[i][i]));
	}
	if (!(g_scale > 0.0)) {
		g_scale = 1.0;
	}
	FinanceMatrix g = g_input;
	for (auto &row : g) {
		for (auto &v : row) {
			v /= g_scale;
		}
	}
	vector<double> x(n, 1.0 / double(n));
	vector<double> s(n, 1.0);
	vector<double> y(m, 0.0);
	bool converged = false;
	double last_mu = 1.0;
	for (idx_t iteration = 0; iteration < 200; iteration++) {
		// Residuals.
		vector<double> r_dual(n, 0.0);
		vector<double> r_primal(m, 0.0);
		double mu = 0.0;
		for (idx_t i = 0; i < n; i++) {
			double gx = 0.0;
			for (idx_t j = 0; j < n; j++) {
				gx += g[i][j] * x[j];
			}
			double aty = 0.0;
			for (idx_t k = 0; k < m; k++) {
				aty += a[k][i] * y[k];
			}
			r_dual[i] = gx - aty - s[i];
			mu += x[i] * s[i];
		}
		mu /= double(n);
		double primal_norm = 0.0;
		for (idx_t k = 0; k < m; k++) {
			double ax = 0.0;
			for (idx_t i = 0; i < n; i++) {
				ax += a[k][i] * x[i];
			}
			r_primal[k] = ax - b[k];
			primal_norm = std::max(primal_norm, std::fabs(r_primal[k]));
		}
		double dual_norm = 0.0;
		for (auto v : r_dual) {
			dual_norm = std::max(dual_norm, std::fabs(v));
		}
		last_mu = mu;
		if (mu < 1e-14 && primal_norm < 1e-12 && dual_norm < 1e-11) {
			converged = true;
			break;
		}
		// Newton system [[G + X^-1 S, -A'], [A, 0]] for a complementarity target.
		auto newton = [&](const vector<double> &complementarity, vector<double> &dx, vector<double> &dy,
		                  vector<double> &ds) {
			FinanceMatrix kkt(n + m, vector<double>(n + m, 0.0));
			vector<double> rhs(n + m, 0.0);
			for (idx_t i = 0; i < n; i++) {
				for (idx_t j = 0; j < n; j++) {
					kkt[i][j] = g[i][j];
				}
				kkt[i][i] += s[i] / x[i];
				for (idx_t k = 0; k < m; k++) {
					kkt[i][n + k] = -a[k][i];
					kkt[n + k][i] = a[k][i];
				}
				rhs[i] = -r_dual[i] + complementarity[i] / x[i];
			}
			for (idx_t k = 0; k < m; k++) {
				rhs[n + k] = -r_primal[k];
			}
			if (!SolveDense(std::move(kkt), rhs)) {
				return false;
			}
			dx.assign(rhs.begin(), rhs.begin() + n);
			dy.assign(rhs.begin() + n, rhs.end());
			ds.resize(n);
			for (idx_t i = 0; i < n; i++) {
				ds[i] = (complementarity[i] - s[i] * dx[i]) / x[i];
			}
			return true;
		};
		auto max_step = [&](const vector<double> &dx, const vector<double> &ds) {
			double alpha = 1.0;
			for (idx_t i = 0; i < n; i++) {
				if (dx[i] < 0.0) {
					alpha = std::min(alpha, -x[i] / dx[i]);
				}
				if (ds[i] < 0.0) {
					alpha = std::min(alpha, -s[i] / ds[i]);
				}
			}
			return alpha;
		};
		vector<double> comp(n), dx, dy, ds;
		for (idx_t i = 0; i < n; i++) {
			comp[i] = -x[i] * s[i];
		}
		if (!newton(comp, dx, dy, ds)) {
			break;
		}
		auto alpha_aff = max_step(dx, ds);
		double mu_aff = 0.0;
		for (idx_t i = 0; i < n; i++) {
			mu_aff += (x[i] + alpha_aff * dx[i]) * (s[i] + alpha_aff * ds[i]);
		}
		mu_aff /= double(n);
		auto sigma = mu > 0.0 ? std::pow(mu_aff / mu, 3.0) : 0.0;
		for (idx_t i = 0; i < n; i++) {
			comp[i] = -x[i] * s[i] - dx[i] * ds[i] + sigma * mu;
		}
		if (!newton(comp, dx, dy, ds)) {
			break;
		}
		auto alpha = std::min(1.0, 0.995 * max_step(dx, ds));
		for (idx_t i = 0; i < n; i++) {
			x[i] += alpha * dx[i];
			s[i] += alpha * ds[i];
		}
		for (idx_t k = 0; k < m; k++) {
			y[k] += alpha * dy[k];
		}
	}
	// A nearly complementary point is enough to identify the support for polishing.
	if (!converged && !(last_mu < 1e-9)) {
		return false;
	}
	// Polish: weights that the interior point drove to the bound are fixed at zero
	// and the remaining ones are solved exactly.
	double x_max = 0.0;
	for (auto v : x) {
		x_max = std::max(x_max, v);
	}
	vector<bool> free(n);
	for (idx_t i = 0; i < n; i++) {
		free[i] = x[i] > 1e-9 * std::max(1.0, x_max);
	}
	vector<double> polished;
	if (SolveEqualityQP(g_input, a, b, free, polished)) {
		bool feasible = true;
		for (auto v : polished) {
			feasible = feasible && v >= -1e-12;
		}
		if (feasible) {
			for (auto &v : polished) {
				v = std::max(v, 0.0);
			}
			result = std::move(polished);
			return true;
		}
	}
	result = std::move(x);
	return true;
}

// Mean-variance frontier: minimum variance portfolio for a target return, fully
// invested, long-only unless allow_short (closed form via the KKT system).
static bool FrontierWeights(const vector<double> &mu, const FinanceMatrix &cov, bool allow_short, double target,
                            bool with_target, vector<double> &weights) {
	auto n = mu.size();
	FinanceMatrix a = {vector<double>(n, 1.0)};
	vector<double> b = {1.0};
	if (with_target) {
		a.push_back(mu);
		b.push_back(target);
	}
	if (allow_short) {
		return SolveEqualityQP(cov, a, b, vector<bool>(n, true), weights);
	}
	return SolveNonNegativeQP(cov, a, b, weights);
}

// Cholesky check: covariance matrices must be symmetric positive definite.
static bool IsPositiveDefinite(const FinanceMatrix &cov) {
	auto n = cov.size();
	FinanceMatrix l(n, vector<double>(n, 0.0));
	for (idx_t i = 0; i < n; i++) {
		for (idx_t j = 0; j <= i; j++) {
			double sum = cov[i][j];
			for (idx_t k = 0; k < j; k++) {
				sum -= l[i][k] * l[j][k];
			}
			if (i == j) {
				if (!(sum > 0.0)) {
					return false;
				}
				l[i][i] = std::sqrt(sum);
			} else {
				l[i][j] = sum / l[j][j];
			}
		}
	}
	return true;
}

static void ValidateSymmetric(const FinanceMatrix &cov, const string &function_name) {
	for (idx_t i = 0; i < cov.size(); i++) {
		for (idx_t j = 0; j < i; j++) {
			auto tolerance = 1e-12 * std::max({1.0, std::fabs(cov[i][j]), std::fabs(cov[j][i])});
			if (std::fabs(cov[i][j] - cov[j][i]) > tolerance) {
				throw InvalidInputException("%s: covariance matrix must be symmetric", function_name);
			}
		}
	}
}

// Hierarchical risk parity (Lopez de Prado 2016, "Building Diversified Portfolios
// that Outperform Out-of-Sample"), following PyPortfolioOpt's HRPOpt: correlation
// distance sqrt((1 - rho) / 2) as the condensed distance, agglomerative
// clustering (Lance-Williams updates as in scipy.cluster.hierarchy.linkage),
// leaf order from the dendrogram, then recursive bisection with
// inverse-variance cluster variances.
static vector<double> HierarchicalRiskParityWeights(const FinanceMatrix &cov, const string &linkage,
                                                    const string &function_name) {
	auto n = cov.size();
	if (n == 1) {
		return {1.0};
	}
	for (idx_t i = 0; i < n; i++) {
		if (!(cov[i][i] > 0.0)) {
			throw InvalidInputException("%s: covariance diagonal must be positive", function_name);
		}
	}
	// Cluster distances, indexed by cluster id (leaves 0..n-1, merges n..2n-2).
	auto total = 2 * n - 1;
	FinanceMatrix dist(total, vector<double>(total, 0.0));
	for (idx_t i = 0; i < n; i++) {
		for (idx_t j = 0; j < n; j++) {
			auto rho = cov[i][j] / std::sqrt(cov[i][i] * cov[j][j]);
			dist[i][j] = i == j ? 0.0 : std::sqrt(std::min(1.0, std::max(0.0, (1.0 - rho) / 2.0)));
		}
	}
	vector<idx_t> size(total, 1);
	vector<bool> active(total, false);
	for (idx_t i = 0; i < n; i++) {
		active[i] = true;
	}
	vector<std::pair<idx_t, idx_t>> children(total);
	for (idx_t step = 0; step < n - 1; step++) {
		idx_t best_i = 0, best_j = 0;
		double best = std::numeric_limits<double>::infinity();
		for (idx_t i = 0; i < n + step; i++) {
			if (!active[i]) {
				continue;
			}
			for (idx_t j = i + 1; j < n + step; j++) {
				if (active[j] && dist[i][j] < best) {
					best = dist[i][j];
					best_i = i;
					best_j = j;
				}
			}
		}
		auto merged = n + step;
		children[merged] = {best_i, best_j};
		active[best_i] = false;
		active[best_j] = false;
		size[merged] = size[best_i] + size[best_j];
		for (idx_t k = 0; k < merged; k++) {
			if (!active[k]) {
				continue;
			}
			auto di = dist[best_i][k];
			auto dj = dist[best_j][k];
			double d;
			if (linkage == "single") {
				d = std::min(di, dj);
			} else if (linkage == "complete") {
				d = std::max(di, dj);
			} else if (linkage == "average") {
				d = (double(size[best_i]) * di + double(size[best_j]) * dj) / double(size[merged]);
			} else {
				// Ward (Lance-Williams form used by scipy for non-Euclidean input).
				auto t = double(size[best_i] + size[best_j] + size[k]);
				d = std::sqrt(std::max(0.0, (double(size[best_i] + size[k]) * di * di +
				                             double(size[best_j] + size[k]) * dj * dj - double(size[k]) * best * best) /
				                                t));
			}
			dist[merged][k] = d;
			dist[k][merged] = d;
		}
		active[merged] = true;
	}
	// Leaf order: pre-order traversal, lower cluster id first.
	vector<idx_t> order;
	vector<idx_t> stack = {total - 1};
	while (!stack.empty()) {
		auto node = stack.back();
		stack.pop_back();
		if (node < n) {
			order.push_back(node);
			continue;
		}
		stack.push_back(children[node].second);
		stack.push_back(children[node].first);
	}
	auto cluster_variance = [&](const vector<idx_t> &items) {
		double inverse_sum = 0.0;
		for (auto i : items) {
			inverse_sum += 1.0 / cov[i][i];
		}
		double variance = 0.0;
		for (auto i : items) {
			for (auto j : items) {
				variance += (1.0 / cov[i][i] / inverse_sum) * cov[i][j] * (1.0 / cov[j][j] / inverse_sum);
			}
		}
		return variance;
	};
	vector<double> weights(n, 1.0);
	vector<vector<idx_t>> clusters = {order};
	while (!clusters.empty()) {
		vector<vector<idx_t>> next;
		for (auto &cluster : clusters) {
			if (cluster.size() <= 1) {
				continue;
			}
			auto half = cluster.size() / 2;
			vector<idx_t> left(cluster.begin(), cluster.begin() + half);
			vector<idx_t> right(cluster.begin() + half, cluster.end());
			auto left_variance = cluster_variance(left);
			auto right_variance = cluster_variance(right);
			auto alpha = 1.0 - left_variance / (left_variance + right_variance);
			for (auto i : left) {
				weights[i] *= alpha;
			}
			for (auto i : right) {
				weights[i] *= 1.0 - alpha;
			}
			next.push_back(std::move(left));
			next.push_back(std::move(right));
		}
		clusters = std::move(next);
	}
	return weights;
}
