//===--------------------------------------------------------------------===//
// Portfolio construction kernels behind the fin_*_weights and
// fin_black_litterman_returns SQL macros. Inputs are per-row LIST(DOUBLE)
// vectors and LIST(LIST(DOUBLE)) matrices; shape errors, non-finite inputs,
// non-positive-definite covariances and non-converged solves return NULL for
// that row. Invalid constant configuration raises an error.
//===--------------------------------------------------------------------===//

//! Cholesky factor (lower, row-major) of a symmetric matrix; false unless safely positive definite.
static bool PortfolioCholesky(const vector<double> &a, idx_t n, vector<double> &l) {
	l.assign(n * n, 0.0);
	double scale = 0.0;
	for (idx_t i = 0; i < n; i++) {
		scale = std::max(scale, std::fabs(a[i * n + i]));
	}
	if (!(scale > 0.0) || !std::isfinite(scale)) {
		return false;
	}
	for (idx_t j = 0; j < n; j++) {
		double diag = a[j * n + j];
		for (idx_t p = 0; p < j; p++) {
			diag -= l[j * n + p] * l[j * n + p];
		}
		if (!(diag > 1e-14 * scale)) {
			return false;
		}
		l[j * n + j] = std::sqrt(diag);
		for (idx_t i = j + 1; i < n; i++) {
			double value = a[i * n + j];
			for (idx_t p = 0; p < j; p++) {
				value -= l[i * n + p] * l[j * n + p];
			}
			l[i * n + j] = value / l[j * n + j];
		}
	}
	return true;
}

//! Solves L L^T x = b given the Cholesky factor.
static vector<double> PortfolioCholeskySolve(const vector<double> &l, idx_t n, const vector<double> &b) {
	vector<double> y(n), x(n);
	for (idx_t i = 0; i < n; i++) {
		double sum = b[i];
		for (idx_t p = 0; p < i; p++) {
			sum -= l[i * n + p] * y[p];
		}
		y[i] = sum / l[i * n + i];
	}
	for (idx_t ii = n; ii-- > 0;) {
		double sum = y[ii];
		for (idx_t p = ii + 1; p < n; p++) {
			sum -= l[p * n + ii] * x[p];
		}
		x[ii] = sum / l[ii * n + ii];
	}
	return x;
}

//! Dense solve with partial pivoting; false for a (numerically) singular system.
static bool PortfolioSolve(vector<double> a, vector<double> b, idx_t n, vector<double> &x) {
	double scale = 0.0;
	for (auto value : a) {
		scale = std::max(scale, std::fabs(value));
	}
	if (!(scale > 0.0) || !std::isfinite(scale)) {
		return false;
	}
	for (idx_t col = 0; col < n; col++) {
		idx_t pivot = col;
		for (idx_t row = col + 1; row < n; row++) {
			if (std::fabs(a[row * n + col]) > std::fabs(a[pivot * n + col])) {
				pivot = row;
			}
		}
		if (!(std::fabs(a[pivot * n + col]) > 1e-13 * scale)) {
			return false;
		}
		if (pivot != col) {
			for (idx_t k = 0; k < n; k++) {
				std::swap(a[col * n + k], a[pivot * n + k]);
			}
			std::swap(b[col], b[pivot]);
		}
		for (idx_t row = col + 1; row < n; row++) {
			double factor = a[row * n + col] / a[col * n + col];
			if (factor == 0.0) {
				continue;
			}
			for (idx_t k = col; k < n; k++) {
				a[row * n + k] -= factor * a[col * n + k];
			}
			b[row] -= factor * b[col];
		}
	}
	x.assign(n, 0.0);
	for (idx_t row = n; row-- > 0;) {
		double sum = b[row];
		for (idx_t k = row + 1; k < n; k++) {
			sum -= a[row * n + k] * x[k];
		}
		x[row] = sum / a[row * n + row];
	}
	return true;
}

//! True for a finite, square, symmetric (to 1e-10 relative) matrix.
static bool PortfolioValidCovariance(const vector<double> &cov, idx_t rows, idx_t cols) {
	if (rows == 0 || rows != cols) {
		return false;
	}
	double scale = 0.0;
	for (auto value : cov) {
		if (!std::isfinite(value)) {
			return false;
		}
		scale = std::max(scale, std::fabs(value));
	}
	for (idx_t i = 0; i < rows; i++) {
		for (idx_t j = 0; j < i; j++) {
			if (std::fabs(cov[i * rows + j] - cov[j * rows + i]) > 1e-10 * scale) {
				return false;
			}
		}
	}
	return true;
}

//! Primal active-set solver for min 0.5 y'Qy - c'y s.t. a'y = b, y >= 0
//! (Nocedal & Wright, Algorithm 16.3). `y` must start feasible. Q must be
//! positive definite. Returns false on a singular step or iteration limit.
static bool PortfolioNonnegativeQP(const vector<double> &q, const vector<double> &c, const vector<double> &a, idx_t n,
                                   vector<double> &y) {
	vector<bool> fixed(n, false);
	for (idx_t i = 0; i < n; i++) {
		fixed[i] = y[i] == 0.0;
	}
	const idx_t max_iterations = 50 * n + 100;
	vector<idx_t> free_idx;
	vector<double> g(n), kkt, rhs, sol;
	for (idx_t iteration = 0; iteration < max_iterations; iteration++) {
		for (idx_t i = 0; i < n; i++) {
			double sum = -c[i];
			for (idx_t j = 0; j < n; j++) {
				sum += q[i * n + j] * y[j];
			}
			g[i] = sum;
		}
		free_idx.clear();
		for (idx_t i = 0; i < n; i++) {
			if (!fixed[i]) {
				free_idx.push_back(i);
			}
		}
		const idx_t m = free_idx.size();
		if (m == 0) {
			return false;
		}
		// [Q_FF a_F; a_F' 0] [p_F; lambda] = [-g_F; 0], with lambda = -nu.
		const idx_t dim = m + 1;
		kkt.assign(dim * dim, 0.0);
		rhs.assign(dim, 0.0);
		for (idx_t r = 0; r < m; r++) {
			for (idx_t s = 0; s < m; s++) {
				kkt[r * dim + s] = q[free_idx[r] * n + free_idx[s]];
			}
			kkt[r * dim + m] = a[free_idx[r]];
			kkt[m * dim + r] = a[free_idx[r]];
			rhs[r] = -g[free_idx[r]];
		}
		if (!PortfolioSolve(kkt, rhs, dim, sol)) {
			return false;
		}
		const double nu = -sol[m];
		double step_norm = 0.0, y_norm = 1.0;
		for (idx_t r = 0; r < m; r++) {
			step_norm = std::max(step_norm, std::fabs(sol[r]));
			y_norm = std::max(y_norm, std::fabs(y[free_idx[r]]));
		}
		if (step_norm <= 1e-13 * y_norm) {
			// Stationary on the working set: check the bound multipliers.
			double most_negative = 0.0;
			idx_t release = n;
			double g_scale = 0.0;
			for (idx_t i = 0; i < n; i++) {
				g_scale = std::max(g_scale, std::fabs(g[i]));
			}
			for (idx_t i = 0; i < n; i++) {
				if (!fixed[i]) {
					continue;
				}
				double mu = g[i] - nu * a[i];
				if (mu < most_negative && mu < -1e-12 * std::max(1.0, g_scale)) {
					most_negative = mu;
					release = i;
				}
			}
			if (release == n) {
				return true;
			}
			fixed[release] = false;
			continue;
		}
		double alpha = 1.0;
		idx_t blocking = n;
		for (idx_t r = 0; r < m; r++) {
			auto i = free_idx[r];
			if (sol[r] < 0.0) {
				double ratio = -y[i] / sol[r];
				if (ratio < alpha) {
					alpha = ratio;
					blocking = i;
				}
			}
		}
		for (idx_t r = 0; r < m; r++) {
			y[free_idx[r]] += alpha * sol[r];
		}
		if (blocking != n) {
			y[blocking] = 0.0;
			fixed[blocking] = true;
		}
	}
	return false;
}

static bool PortfolioNormalizeWeights(vector<double> &w) {
	double sum = 0.0;
	for (auto value : w) {
		sum += value;
	}
	if (!(std::fabs(sum) > 0.0) || !std::isfinite(sum)) {
		return false;
	}
	for (auto &value : w) {
		value /= sum;
		if (!std::isfinite(value)) {
			return false;
		}
	}
	return true;
}

//! Minimum-variance weights summing to one; long-only via the active-set QP.
static bool PortfolioMinVariance(const vector<double> &cov, idx_t n, bool long_only, vector<double> &w) {
	vector<double> l;
	if (!PortfolioCholesky(cov, n, l)) {
		return false;
	}
	w = PortfolioCholeskySolve(l, n, vector<double>(n, 1.0));
	if (!PortfolioNormalizeWeights(w)) {
		return false;
	}
	if (!long_only) {
		return true;
	}
	bool feasible = true;
	for (auto value : w) {
		feasible = feasible && value >= 0.0;
	}
	if (feasible) {
		return true;
	}
	w.assign(n, 1.0 / double(n));
	if (!PortfolioNonnegativeQP(cov, vector<double>(n, 0.0), vector<double>(n, 1.0), n, w)) {
		return false;
	}
	for (auto &value : w) {
		value = std::max(0.0, value);
	}
	return PortfolioNormalizeWeights(w);
}

//! Maximum-Sharpe (tangency) weights summing to one.
static bool PortfolioMaxSharpe(const vector<double> &mu, const vector<double> &cov, idx_t n, double risk_free,
                               bool long_only, vector<double> &w) {
	vector<double> excess(n);
	double best = -std::numeric_limits<double>::infinity();
	idx_t best_idx = 0;
	for (idx_t i = 0; i < n; i++) {
		excess[i] = mu[i] - risk_free;
		if (excess[i] > best) {
			best = excess[i];
			best_idx = i;
		}
	}
	vector<double> l;
	if (!PortfolioCholesky(cov, n, l)) {
		return false;
	}
	w = PortfolioCholeskySolve(l, n, excess);
	double sum = 0.0;
	bool nonnegative = true;
	for (auto value : w) {
		sum += value;
		nonnegative = nonnegative && value >= 0.0;
	}
	if (!long_only) {
		// The tangency portfolio exists only when 1' inv(S) (mu - rf) > 0.
		return sum > 0.0 && PortfolioNormalizeWeights(w);
	}
	if (!(best > 0.0)) {
		return false;
	}
	if (nonnegative && sum > 0.0) {
		return PortfolioNormalizeWeights(w);
	}
	// min y'Sy s.t. (mu - rf)'y = 1, y >= 0; weights are y / sum(y).
	w.assign(n, 0.0);
	w[best_idx] = 1.0 / best;
	if (!PortfolioNonnegativeQP(cov, vector<double>(n, 0.0), excess, n, w)) {
		return false;
	}
	for (auto &value : w) {
		value = std::max(0.0, value);
	}
	return PortfolioNormalizeWeights(w);
}

//! Long-only risk budgeting by cyclical coordinate descent on
//! 0.5 y'Sy - sum b_i ln y_i (Griveau-Billion, Richard and Roncalli 2013).
//! Converged when every risk-contribution share is within tol of its budget.
static bool PortfolioRiskParity(const vector<double> &cov, idx_t n, const vector<double> &budgets, double tol,
                                int64_t max_iter, vector<double> &w) {
	for (idx_t i = 0; i < n; i++) {
		if (!(cov[i * n + i] > 0.0)) {
			return false;
		}
	}
	vector<double> y(n);
	for (idx_t i = 0; i < n; i++) {
		y[i] = 1.0 / std::sqrt(cov[i * n + i]);
	}
	vector<double> sy(n);
	for (int64_t iteration = 0; iteration < max_iter; iteration++) {
		for (idx_t i = 0; i < n; i++) {
			double c = 0.0;
			for (idx_t j = 0; j < n; j++) {
				if (j != i) {
					c += cov[i * n + j] * y[j];
				}
			}
			const double s = cov[i * n + i];
			y[i] = (-c + std::sqrt(c * c + 4.0 * s * budgets[i])) / (2.0 * s);
			if (!(y[i] > 0.0) || !std::isfinite(y[i])) {
				return false;
			}
		}
		w = y;
		if (!PortfolioNormalizeWeights(w)) {
			return false;
		}
		double variance = 0.0;
		for (idx_t i = 0; i < n; i++) {
			double sum = 0.0;
			for (idx_t j = 0; j < n; j++) {
				sum += cov[i * n + j] * w[j];
			}
			sy[i] = sum;
			variance += w[i] * sum;
		}
		if (!(variance > 0.0)) {
			return false;
		}
		double error = 0.0;
		for (idx_t i = 0; i < n; i++) {
			error = std::max(error, std::fabs(w[i] * sy[i] / variance - budgets[i]));
		}
		if (error <= tol) {
			return true;
		}
	}
	return false;
}

//! Black-Litterman posterior expected returns (He and Litterman 1999):
//! pi = delta S w_mkt, mu = pi + tau S P' (P tau S P' + Omega)^-1 (Q - P pi),
//! with Omega defaulting to diag(P tau S P').
static bool PortfolioBlackLitterman(const vector<double> &weights, const vector<double> &cov, idx_t n,
                                    const vector<double> &p, idx_t k, const vector<double> &q,
                                    const vector<double> *omega, double tau, double delta, vector<double> &mu) {
	vector<double> pi(n, 0.0);
	for (idx_t i = 0; i < n; i++) {
		for (idx_t j = 0; j < n; j++) {
			pi[i] += delta * cov[i * n + j] * weights[j];
		}
	}
	// tS P' (n x k)
	vector<double> sp(n * k, 0.0);
	for (idx_t i = 0; i < n; i++) {
		for (idx_t v = 0; v < k; v++) {
			double sum = 0.0;
			for (idx_t j = 0; j < n; j++) {
				sum += cov[i * n + j] * p[v * n + j];
			}
			sp[i * k + v] = tau * sum;
		}
	}
	vector<double> m(k * k, 0.0), resid(k, 0.0);
	for (idx_t a = 0; a < k; a++) {
		for (idx_t b = 0; b < k; b++) {
			double sum = 0.0;
			for (idx_t i = 0; i < n; i++) {
				sum += p[a * n + i] * sp[i * k + b];
			}
			m[a * k + b] = sum;
		}
		double view = q[a];
		for (idx_t i = 0; i < n; i++) {
			view -= p[a * n + i] * pi[i];
		}
		resid[a] = view;
	}
	if (omega) {
		for (idx_t idx = 0; idx < k * k; idx++) {
			m[idx] += (*omega)[idx];
		}
	} else {
		for (idx_t a = 0; a < k; a++) {
			m[a * k + a] *= 2.0;
		}
	}
	vector<double> z;
	if (!PortfolioSolve(m, resid, k, z)) {
		return false;
	}
	mu = pi;
	for (idx_t i = 0; i < n; i++) {
		for (idx_t v = 0; v < k; v++) {
			mu[i] += sp[i * k + v] * z[v];
		}
		if (!std::isfinite(mu[i])) {
			return false;
		}
	}
	return true;
}

template <class T>
static T PortfolioScalarArg(const PreparedInputs &input, idx_t col, idx_t row) {
	auto &format = input.formats[col];
	return UnifiedVectorFormat::GetData<T>(format)[format.sel->get_index(row)];
}

static bool PortfolioReadVector(const DoubleListArg &arg, const PreparedInputs &input, idx_t row, vector<double> &out) {
	if (input.IsNull(arg.col, row)) {
		return false;
	}
	auto entry = arg.Entry(input, row);
	if (arg.HasNullElement(entry)) {
		return false;
	}
	out.assign(arg.values + entry.offset, arg.values + entry.offset + entry.length);
	for (auto value : out) {
		if (!std::isfinite(value)) {
			return false;
		}
	}
	return true;
}

static bool PortfolioReadMatrix(const MatrixArg &arg, const PreparedInputs &input, idx_t row, idx_t &rows, idx_t &cols,
                                vector<double> &out) {
	if (input.IsNull(arg.col, row) || !arg.Read(arg.Entry(input, row), rows, cols, out)) {
		return false;
	}
	for (auto value : out) {
		if (!std::isfinite(value)) {
			return false;
		}
	}
	return true;
}

enum class PortfolioKernel : uint8_t { MIN_VARIANCE, MAX_SHARPE, RISK_PARITY, BLACK_LITTERMAN };

template <PortfolioKernel KERNEL>
static void PortfolioWeightsFunction(DataChunk &args, ExpressionState &, Vector &result) {
	PreparedInputs input(args);
	const auto count = args.size();
	const auto constant = AllInputsConstant(args);
	const auto row_count = constant && count > 0 ? idx_t(1) : count;
	ListResultWriter writer(result, constant);
	const idx_t matrix_col = KERNEL == PortfolioKernel::MIN_VARIANCE || KERNEL == PortfolioKernel::RISK_PARITY ? 0 : 1;
	MatrixArg cov_arg(args, input, matrix_col);
	// List arguments are flattened once per chunk.
	unique_ptr<DoubleListArg> vec_arg, q_arg;
	unique_ptr<MatrixArg> p_arg, omega_arg;
	if (KERNEL == PortfolioKernel::MAX_SHARPE || KERNEL == PortfolioKernel::BLACK_LITTERMAN) {
		vec_arg = make_uniq<DoubleListArg>(args, input, 0);
	} else if (KERNEL == PortfolioKernel::RISK_PARITY) {
		vec_arg = make_uniq<DoubleListArg>(args, input, 1);
	}
	if (KERNEL == PortfolioKernel::BLACK_LITTERMAN) {
		p_arg = make_uniq<MatrixArg>(args, input, 2);
		q_arg = make_uniq<DoubleListArg>(args, input, 3);
		omega_arg = make_uniq<MatrixArg>(args, input, 5);
	}
	vector<double> cov, vec, extra, w, p, q, omega;
	for (idx_t row = 0; row < row_count; row++) {
		idx_t n = 0, cols = 0;
		bool ok = PortfolioReadMatrix(cov_arg, input, row, n, cols, cov) && PortfolioValidCovariance(cov, n, cols);
		if (ok) {
			switch (KERNEL) {
			case PortfolioKernel::MIN_VARIANCE: {
				if (input.IsNull(1, row)) {
					throw InvalidInputException("fin_min_variance_weights: long_only must not be NULL");
				}
				ok = PortfolioMinVariance(cov, n, PortfolioScalarArg<bool>(input, 1, row), w);
				break;
			}
			case PortfolioKernel::MAX_SHARPE: {
				if (input.IsNull(2, row) || input.IsNull(3, row)) {
					throw InvalidInputException("fin_max_sharpe_weights: risk_free and long_only must not be NULL");
				}
				const double risk_free = PortfolioScalarArg<double>(input, 2, row);
				if (!std::isfinite(risk_free)) {
					throw InvalidInputException("fin_max_sharpe_weights: risk_free must be finite");
				}
				ok = PortfolioReadVector(*vec_arg, input, row, vec) && vec.size() == n &&
				     PortfolioMaxSharpe(vec, cov, n, risk_free, PortfolioScalarArg<bool>(input, 3, row), w);
				break;
			}
			case PortfolioKernel::RISK_PARITY: {
				if (input.IsNull(2, row) || input.IsNull(3, row)) {
					throw InvalidInputException("fin_risk_parity_weights: tol and max_iter must not be NULL");
				}
				const double tol = PortfolioScalarArg<double>(input, 2, row);
				const int64_t max_iter = PortfolioScalarArg<int64_t>(input, 3, row);
				if (!(tol > 0.0) || !std::isfinite(tol)) {
					throw InvalidInputException("fin_risk_parity_weights: tol must be positive and finite");
				}
				if (max_iter < 1) {
					throw InvalidInputException("fin_risk_parity_weights: max_iter must be at least 1");
				}
				if (input.IsNull(1, row)) {
					vec.assign(n, 1.0 / double(n));
				} else {
					ok = PortfolioReadVector(*vec_arg, input, row, vec) && vec.size() == n;
					double total = 0.0;
					for (idx_t i = 0; ok && i < n; i++) {
						ok = vec[i] > 0.0;
						total += vec[i];
					}
					for (idx_t i = 0; ok && i < n; i++) {
						vec[i] /= total;
					}
				}
				ok = ok && PortfolioRiskParity(cov, n, vec, tol, max_iter, w);
				break;
			}
			case PortfolioKernel::BLACK_LITTERMAN: {
				if (input.IsNull(4, row) || input.IsNull(6, row)) {
					throw InvalidInputException("fin_black_litterman_returns: tau and risk_aversion must not be NULL");
				}
				const double tau = PortfolioScalarArg<double>(input, 4, row);
				const double delta = PortfolioScalarArg<double>(input, 6, row);
				if (!(tau > 0.0) || !std::isfinite(tau)) {
					throw InvalidInputException("fin_black_litterman_returns: tau must be positive and finite");
				}
				if (!(delta > 0.0) || !std::isfinite(delta)) {
					throw InvalidInputException("fin_black_litterman_returns: risk_aversion must be positive and finite");
				}
				idx_t k = 0, p_cols = 0;
				ok = PortfolioReadVector(*vec_arg, input, row, vec) && vec.size() == n &&
				     PortfolioReadMatrix(*p_arg, input, row, k, p_cols, p) && k > 0 && p_cols == n &&
				     PortfolioReadVector(*q_arg, input, row, q) && q.size() == k;
				const vector<double> *omega_ptr = nullptr;
				if (ok && !input.IsNull(5, row)) {
					idx_t o_rows = 0, o_cols = 0;
					ok = PortfolioReadMatrix(*omega_arg, input, row, o_rows, o_cols, omega) && o_rows == k && o_cols == k;
					omega_ptr = &omega;
				}
				ok = ok && PortfolioBlackLitterman(vec, cov, n, p, k, q, omega_ptr, tau, delta, w);
				break;
			}
			}
		}
		if (!ok) {
			writer.SetNull(row, count);
			continue;
		}
		auto out = writer.Begin(w.size());
		for (idx_t i = 0; i < w.size(); i++) {
			out[i] = w[i];
		}
		writer.Commit(row, w.size());
	}
	writer.Finish();
}

static void RegisterPortfolioOptimizerScalars(ExtensionLoader &loader) {
	const auto DOUBLE = FinanceLogicalType(LogicalTypeId::DOUBLE);
	const auto BOOLEAN = FinanceLogicalType(LogicalTypeId::BOOLEAN);
	const auto BIGINT = FinanceLogicalType(LogicalTypeId::BIGINT);
	const auto vector_type = LogicalType::LIST(DOUBLE);
	const auto matrix_type = LogicalType::LIST(vector_type);
	auto add = [&](const string &name, vector<LogicalType> arguments, scalar_function_t function) {
		ScalarFunction scalar(FinanceFunctionName(name), std::move(arguments), vector_type, std::move(function));
		scalar.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
		loader.RegisterFunction(std::move(scalar));
	};
	add("finance_min_variance_weights_internal", {matrix_type, BOOLEAN},
	    PortfolioWeightsFunction<PortfolioKernel::MIN_VARIANCE>);
	add("finance_max_sharpe_weights_internal", {vector_type, matrix_type, DOUBLE, BOOLEAN},
	    PortfolioWeightsFunction<PortfolioKernel::MAX_SHARPE>);
	add("finance_risk_parity_weights_internal", {matrix_type, vector_type, DOUBLE, BIGINT},
	    PortfolioWeightsFunction<PortfolioKernel::RISK_PARITY>);
	add("finance_black_litterman_internal",
	    {vector_type, matrix_type, matrix_type, vector_type, DOUBLE, matrix_type, DOUBLE},
	    PortfolioWeightsFunction<PortfolioKernel::BLACK_LITTERMAN>);
}
