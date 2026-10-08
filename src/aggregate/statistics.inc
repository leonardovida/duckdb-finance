// Native statistical tests, association measures and ordered time-series
// diagnostics. Most of these need the whole sample (ranks, sorting, lags), so
// they keep a flat row history, merge histories in Combine and compute in
// Finalize. Results never depend on thread count or physical row order:
// ordered statistics sort by an explicit ordering key (ties broken by value),
// and unordered ones sort their inputs before computing.
//
// Policy shared by every operation here: NULL rows are skipped; a NaN or
// infinite input makes the group's result NULL; degenerate samples (too few
// rows, zero variance, singular regressions) return NULL rather than NaN/inf.

//===--------------------------------------------------------------------===//
// Special functions
//===--------------------------------------------------------------------===//
static double StatNaN() {
	return std::numeric_limits<double>::quiet_NaN();
}

// Continued fraction for the regularized incomplete beta (modified Lentz).
static double StatBetaContinuedFraction(double a, double b, double x) {
	constexpr int MAX_ITER = 10000;
	constexpr double EPS = 1e-16;
	constexpr double TINY = 1e-300;
	double qab = a + b, qap = a + 1.0, qam = a - 1.0;
	double c = 1.0;
	double d = 1.0 - qab * x / qap;
	if (std::fabs(d) < TINY) {
		d = TINY;
	}
	d = 1.0 / d;
	double h = d;
	for (int m = 1; m <= MAX_ITER; m++) {
		int m2 = 2 * m;
		double aa = m * (b - m) * x / ((qam + m2) * (a + m2));
		d = 1.0 + aa * d;
		d = std::fabs(d) < TINY ? TINY : d;
		c = 1.0 + aa / c;
		c = std::fabs(c) < TINY ? TINY : c;
		d = 1.0 / d;
		h *= d * c;
		aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
		d = 1.0 + aa * d;
		d = std::fabs(d) < TINY ? TINY : d;
		c = 1.0 + aa / c;
		c = std::fabs(c) < TINY ? TINY : c;
		d = 1.0 / d;
		double del = d * c;
		h *= del;
		if (std::fabs(del - 1.0) <= EPS) {
			break;
		}
	}
	return h;
}

// Regularized incomplete beta I_x(a, b).
static double StatIncompleteBeta(double a, double b, double x) {
	if (!(a > 0.0) || !(b > 0.0) || !(x >= 0.0) || !(x <= 1.0)) {
		return StatNaN();
	}
	if (x == 0.0 || x == 1.0) {
		return x;
	}
	double log_front = std::lgamma(a + b) - std::lgamma(a) - std::lgamma(b) + a * std::log(x) + b * std::log1p(-x);
	double front = std::exp(log_front);
	if (x < (a + 1.0) / (a + b + 2.0)) {
		return front * StatBetaContinuedFraction(a, b, x) / a;
	}
	return 1.0 - front * StatBetaContinuedFraction(b, a, 1.0 - x) / b;
}

// Upper tail of the F distribution P(F >= f).
static double StatFSurvival(double f, double d1, double d2) {
	if (!(f >= 0.0) || !std::isfinite(f) || !(d1 > 0.0) || !(d2 > 0.0)) {
		return StatNaN();
	}
	return StatIncompleteBeta(0.5 * d2, 0.5 * d1, d2 / (d2 + d1 * f));
}

// Regularized upper incomplete gamma Q(a, x).
static double StatGammaQ(double a, double x) {
	if (!(a > 0.0) || !(x >= 0.0)) {
		return StatNaN();
	}
	if (x == 0.0) {
		return 1.0;
	}
	if (!std::isfinite(x)) {
		return 0.0;
	}
	const double log_front = -x + a * std::log(x) - std::lgamma(a);
	if (x < a + 1.0) {
		double ap = a, sum = 1.0 / a, del = sum;
		for (int n = 0; n < 100000; n++) {
			ap += 1.0;
			del *= x / ap;
			sum += del;
			if (std::fabs(del) < std::fabs(sum) * 1e-16) {
				break;
			}
		}
		return std::max(0.0, 1.0 - sum * std::exp(log_front));
	}
	constexpr double TINY = 1e-300;
	double b = x + 1.0 - a, c = 1.0 / TINY, d = 1.0 / b, h = d;
	for (int i = 1; i < 100000; i++) {
		double an = -i * (i - a);
		b += 2.0;
		d = an * d + b;
		d = std::fabs(d) < TINY ? TINY : d;
		c = b + an / c;
		c = std::fabs(c) < TINY ? TINY : c;
		d = 1.0 / d;
		double del = d * c;
		h *= del;
		if (std::fabs(del - 1.0) < 1e-16) {
			break;
		}
	}
	return std::exp(log_front) * h;
}

static double StatChiSquareSurvival(double x, double df) {
	return StatGammaQ(0.5 * df, 0.5 * x);
}

static double StatNormalSurvival(double z) {
	return 0.5 * std::erfc(z / std::sqrt(2.0));
}

static double StatNormalCdf(double z) {
	return 0.5 * std::erfc(-z / std::sqrt(2.0));
}

// Kolmogorov limiting distribution Q_KS(lambda) = P(K > lambda).
static double StatKolmogorovSurvival(double lambda) {
	if (!(lambda > 0.0)) {
		return 1.0;
	}
	constexpr double PI = 3.14159265358979323846;
	if (lambda < 1.18) {
		// P(K <= lambda) = sqrt(2 pi) / lambda * sum exp(-(2j-1)^2 pi^2 / (8 lambda^2)).
		double y = std::exp(-PI * PI / (8.0 * lambda * lambda));
		double sum = 0.0;
		for (int j = 1; j <= 200; j++) {
			double term = std::pow(y, double((2 * j - 1) * (2 * j - 1)));
			sum += term;
			if (term < 1e-17 * sum) {
				break;
			}
		}
		return std::min(1.0, std::max(0.0, 1.0 - std::sqrt(2.0 * PI) / lambda * sum));
	}
	double sum = 0.0;
	for (int j = 1; j <= 200; j++) {
		double term = std::exp(-2.0 * j * j * lambda * lambda);
		sum += (j % 2 == 1 ? 2.0 : -2.0) * term;
		if (term < 1e-17) {
			break;
		}
	}
	return std::min(1.0, std::max(0.0, sum));
}

// Average (fractional) ranks, 1-based, of values; ties share their mean rank.
// Also returns the tie correction sum of (t^3 - t) over tie groups.
static double StatAverageRanks(const vector<double> &values, vector<double> &ranks) {
	const idx_t n = values.size();
	vector<idx_t> order(n);
	for (idx_t i = 0; i < n; i++) {
		order[i] = i;
	}
	std::sort(order.begin(), order.end(), [&](idx_t l, idx_t r) { return values[l] < values[r]; });
	ranks.assign(n, 0.0);
	double ties = 0.0;
	idx_t i = 0;
	while (i < n) {
		idx_t j = i + 1;
		while (j < n && values[order[j]] == values[order[i]]) {
			j++;
		}
		double rank = 0.5 * double(i + 1 + j);
		for (idx_t k = i; k < j; k++) {
			ranks[order[k]] = rank;
		}
		double t = double(j - i);
		ties += t * t * t - t;
		i = j;
	}
	return ties;
}

// Pearson correlation; NaN for fewer than two pairs or zero variance.
static double StatPearson(const double *x, const double *y, idx_t n, idx_t stride_x = 1, idx_t stride_y = 1) {
	if (n < 2) {
		return StatNaN();
	}
	double mx = 0.0, my = 0.0;
	for (idx_t i = 0; i < n; i++) {
		mx += x[i * stride_x];
		my += y[i * stride_y];
	}
	mx /= double(n);
	my /= double(n);
	double sxx = 0.0, syy = 0.0, sxy = 0.0;
	for (idx_t i = 0; i < n; i++) {
		double dx = x[i * stride_x] - mx, dy = y[i * stride_y] - my;
		sxx += dx * dx;
		syy += dy * dy;
		sxy += dx * dy;
	}
	if (!(sxx > 0.0) || !(syy > 0.0)) {
		return StatNaN();
	}
	return std::max(-1.0, std::min(1.0, sxy / std::sqrt(sxx * syy)));
}

//===--------------------------------------------------------------------===//
// Dense linear algebra for small least-squares problems
//===--------------------------------------------------------------------===//
// Inverts a symmetric positive-definite k x k matrix (row-major) in place via
// Cholesky. Returns false when a pivot is not safely positive.
static bool StatInvertSPD(vector<double> &a, idx_t k) {
	vector<double> l(k * k, 0.0);
	double scale = 0.0;
	for (idx_t i = 0; i < k; i++) {
		scale = std::max(scale, std::fabs(a[i * k + i]));
	}
	if (!(scale > 0.0) || !std::isfinite(scale)) {
		return false;
	}
	for (idx_t j = 0; j < k; j++) {
		double diag = a[j * k + j];
		for (idx_t p = 0; p < j; p++) {
			diag -= l[j * k + p] * l[j * k + p];
		}
		if (!(diag > 1e-13 * scale)) {
			return false;
		}
		l[j * k + j] = std::sqrt(diag);
		for (idx_t i = j + 1; i < k; i++) {
			double value = a[i * k + j];
			for (idx_t p = 0; p < j; p++) {
				value -= l[i * k + p] * l[j * k + p];
			}
			l[i * k + j] = value / l[j * k + j];
		}
	}
	// inverse(L) then inverse(A) = inverse(L)^T inverse(L).
	vector<double> li(k * k, 0.0);
	for (idx_t i = 0; i < k; i++) {
		li[i * k + i] = 1.0 / l[i * k + i];
		for (idx_t j = 0; j < i; j++) {
			double sum = 0.0;
			for (idx_t p = j; p < i; p++) {
				sum += l[i * k + p] * li[p * k + j];
			}
			li[i * k + j] = -sum / l[i * k + i];
		}
	}
	for (idx_t i = 0; i < k; i++) {
		for (idx_t j = 0; j <= i; j++) {
			double sum = 0.0;
			for (idx_t p = i; p < k; p++) {
				sum += li[p * k + i] * li[p * k + j];
			}
			a[i * k + j] = sum;
			a[j * k + i] = sum;
		}
	}
	return true;
}

// Ordinary least squares on a dense row-major design (n x k). Fills the
// coefficients, their conventional standard errors and residuals. Returns
// false for n <= k or a singular design.
static bool StatLeastSquares(const vector<double> &x, const vector<double> &y, idx_t n, idx_t k, vector<double> &beta,
                             vector<double> &stderr_out, vector<double> &residuals, vector<double> *xtx_inv_out = nullptr) {
	if (n <= k) {
		return false;
	}
	// Column scaling keeps the normal equations well conditioned for trend columns.
	vector<double> scale(k, 0.0);
	for (idx_t j = 0; j < k; j++) {
		double s = 0.0;
		for (idx_t i = 0; i < n; i++) {
			s = std::max(s, std::fabs(x[i * k + j]));
		}
		scale[j] = s > 0.0 ? s : 1.0;
	}
	vector<double> xtx(k * k, 0.0), xty(k, 0.0);
	for (idx_t i = 0; i < n; i++) {
		const double *row = &x[i * k];
		for (idx_t a = 0; a < k; a++) {
			double xa = row[a] / scale[a];
			xty[a] += xa * y[i];
			for (idx_t b = 0; b <= a; b++) {
				xtx[a * k + b] += xa * row[b] / scale[b];
			}
		}
	}
	for (idx_t a = 0; a < k; a++) {
		for (idx_t b = 0; b < a; b++) {
			xtx[b * k + a] = xtx[a * k + b];
		}
	}
	if (!StatInvertSPD(xtx, k)) {
		return false;
	}
	beta.assign(k, 0.0);
	for (idx_t a = 0; a < k; a++) {
		double sum = 0.0;
		for (idx_t b = 0; b < k; b++) {
			sum += xtx[a * k + b] * xty[b];
		}
		beta[a] = sum;
	}
	residuals.assign(n, 0.0);
	double ssr = 0.0;
	for (idx_t i = 0; i < n; i++) {
		double fit = 0.0;
		for (idx_t a = 0; a < k; a++) {
			fit += x[i * k + a] / scale[a] * beta[a];
		}
		residuals[i] = y[i] - fit;
		ssr += residuals[i] * residuals[i];
	}
	double sigma2 = ssr / double(n - k);
	stderr_out.assign(k, 0.0);
	for (idx_t a = 0; a < k; a++) {
		stderr_out[a] = std::sqrt(sigma2 * xtx[a * k + a]) / scale[a];
		beta[a] /= scale[a];
	}
	if (xtx_inv_out) {
		xtx_inv_out->assign(k * k, 0.0);
		for (idx_t a = 0; a < k; a++) {
			for (idx_t b = 0; b < k; b++) {
				(*xtx_inv_out)[a * k + b] = xtx[a * k + b] / (scale[a] * scale[b]);
			}
		}
	}
	return true;
}

//===--------------------------------------------------------------------===//
// History state shared by the operations in this file
//===--------------------------------------------------------------------===//
struct StatHistoryState {
	vector<double> *data;
	FinWindowAux *window;
	double params[3];
	bool params_set;
	bool invalid;
};

struct StatHistoryBase : public FinOperationDefaults {
	static constexpr bool ORDER_DEPENDENT = false;
	static constexpr bool WINDOW_INCREMENTAL = true;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.data = new vector<double>();
		state.window = nullptr;
		WindowReset(state);
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		state.data->clear();
		state.params[0] = state.params[1] = state.params[2] = 0.0;
		state.params_set = false;
		state.invalid = false;
	}

	template <class STATE>
	static void SetParams(STATE &state, const double *params, idx_t count, const char *name) {
		if (state.params_set) {
			for (idx_t i = 0; i < count; i++) {
				if (state.params[i] != params[i]) {
					throw InvalidInputException("%s: parameters must be constant within a group", name);
				}
			}
			return;
		}
		for (idx_t i = 0; i < count; i++) {
			state.params[i] = params[i];
		}
		state.params_set = true;
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.invalid = target.invalid || source.invalid;
		if (source.params_set) {
			if (target.params_set && (target.params[0] != source.params[0] || target.params[1] != source.params[1] ||
			                          target.params[2] != source.params[2])) {
				throw InvalidInputException("Aggregate parameters must be constant within a group");
			}
			target.params[0] = source.params[0];
			target.params[1] = source.params[1];
			target.params[2] = source.params[2];
			target.params_set = true;
		}
		target.data->insert(target.data->end(), source.data->begin(), source.data->end());
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.data;
		state.data = nullptr;
		delete state.window;
		state.window = nullptr;
	}
};

// Bind for internal aggregates called from SQL macros: validates constant
// configuration once (so invalid settings fail even on empty input). Macro
// parameters arrive positionally, so named-argument rejection does not apply.
template <class OP>
static unique_ptr<FunctionData> StatInternalBind(ClientContext &context, AggregateFunction &function,
                                                 vector<unique_ptr<Expression>> &arguments) {
	for (idx_t c = OP::CONFIG_START; c < arguments.size(); c++) {
		auto &argument = *arguments[c];
		if (!argument.IsFoldable()) {
			continue;
		}
		auto value = ExpressionExecutor::EvaluateScalar(context, argument, true);
		if (value.IsNull()) {
			OP::ValidateParameter(c, StatNaN(), false);
			continue;
		}
		if (function.arguments[c].id() == LogicalTypeId::VARCHAR) {
			auto text = StringValue::Get(value.DefaultCastAs(LogicalType::VARCHAR));
			OP::ValidateParameter(c, OP::ParseText(c, string_t(text.c_str(), static_cast<uint32_t>(text.size()))), true);
		} else if (function.arguments[c].id() == LogicalTypeId::BOOLEAN) {
			OP::ValidateParameter(c, BooleanValue::Get(value.DefaultCastAs(LogicalType::BOOLEAN)) ? 1.0 : 0.0, true);
		} else {
			OP::ValidateParameter(c, DoubleValue::Get(value.DefaultCastAs(LogicalType::DOUBLE)), true);
		}
	}
	return nullptr;
}

static void StatRequireInteger(const char *name, const char *parameter, double value, bool valid, double minimum) {
	if (!valid || !std::isfinite(value) || value != std::floor(value) || value < minimum) {
		throw InvalidInputException("%s: %s must be an integer >= %lld", name, parameter,
		                            static_cast<long long>(minimum));
	}
}

// Finalize for operations that return a STRUCT of DOUBLE fields.
template <class STATE, class OP>
static void StatStructFinalize(Vector &states, AggregateInputData &, Vector &result, idx_t count, idx_t offset) {
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(states, count, sdata);
	auto state_ptrs = UnifiedVectorFormat::GetData<STATE *>(sdata);
	auto names = OP::FieldNames();
	vector<double> fields(names.size());
	for (idx_t i = 0; i < count; i++) {
		auto &state = *state_ptrs[sdata.sel->get_index(i)];
		std::fill(fields.begin(), fields.end(), StatNaN());
		Value value;
		if (!state.invalid && OP::Compute(state, fields.data())) {
			child_list_t<Value> children;
			for (idx_t f = 0; f < names.size(); f++) {
				children.emplace_back(names[f], std::isfinite(fields[f]) ? Value::DOUBLE(fields[f])
				                                                          : Value(LogicalType::DOUBLE));
			}
			value = Value::STRUCT(std::move(children));
		} else {
			value = Value(OP::ReturnType());
		}
		result.SetValue(i + offset, value);
	}
}

template <class OP>
static LogicalType StatStructType() {
	child_list_t<LogicalType> children;
	for (auto &name : OP::FieldNames()) {
		children.emplace_back(name, LogicalType::DOUBLE);
	}
	return LogicalType::STRUCT(std::move(children));
}

// Scalar DOUBLE finalize for history operations.
struct StatScalarFinalizeMixin {
	template <class T, class STATE, class OP_SELF>
	static void FinalizeWith(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		double out = StatNaN();
		if (state.invalid || !OP_SELF::ComputeScalar(state, out) || !std::isfinite(out)) {
			finalize_data.ReturnNull();
			return;
		}
		target = out;
	}
};

template <class STATE, class OP>
static AggregateFunction StatStructAggregate(const string &name, vector<LogicalType> arguments) {
	AggregateFunction result(std::move(arguments), OP::ReturnType(), AggregateFunction::StateSize<STATE>,
	                         AggregateFunction::StateInitialize<STATE, OP, AggregateDestructorType::LEGACY>,
	                         FinScatterUpdate<STATE, OP>, AggregateFunction::StateCombine<STATE, OP>,
	                         StatStructFinalize<STATE, OP>, FunctionNullHandling::SPECIAL_HANDLING,
	                         FinSimpleUpdate<STATE, OP>);
	result.SetStateDestructorCallback(AggregateFunction::StateDestroy<STATE, OP>);
	result.SetBindCallback(StatInternalBind<OP>);
	result.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	result.name = FinanceFunctionName(name);
	return result;
}

template <class STATE, class OP>
static AggregateFunction StatScalarAggregate(const string &name, vector<LogicalType> arguments) {
	auto result = FinWindowAggregate<STATE, OP>(name, std::move(arguments));
	result.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	result.SetBindCallback(StatInternalBind<OP>);
	return result;
}

// Splits two-column (value, sample id) history into the two samples.
static void StatSplitSamples(const vector<double> &data, vector<double> &x, vector<double> &y) {
	x.clear();
	y.clear();
	for (idx_t i = 0; i + 1 < data.size(); i += 2) {
		(data[i + 1] == 0.0 ? x : y).push_back(data[i]);
	}
}

//===--------------------------------------------------------------------===//
// Two-sample tests: x and y are separate columns whose NULLs are independent
//===--------------------------------------------------------------------===//
struct TwoSampleBase : public StatHistoryBase {
	static constexpr idx_t REQUIRED_ARGS = 0;
	static constexpr idx_t CONFIG_START = 2;
	static bool NullableArgument(idx_t) {
		return true;
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t) {
		for (idx_t c = 0; c < 2; c++) {
			if (!row.valid[c]) {
				continue;
			}
			if (!std::isfinite(row.v[c])) {
				state.invalid = true;
				continue;
			}
			state.data->push_back(row.v[c]);
			state.data->push_back(double(c));
		}
	}
};

// Two-sample Kolmogorov-Smirnov: D = sup |F_x - F_y|; p-value from the
// Kolmogorov limit distribution with Stephens' small-sample correction,
// Q_KS((sqrt(ne) + 0.12 + 0.11 / sqrt(ne)) * D), ne = n m / (n + m).
struct KSTestOperation : public TwoSampleBase {
	static vector<string> FieldNames() {
		return {"stat", "pvalue"};
	}
	static LogicalType ReturnType() {
		return StatStructType<KSTestOperation>();
	}
	template <class STATE>
	static bool Compute(STATE &state, double *out) {
		vector<double> x, y;
		StatSplitSamples(*state.data, x, y);
		if (x.empty() || y.empty()) {
			return false;
		}
		std::sort(x.begin(), x.end());
		std::sort(y.begin(), y.end());
		const double n = double(x.size()), m = double(y.size());
		idx_t i = 0, j = 0;
		double d = 0.0;
		while (i < x.size() && j < y.size()) {
			double value = std::min(x[i], y[j]);
			while (i < x.size() && x[i] == value) {
				i++;
			}
			while (j < y.size() && y[j] == value) {
				j++;
			}
			d = std::max(d, std::fabs(double(i) / n - double(j) / m));
		}
		const double ne = n * m / (n + m);
		const double sqrt_ne = std::sqrt(ne);
		out[0] = d;
		out[1] = StatKolmogorovSurvival((sqrt_ne + 0.12 + 0.11 / sqrt_ne) * d);
		return true;
	}
};

// Mann-Whitney U for x: U = R_x - n_x (n_x + 1) / 2 with average ranks.
// Two-sided p-value from the normal approximation with tie and continuity
// correction (scipy.stats.mannwhitneyu(method='asymptotic')).
struct MannWhitneyOperation : public TwoSampleBase {
	static vector<string> FieldNames() {
		return {"stat", "pvalue"};
	}
	static LogicalType ReturnType() {
		return StatStructType<MannWhitneyOperation>();
	}
	template <class STATE>
	static bool Compute(STATE &state, double *out) {
		const auto &data = *state.data;
		const idx_t total = data.size() / 2;
		vector<double> values(total);
		double n1 = 0.0;
		for (idx_t i = 0; i < total; i++) {
			values[i] = data[2 * i];
			n1 += data[2 * i + 1] == 0.0 ? 1.0 : 0.0;
		}
		const double n2 = double(total) - n1;
		if (n1 < 1.0 || n2 < 1.0) {
			return false;
		}
		vector<double> ranks;
		auto ties = StatAverageRanks(values, ranks);
		double r1 = 0.0;
		for (idx_t i = 0; i < total; i++) {
			if (data[2 * i + 1] == 0.0) {
				r1 += ranks[i];
			}
		}
		const double u1 = r1 - n1 * (n1 + 1.0) / 2.0;
		out[0] = u1;
		const double n = n1 + n2;
		const double mu = n1 * n2 / 2.0;
		const double variance = n1 * n2 / 12.0 * ((n + 1.0) - ties / (n * (n - 1.0)));
		if (variance > 0.0) {
			const double u = std::max(u1, n1 * n2 - u1);
			const double z = (u - mu - 0.5) / std::sqrt(variance);
			out[1] = std::min(1.0, 2.0 * StatNormalSurvival(z));
		}
		return true;
	}
};

//===--------------------------------------------------------------------===//
// One-way ANOVA over (value, group code)
//===--------------------------------------------------------------------===//
struct AnovaOperation : public StatHistoryBase {
	static constexpr idx_t REQUIRED_ARGS = 2;
	static constexpr idx_t CONFIG_START = 2;
	static vector<string> FieldNames() {
		return {"f_stat", "pvalue", "df_between", "df_within"};
	}
	static LogicalType ReturnType() {
		return StatStructType<AnovaOperation>();
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t) {
		if (!std::isfinite(row.v[0])) {
			state.invalid = true;
			return;
		}
		state.data->push_back(row.v[1]);
		state.data->push_back(row.v[0]);
	}
	template <class STATE>
	static bool Compute(STATE &state, double *out) {
		auto &data = *state.data;
		const idx_t n = data.size() / 2;
		vector<std::pair<double, double>> rows(n);
		for (idx_t i = 0; i < n; i++) {
			rows[i] = {data[2 * i], data[2 * i + 1]};
		}
		std::sort(rows.begin(), rows.end());
		double grand = 0.0;
		for (auto &row : rows) {
			grand += row.second;
		}
		grand /= double(n);
		double ssb = 0.0, ssw = 0.0, groups = 0.0;
		idx_t i = 0;
		while (i < n) {
			idx_t j = i;
			double mean = 0.0;
			while (j < n && rows[j].first == rows[i].first) {
				mean += rows[j].second;
				j++;
			}
			double size = double(j - i);
			mean /= size;
			for (idx_t k = i; k < j; k++) {
				ssw += (rows[k].second - mean) * (rows[k].second - mean);
			}
			ssb += size * (mean - grand) * (mean - grand);
			groups += 1.0;
			i = j;
		}
		const double df_between = groups - 1.0, df_within = double(n) - groups;
		if (df_between < 1.0 || df_within < 1.0 || !(ssw > 0.0)) {
			return false;
		}
		out[0] = (ssb / df_between) / (ssw / df_within);
		out[1] = StatFSurvival(out[0], df_between, df_within);
		out[2] = df_between;
		out[3] = df_within;
		return true;
	}
};

//===--------------------------------------------------------------------===//
// Paired correlation: Spearman, Kendall tau-b or Pearson
//===--------------------------------------------------------------------===//
enum class StatCorrMethod : uint8_t { SPEARMAN = 0, KENDALL = 1, PEARSON = 2 };

// Kendall tau-b in O(n log n) (Knight 1966), as in scipy.stats.kendalltau.
static double StatKendallTauB(vector<std::pair<double, double>> &pairs) {
	const idx_t n = pairs.size();
	if (n < 2) {
		return StatNaN();
	}
	std::sort(pairs.begin(), pairs.end());
	auto tie_count = [](const vector<double> &sorted) {
		double count = 0.0;
		idx_t i = 0;
		while (i < sorted.size()) {
			idx_t j = i + 1;
			while (j < sorted.size() && sorted[j] == sorted[i]) {
				j++;
			}
			double t = double(j - i);
			count += t * (t - 1.0) / 2.0;
			i = j;
		}
		return count;
	};
	vector<double> xs(n), ys(n);
	for (idx_t i = 0; i < n; i++) {
		xs[i] = pairs[i].first;
		ys[i] = pairs[i].second;
	}
	const double x_ties = tie_count(xs);
	double joint_ties = 0.0;
	{
		idx_t i = 0;
		while (i < n) {
			idx_t j = i + 1;
			while (j < n && pairs[j] == pairs[i]) {
				j++;
			}
			double t = double(j - i);
			joint_ties += t * (t - 1.0) / 2.0;
			i = j;
		}
	}
	// Count discordant pairs as inversions of y in (x, y) order with a merge sort.
	double swaps = 0.0;
	vector<double> buffer(n);
	for (idx_t width = 1; width < n; width *= 2) {
		for (idx_t lo = 0; lo < n; lo += 2 * width) {
			idx_t mid = std::min(lo + width, n), hi = std::min(lo + 2 * width, n);
			idx_t a = lo, b = mid, k = lo;
			while (a < mid && b < hi) {
				if (ys[b] < ys[a]) {
					swaps += double(mid - a);
					buffer[k++] = ys[b++];
				} else {
					buffer[k++] = ys[a++];
				}
			}
			while (a < mid) {
				buffer[k++] = ys[a++];
			}
			while (b < hi) {
				buffer[k++] = ys[b++];
			}
		}
		std::swap(ys, buffer);
	}
	const double y_ties = tie_count(ys);
	const double total = double(n) * double(n - 1) / 2.0;
	const double denominator = std::sqrt((total - x_ties) * (total - y_ties));
	if (!(denominator > 0.0)) {
		return StatNaN();
	}
	const double concordant_minus_discordant = total - x_ties - y_ties + joint_ties - 2.0 * swaps;
	return std::max(-1.0, std::min(1.0, concordant_minus_discordant / denominator));
}

static double StatCorrelation(vector<std::pair<double, double>> &pairs, StatCorrMethod method) {
	const idx_t n = pairs.size();
	if (n < 2) {
		return StatNaN();
	}
	if (method == StatCorrMethod::KENDALL) {
		return StatKendallTauB(pairs);
	}
	vector<double> x(n), y(n);
	for (idx_t i = 0; i < n; i++) {
		x[i] = pairs[i].first;
		y[i] = pairs[i].second;
	}
	if (method == StatCorrMethod::PEARSON) {
		return StatPearson(x.data(), y.data(), n);
	}
	vector<double> rx, ry;
	StatAverageRanks(x, rx);
	StatAverageRanks(y, ry);
	return StatPearson(rx.data(), ry.data(), n);
}

// WHICH: 0 = fin_rank_corr (spearman, kendall), 1 = fin_factor_ic (spearman, pearson, kendall).
template <int WHICH>
struct CorrelationOperation : public StatHistoryBase {
	static constexpr idx_t REQUIRED_ARGS = 2;
	static constexpr idx_t CONFIG_START = 2;
	static const char *Name() {
		return WHICH == 0 ? "fin_rank_corr" : "fin_factor_ic";
	}
	static double ParseText(idx_t, string_t text) {
		if (FinTextEquals(text, "spearman")) {
			return double(StatCorrMethod::SPEARMAN);
		}
		if (FinTextEquals(text, "kendall")) {
			return double(StatCorrMethod::KENDALL);
		}
		if (WHICH == 1 && FinTextEquals(text, "pearson")) {
			return double(StatCorrMethod::PEARSON);
		}
		throw InvalidInputException("%s: unknown method '%s' (expected %s)", Name(), text.GetString(),
		                            WHICH == 0 ? "'spearman' or 'kendall'" : "'spearman', 'pearson' or 'kendall'");
	}
	static void ValidateParameter(idx_t, double, bool valid) {
		if (!valid) {
			throw InvalidInputException("%s: method must not be NULL", Name());
		}
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double method = input_count > 2 ? row.v[2] : 0.0;
		SetParams(state, &method, 1, Name());
		if (!std::isfinite(row.v[0]) || !std::isfinite(row.v[1])) {
			state.invalid = true;
			return;
		}
		state.data->push_back(row.v[0]);
		state.data->push_back(row.v[1]);
	}
	template <class STATE>
	static bool ComputeScalar(STATE &state, double &out) {
		auto &data = *state.data;
		vector<std::pair<double, double>> pairs(data.size() / 2);
		for (idx_t i = 0; i < pairs.size(); i++) {
			pairs[i] = {data[2 * i], data[2 * i + 1]};
		}
		out = StatCorrelation(pairs, StatCorrMethod(int(state.params[0])));
		return true;
	}
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		StatScalarFinalizeMixin::FinalizeWith<T, STATE, CorrelationOperation>(state, target, finalize_data);
	}
};

//===--------------------------------------------------------------------===//
// Binned mutual information (nats)
//===--------------------------------------------------------------------===//
struct MutualInformationOperation : public StatHistoryBase {
	static constexpr idx_t REQUIRED_ARGS = 2;
	static constexpr idx_t CONFIG_START = 2;
	static void ValidateParameter(idx_t, double value, bool valid) {
		StatRequireInteger("fin_mutual_information", "bins", value, valid, 1.0);
		if (value > 100000.0) {
			throw InvalidInputException("fin_mutual_information: bins must be <= 100000");
		}
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double bins = input_count > 2 ? row.v[2] : 10.0;
		if (!state.params_set) {
			ValidateParameter(2, bins, true);
		}
		SetParams(state, &bins, 1, "fin_mutual_information");
		if (!std::isfinite(row.v[0]) || !std::isfinite(row.v[1])) {
			state.invalid = true;
			return;
		}
		state.data->push_back(row.v[0]);
		state.data->push_back(row.v[1]);
	}
	static idx_t Bin(double value, double lo, double hi, idx_t bins) {
		if (!(hi > lo)) {
			return 0;
		}
		auto index = static_cast<idx_t>(std::floor((value - lo) / (hi - lo) * double(bins)));
		return std::min(index, bins - 1);
	}
	template <class STATE>
	static bool ComputeScalar(STATE &state, double &out) {
		auto &data = *state.data;
		const idx_t n = data.size() / 2;
		if (n == 0) {
			return false;
		}
		const auto bins = static_cast<idx_t>(state.params[0]);
		double xlo = data[0], xhi = data[0], ylo = data[1], yhi = data[1];
		for (idx_t i = 0; i < n; i++) {
			xlo = std::min(xlo, data[2 * i]);
			xhi = std::max(xhi, data[2 * i]);
			ylo = std::min(ylo, data[2 * i + 1]);
			yhi = std::max(yhi, data[2 * i + 1]);
		}
		vector<std::pair<idx_t, idx_t>> cells(n);
		vector<double> px(bins, 0.0), py(bins, 0.0);
		for (idx_t i = 0; i < n; i++) {
			cells[i] = {Bin(data[2 * i], xlo, xhi, bins), Bin(data[2 * i + 1], ylo, yhi, bins)};
			px[cells[i].first] += 1.0;
			py[cells[i].second] += 1.0;
		}
		std::sort(cells.begin(), cells.end());
		const double total = double(n);
		double mi = 0.0;
		idx_t i = 0;
		while (i < n) {
			idx_t j = i + 1;
			while (j < n && cells[j] == cells[i]) {
				j++;
			}
			double joint = double(j - i);
			mi += joint / total * std::log(joint * total / (px[cells[i].first] * py[cells[i].second]));
			i = j;
		}
		out = std::max(0.0, mi);
		return true;
	}
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		StatScalarFinalizeMixin::FinalizeWith<T, STATE, MutualInformationOperation>(state, target, finalize_data);
	}
};

//===--------------------------------------------------------------------===//
// Categorical association over hashed category codes
//===--------------------------------------------------------------------===//
struct StatContingency {
	double n = 0.0;
	vector<double> row_totals, col_totals;
	// (row index, col index, count) for non-empty cells
	vector<std::tuple<idx_t, idx_t, double>> cells;
};

static void StatBuildContingency(const vector<double> &data, StatContingency &table) {
	const idx_t n = data.size() / 2;
	table.n = double(n);
	auto index_of = [&](idx_t column, vector<double> &totals, vector<idx_t> &codes) {
		vector<double> keys(n);
		for (idx_t i = 0; i < n; i++) {
			keys[i] = data[2 * i + column];
		}
		vector<double> sorted = keys;
		std::sort(sorted.begin(), sorted.end());
		sorted.erase(std::unique(sorted.begin(), sorted.end()), sorted.end());
		totals.assign(sorted.size(), 0.0);
		codes.resize(n);
		for (idx_t i = 0; i < n; i++) {
			codes[i] = static_cast<idx_t>(std::lower_bound(sorted.begin(), sorted.end(), keys[i]) - sorted.begin());
			totals[codes[i]] += 1.0;
		}
	};
	vector<idx_t> rows, cols;
	index_of(0, table.row_totals, rows);
	index_of(1, table.col_totals, cols);
	vector<std::pair<idx_t, idx_t>> pairs(n);
	for (idx_t i = 0; i < n; i++) {
		pairs[i] = {rows[i], cols[i]};
	}
	std::sort(pairs.begin(), pairs.end());
	table.cells.clear();
	idx_t i = 0;
	while (i < n) {
		idx_t j = i + 1;
		while (j < n && pairs[j] == pairs[i]) {
			j++;
		}
		table.cells.emplace_back(pairs[i].first, pairs[i].second, double(j - i));
		i = j;
	}
}

// WHICH: 0 = Cramer's V (optional Bergsma bias correction), 1 = Theil's U(x | y).
template <int WHICH>
struct CategoricalAssociationOperation : public StatHistoryBase {
	static constexpr idx_t REQUIRED_ARGS = 2;
	static constexpr idx_t CONFIG_START = 2;
	static const char *Name() {
		return WHICH == 0 ? "fin_cramers_v" : "fin_theils_u";
	}
	static void ValidateParameter(idx_t, double, bool valid) {
		if (!valid) {
			throw InvalidInputException("%s: bias_corrected must not be NULL", Name());
		}
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double corrected = input_count > 2 ? row.v[2] : 1.0;
		SetParams(state, &corrected, 1, Name());
		state.data->push_back(row.v[0]);
		state.data->push_back(row.v[1]);
	}
	template <class STATE>
	static bool ComputeScalar(STATE &state, double &out) {
		if (state.data->empty()) {
			return false;
		}
		StatContingency table;
		StatBuildContingency(*state.data, table);
		const double n = table.n;
		const double r = double(table.row_totals.size()), k = double(table.col_totals.size());
		if (WHICH == 0) {
			double sum = 0.0;
			for (auto &cell : table.cells) {
				double observed = std::get<2>(cell);
				sum += observed * observed / (table.row_totals[std::get<0>(cell)] * table.col_totals[std::get<1>(cell)]);
			}
			const double phi2 = std::max(0.0, sum - 1.0);
			if (state.params[0] != 0.0) {
				if (n < 2.0) {
					return false;
				}
				const double phi2_corrected = std::max(0.0, phi2 - (k - 1.0) * (r - 1.0) / (n - 1.0));
				const double r_corrected = r - (r - 1.0) * (r - 1.0) / (n - 1.0);
				const double k_corrected = k - (k - 1.0) * (k - 1.0) / (n - 1.0);
				const double denominator = std::min(k_corrected - 1.0, r_corrected - 1.0);
				if (!(denominator > 0.0)) {
					return false;
				}
				out = std::sqrt(phi2_corrected / denominator);
			} else {
				const double denominator = std::min(k - 1.0, r - 1.0);
				if (!(denominator > 0.0)) {
					return false;
				}
				out = std::sqrt(phi2 / denominator);
			}
			out = std::min(1.0, out);
			return true;
		}
		// Theil's U: (H(x) - H(x | y)) / H(x), natural logarithms.
		double hx = 0.0;
		for (auto total : table.row_totals) {
			hx -= total / n * std::log(total / n);
		}
		if (!(hx > 0.0)) {
			return false;
		}
		double hxy = 0.0;
		for (auto &cell : table.cells) {
			double joint = std::get<2>(cell);
			hxy -= joint / n * std::log(joint / table.col_totals[std::get<1>(cell)]);
		}
		out = std::max(0.0, std::min(1.0, (hx - hxy) / hx));
		return true;
	}
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		StatScalarFinalizeMixin::FinalizeWith<T, STATE, CategoricalAssociationOperation>(state, target, finalize_data);
	}
};

//===--------------------------------------------------------------------===//
// Factor rank autocorrelation turnover over (date key, asset code, factor)
//===--------------------------------------------------------------------===//
// turnover = 1 - mean over dates t of corr(rank_t, rank_{t-period}) on the
// assets present on both dates, where ranks are average ranks within each date
// (alphalens factor_rank_autocorrelation). Duplicate (date, asset) rows -> NULL.
struct FactorTurnoverOperation : public StatHistoryBase {
	static constexpr idx_t REQUIRED_ARGS = 3;
	static constexpr idx_t CONFIG_START = 3;
	static void ValidateParameter(idx_t, double value, bool valid) {
		StatRequireInteger("fin_factor_turnover", "period", value, valid, 1.0);
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double period = input_count > 3 ? row.v[3] : 1.0;
		if (!state.params_set) {
			ValidateParameter(3, period, true);
		}
		SetParams(state, &period, 1, "fin_factor_turnover");
		if (!std::isfinite(row.v[0]) || !std::isfinite(row.v[2])) {
			state.invalid = true;
			return;
		}
		state.data->push_back(row.v[0]);
		state.data->push_back(row.v[1]);
		state.data->push_back(row.v[2]);
	}
	template <class STATE>
	static bool ComputeScalar(STATE &state, double &out) {
		auto &data = *state.data;
		const idx_t n = data.size() / 3;
		vector<std::array<double, 3>> rows(n);
		for (idx_t i = 0; i < n; i++) {
			rows[i] = {data[3 * i], data[3 * i + 1], data[3 * i + 2]};
		}
		std::sort(rows.begin(), rows.end());
		// Per-date asset codes (sorted) and within-date average ranks.
		struct DateSlice {
			idx_t begin, end;
		};
		vector<DateSlice> dates;
		vector<double> ranks(n);
		idx_t i = 0;
		vector<double> values, slice_ranks;
		while (i < n) {
			idx_t j = i + 1;
			while (j < n && rows[j][0] == rows[i][0]) {
				if (rows[j][1] == rows[j - 1][1]) {
					return false;
				}
				j++;
			}
			values.resize(j - i);
			for (idx_t k = i; k < j; k++) {
				values[k - i] = rows[k][2];
			}
			StatAverageRanks(values, slice_ranks);
			for (idx_t k = i; k < j; k++) {
				ranks[k] = slice_ranks[k - i];
			}
			dates.push_back({i, j});
			i = j;
		}
		const auto period = static_cast<idx_t>(state.params[0]);
		double sum = 0.0, used = 0.0;
		vector<double> a, b;
		for (idx_t t = period; t < dates.size(); t++) {
			auto &now = dates[t];
			auto &before = dates[t - period];
			a.clear();
			b.clear();
			idx_t p = before.begin, q = now.begin;
			while (p < before.end && q < now.end) {
				if (rows[p][1] < rows[q][1]) {
					p++;
				} else if (rows[q][1] < rows[p][1]) {
					q++;
				} else {
					a.push_back(ranks[p++]);
					b.push_back(ranks[q++]);
				}
			}
			double corr = StatPearson(a.data(), b.data(), a.size());
			if (std::isfinite(corr)) {
				sum += corr;
				used += 1.0;
			}
		}
		if (used == 0.0) {
			return false;
		}
		out = 1.0 - sum / used;
		return true;
	}
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		StatScalarFinalizeMixin::FinalizeWith<T, STATE, FactorTurnoverOperation>(state, target, finalize_data);
	}
};

//===--------------------------------------------------------------------===//
// Ordered series diagnostics over (value[, value2], ordering key)
//===--------------------------------------------------------------------===//
// Rows are sorted by (key, value[, value2]) so ties on the ordering key are
// resolved by value and never by physical row order.
template <idx_t WIDTH>
static void StatSortedSeries(const vector<double> &data, vector<std::array<double, WIDTH>> &rows) {
	const idx_t n = data.size() / WIDTH;
	rows.resize(n);
	for (idx_t i = 0; i < n; i++) {
		for (idx_t c = 0; c < WIDTH; c++) {
			rows[i][c] = data[WIDTH * i + c];
		}
	}
	std::sort(rows.begin(), rows.end());
}

// Shared row intake: columns [0, VALUE_COUNT) are values, VALUE_COUNT is the
// ordering key, and the remaining columns are constant configuration. Stores
// rows as (key, values...).
template <idx_t VALUE_COUNT>
struct OrderedSeriesBase : public StatHistoryBase {
	static constexpr idx_t REQUIRED_ARGS = VALUE_COUNT + 1;
	static constexpr idx_t CONFIG_START = VALUE_COUNT + 1;
	template <class STATE>
	static bool Intake(STATE &state, const FinRow &row) {
		for (idx_t c = 0; c <= VALUE_COUNT; c++) {
			if (!std::isfinite(row.v[c])) {
				state.invalid = true;
				return false;
			}
		}
		state.data->push_back(row.v[VALUE_COUNT]);
		for (idx_t c = 0; c < VALUE_COUNT; c++) {
			state.data->push_back(row.v[c]);
		}
		return true;
	}
};

// WHICH 0: fin_autocorr(x, ts, lag) = corr(x_t, x_{t-lag});
// WHICH 1: fin_crosscorr(x, y, ts, lag) = corr(x_t, y_{t-lag}) (pandas x.corr(y.shift(lag))).
template <int WHICH>
struct LaggedCorrelationOperation : public OrderedSeriesBase<WHICH == 0 ? 1 : 2> {
	using BASE = OrderedSeriesBase<WHICH == 0 ? 1 : 2>;
	static constexpr idx_t VALUES = WHICH == 0 ? 1 : 2;
	static const char *Name() {
		return WHICH == 0 ? "fin_autocorr" : "fin_crosscorr";
	}
	static void ValidateParameter(idx_t, double value, bool valid) {
		if (!valid || !std::isfinite(value) || value != std::floor(value) || std::fabs(value) > 1e9) {
			throw InvalidInputException("%s: lag must be an integer", Name());
		}
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double lag = input_count > VALUES + 1 ? row.v[VALUES + 1] : (WHICH == 0 ? 1.0 : 0.0);
		if (!state.params_set) {
			ValidateParameter(VALUES + 1, lag, true);
		}
		BASE::SetParams(state, &lag, 1, Name());
		BASE::Intake(state, row);
	}
	template <class STATE>
	static bool ComputeScalar(STATE &state, double &out) {
		vector<std::array<double, VALUES + 1>> rows;
		StatSortedSeries<VALUES + 1>(*state.data, rows);
		const int64_t n = int64_t(rows.size());
		const int64_t lag = int64_t(state.params[0]);
		vector<double> a, b;
		for (int64_t t = 0; t < n; t++) {
			int64_t s = t - lag;
			if (s < 0 || s >= n) {
				continue;
			}
			a.push_back(rows[t][1]);
			b.push_back(rows[s][VALUES]);
		}
		out = StatPearson(a.data(), b.data(), a.size());
		return true;
	}
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		StatScalarFinalizeMixin::FinalizeWith<T, STATE, LaggedCorrelationOperation>(state, target, finalize_data);
	}
};

// Hurst exponent by classic rescaled-range (R/S) analysis of the increments x:
// for window sizes n = 8, 16, 32, ... with at least two windows, split the
// series into floor(N / n) non-overlapping windows, average R/S (R = range of
// the cumulative mean-adjusted sum, S = population standard deviation), and
// regress log(R/S) on log(n). Needs at least 32 observations.
struct HurstOperation : public OrderedSeriesBase<1> {
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t) {
		Intake(state, row);
	}
	template <class STATE>
	static bool ComputeScalar(STATE &state, double &out) {
		vector<std::array<double, 2>> rows;
		StatSortedSeries<2>(*state.data, rows);
		const idx_t n = rows.size();
		vector<double> log_size, log_rs;
		for (idx_t size = 8; size <= n / 2; size *= 2) {
			double rs_sum = 0.0, used = 0.0;
			for (idx_t start = 0; start + size <= n; start += size) {
				double mean = 0.0;
				for (idx_t i = start; i < start + size; i++) {
					mean += rows[i][1];
				}
				mean /= double(size);
				double cumulative = 0.0, lo = 0.0, hi = 0.0, ss = 0.0;
				for (idx_t i = start; i < start + size; i++) {
					double d = rows[i][1] - mean;
					cumulative += d;
					lo = std::min(lo, cumulative);
					hi = std::max(hi, cumulative);
					ss += d * d;
				}
				double sd = std::sqrt(ss / double(size));
				if (sd > 0.0) {
					rs_sum += (hi - lo) / sd;
					used += 1.0;
				}
			}
			if (used > 0.0 && rs_sum > 0.0) {
				log_size.push_back(std::log(double(size)));
				log_rs.push_back(std::log(rs_sum / used));
			}
		}
		if (log_size.size() < 2) {
			return false;
		}
		double mx = 0.0, my = 0.0;
		for (idx_t i = 0; i < log_size.size(); i++) {
			mx += log_size[i];
			my += log_rs[i];
		}
		mx /= double(log_size.size());
		my /= double(log_size.size());
		double sxx = 0.0, sxy = 0.0;
		for (idx_t i = 0; i < log_size.size(); i++) {
			sxx += (log_size[i] - mx) * (log_size[i] - mx);
			sxy += (log_size[i] - mx) * (log_rs[i] - my);
		}
		out = sxy / sxx;
		return true;
	}
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		StatScalarFinalizeMixin::FinalizeWith<T, STATE, HurstOperation>(state, target, finalize_data);
	}
};

// Half-life of mean reversion from the AR(1) regression
// x_t - x_{t-1} = a + b x_{t-1} + e: phi = 1 + b, half-life = ln(0.5) / ln(phi)
// periods; NULL unless 0 < phi < 1.
struct HalfLifeOperation : public OrderedSeriesBase<1> {
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t) {
		Intake(state, row);
	}
	template <class STATE>
	static bool ComputeScalar(STATE &state, double &out) {
		vector<std::array<double, 2>> rows;
		StatSortedSeries<2>(*state.data, rows);
		const idx_t n = rows.size();
		if (n < 3) {
			return false;
		}
		vector<double> x((n - 1) * 2), y(n - 1), beta, se, residuals;
		for (idx_t t = 1; t < n; t++) {
			x[(t - 1) * 2] = 1.0;
			x[(t - 1) * 2 + 1] = rows[t - 1][1];
			y[t - 1] = rows[t][1] - rows[t - 1][1];
		}
		if (!StatLeastSquares(x, y, n - 1, 2, beta, se, residuals)) {
			return false;
		}
		const double phi = 1.0 + beta[1];
		if (!(phi > 0.0 && phi < 1.0)) {
			return false;
		}
		out = std::log(0.5) / std::log(phi);
		return true;
	}
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		StatScalarFinalizeMixin::FinalizeWith<T, STATE, HalfLifeOperation>(state, target, finalize_data);
	}
};

// Augmented Dickey-Fuller with a fixed lag order p (statsmodels
// adfuller(x, maxlag=p, autolag=None)): regress dx_t on x_{t-1}, dx_{t-1..t-p}
// and the deterministic terms; stat = t-value of x_{t-1}; p-value from
// MacKinnon (1994) response surfaces (N = 1).
enum class AdfRegression : uint8_t { NONE = 0, CONSTANT = 1, TREND = 2 };

static double StatMacKinnonP(double stat, AdfRegression regression) {
	static const double TAU_MAX[] = {std::numeric_limits<double>::infinity(), 2.74, 0.7};
	static const double TAU_MIN[] = {-19.04, -18.83, -16.18};
	static const double TAU_STAR[] = {-1.04, -1.61, -2.89};
	static const double SMALL[3][3] = {
	    {0.6344, 1.2378, 3.2496e-2}, {2.1659, 1.4412, 3.8269e-2}, {3.2512, 1.6047, 4.9588e-2}};
	static const double LARGE[3][4] = {{0.4797, 9.3557e-1, -0.6999e-1, 3.3066e-2},
	                                   {1.7339, 9.3202e-1, -1.2745e-1, -1.0368e-2},
	                                   {2.5261, 6.1654e-1, -3.7956e-1, -6.0285e-2}};
	auto r = int(regression);
	if (stat > TAU_MAX[r]) {
		return 1.0;
	}
	if (stat < TAU_MIN[r]) {
		return 0.0;
	}
	double z;
	if (stat <= TAU_STAR[r]) {
		z = SMALL[r][0] + stat * (SMALL[r][1] + stat * SMALL[r][2]);
	} else {
		z = LARGE[r][0] + stat * (LARGE[r][1] + stat * (LARGE[r][2] + stat * LARGE[r][3]));
	}
	return StatNormalCdf(z);
}

struct AdfOperation : public OrderedSeriesBase<1> {
	static vector<string> FieldNames() {
		return {"stat", "pvalue", "lags", "nobs"};
	}
	static LogicalType ReturnType() {
		return StatStructType<AdfOperation>();
	}
	static double ParseText(idx_t, string_t text) {
		if (FinTextEquals(text, "n") || FinTextEquals(text, "nc")) {
			return double(AdfRegression::NONE);
		}
		if (FinTextEquals(text, "c")) {
			return double(AdfRegression::CONSTANT);
		}
		if (FinTextEquals(text, "ct")) {
			return double(AdfRegression::TREND);
		}
		throw InvalidInputException("fin_adf: unknown regression '%s' (expected 'n', 'c' or 'ct')", text.GetString());
	}
	static void ValidateParameter(idx_t column, double value, bool valid) {
		if (column == 2) {
			StatRequireInteger("fin_adf", "max_lag", value, valid, 0.0);
		} else if (!valid) {
			throw InvalidInputException("fin_adf: regression must not be NULL");
		}
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double params[2] = {input_count > 2 ? row.v[2] : 1.0, input_count > 3 ? row.v[3] : 1.0};
		if (!state.params_set) {
			ValidateParameter(2, params[0], true);
		}
		SetParams(state, params, 2, "fin_adf");
		Intake(state, row);
	}
	template <class STATE>
	static bool Compute(STATE &state, double *out) {
		vector<std::array<double, 2>> rows;
		StatSortedSeries<2>(*state.data, rows);
		const idx_t n = rows.size();
		const auto p = static_cast<idx_t>(state.params[0]);
		const auto regression = AdfRegression(int(state.params[1]));
		if (n < p + 2) {
			return false;
		}
		const idx_t nobs = n - 1 - p;
		const idx_t k = 1 + p + idx_t(regression);
		if (nobs <= k) {
			return false;
		}
		vector<double> diff(n - 1);
		for (idx_t t = 1; t < n; t++) {
			diff[t - 1] = rows[t][1] - rows[t - 1][1];
		}
		vector<double> x(nobs * k), y(nobs), beta, se, residuals;
		for (idx_t i = 0; i < nobs; i++) {
			const idx_t t = p + i; // index into diff of the dependent value
			y[i] = diff[t];
			double *row = &x[i * k];
			row[0] = rows[t][1];
			for (idx_t l = 1; l <= p; l++) {
				row[l] = diff[t - l];
			}
			if (regression != AdfRegression::NONE) {
				row[p + 1] = 1.0;
			}
			if (regression == AdfRegression::TREND) {
				row[p + 2] = double(i + 1);
			}
		}
		if (!StatLeastSquares(x, y, nobs, k, beta, se, residuals) || !(se[0] > 0.0)) {
			return false;
		}
		out[0] = beta[0] / se[0];
		out[1] = StatMacKinnonP(out[0], regression);
		out[2] = double(p);
		out[3] = double(nobs);
		return true;
	}
};

// Ljung-Box Q = n (n + 2) sum_{k=1..h} acf_k^2 / (n - k) with p-value from
// chi-square(h) (statsmodels acorr_ljungbox).
struct LjungBoxOperation : public OrderedSeriesBase<1> {
	static vector<string> FieldNames() {
		return {"stat", "pvalue", "lags"};
	}
	static LogicalType ReturnType() {
		return StatStructType<LjungBoxOperation>();
	}
	static void ValidateParameter(idx_t, double value, bool valid) {
		StatRequireInteger("fin_ljung_box", "lags", value, valid, 1.0);
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double lags = input_count > 2 ? row.v[2] : 10.0;
		if (!state.params_set) {
			ValidateParameter(2, lags, true);
		}
		SetParams(state, &lags, 1, "fin_ljung_box");
		Intake(state, row);
	}
	template <class STATE>
	static bool Compute(STATE &state, double *out) {
		vector<std::array<double, 2>> rows;
		StatSortedSeries<2>(*state.data, rows);
		const idx_t n = rows.size();
		const auto h = static_cast<idx_t>(state.params[0]);
		if (n <= h + 1) {
			return false;
		}
		double mean = 0.0;
		for (auto &row : rows) {
			mean += row[1];
		}
		mean /= double(n);
		double denominator = 0.0;
		for (auto &row : rows) {
			denominator += (row[1] - mean) * (row[1] - mean);
		}
		if (!(denominator > 0.0)) {
			return false;
		}
		double q = 0.0;
		for (idx_t k = 1; k <= h; k++) {
			double acf = 0.0;
			for (idx_t t = k; t < n; t++) {
				acf += (rows[t][1] - mean) * (rows[t - k][1] - mean);
			}
			acf /= denominator;
			q += acf * acf / double(n - k);
		}
		q *= double(n) * double(n + 2);
		out[0] = q;
		out[1] = StatChiSquareSurvival(q, double(h));
		out[2] = double(h);
		return true;
	}
};

// Newey-West HAC t-statistic of the slope in y = a + b x (Bartlett kernel,
// weights 1 - l / (L + 1), no small-sample correction; statsmodels
// OLS.fit(cov_type='HAC', cov_kwds={'maxlags': L, 'use_correction': False})).
// Columns: y, x, ordering key, lags.
struct NeweyWestOperation : public OrderedSeriesBase<2> {
	static void ValidateParameter(idx_t, double value, bool valid) {
		StatRequireInteger("fin_newey_west_tstat", "lags", value, valid, 0.0);
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t input_count) {
		double lags = input_count > 3 ? row.v[3] : 1.0;
		if (!state.params_set) {
			ValidateParameter(3, lags, true);
		}
		SetParams(state, &lags, 1, "fin_newey_west_tstat");
		Intake(state, row);
	}
	template <class STATE>
	static bool ComputeScalar(STATE &state, double &out) {
		vector<std::array<double, 3>> rows;
		StatSortedSeries<3>(*state.data, rows);
		const idx_t n = rows.size();
		if (n < 3) {
			return false;
		}
		vector<double> x(n * 2), y(n), beta, se, residuals, xtx_inv;
		for (idx_t t = 0; t < n; t++) {
			y[t] = rows[t][1];
			x[t * 2] = 1.0;
			x[t * 2 + 1] = rows[t][2];
		}
		if (!StatLeastSquares(x, y, n, 2, beta, se, residuals, &xtx_inv)) {
			return false;
		}
		const auto lags = static_cast<idx_t>(state.params[0]);
		double s[4] = {0.0, 0.0, 0.0, 0.0};
		for (idx_t l = 0; l <= std::min(lags, n - 1); l++) {
			const double weight = l == 0 ? 1.0 : 1.0 - double(l) / double(lags + 1);
			double g[4] = {0.0, 0.0, 0.0, 0.0};
			for (idx_t t = l; t < n; t++) {
				const double e = residuals[t] * residuals[t - l];
				const double *xt = &x[t * 2];
				const double *xs = &x[(t - l) * 2];
				g[0] += e * xt[0] * xs[0];
				g[1] += e * xt[0] * xs[1];
				g[2] += e * xt[1] * xs[0];
				g[3] += e * xt[1] * xs[1];
			}
			if (l == 0) {
				for (idx_t i = 0; i < 4; i++) {
					s[i] += g[i];
				}
			} else {
				s[0] += weight * 2.0 * g[0];
				s[1] += weight * (g[1] + g[2]);
				s[2] += weight * (g[2] + g[1]);
				s[3] += weight * 2.0 * g[3];
			}
		}
		// V = A S A with A = (X'X)^-1; we need V[1][1].
		const double *a = xtx_inv.data();
		double as[4];
		for (idx_t i = 0; i < 2; i++) {
			for (idx_t j = 0; j < 2; j++) {
				as[i * 2 + j] = a[i * 2] * s[j] + a[i * 2 + 1] * s[2 + j];
			}
		}
		const double v11 = as[2] * a[1] + as[3] * a[3];
		if (!(v11 > 0.0)) {
			return false;
		}
		out = beta[1] / std::sqrt(v11);
		return true;
	}
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		StatScalarFinalizeMixin::FinalizeWith<T, STATE, NeweyWestOperation>(state, target, finalize_data);
	}
};

// GARCH(1,1) maximum likelihood with a zero conditional mean and Gaussian
// innovations: h_1 = sample variance (ddof 1), h_t = omega + alpha r_{t-1}^2 +
// beta h_{t-1}, loglik = -1/2 sum(log(2 pi) + log h_t + r_t^2 / h_t). The
// recursion matches fin_garch11_forecast. BFGS with analytic gradients over
// omega = s2 exp(u0), alpha + beta = logistic(u1), alpha / (alpha + beta) =
// logistic(u2), which keeps omega > 0, alpha, beta >= 0 and alpha + beta < 1;
// the best of several deterministic starts is returned.
struct GarchFitOperation : public OrderedSeriesBase<1> {
	static vector<string> FieldNames() {
		return {"omega", "alpha", "beta", "loglik", "nobs"};
	}
	static LogicalType ReturnType() {
		return StatStructType<GarchFitOperation>();
	}
	static void ValidateParameter(idx_t, double, bool) {
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t) {
		Intake(state, row);
	}
	static double Logistic(double u) {
		return u >= 0.0 ? 1.0 / (1.0 + std::exp(-u)) : std::exp(u) / (1.0 + std::exp(u));
	}
	// Returns the mean negative log-likelihood and its gradient in u.
	static double Objective(const vector<double> &r2, double s2, const double *u, double *grad) {
		const double p = Logistic(u[1]);
		const double share = Logistic(u[2]);
		const double omega = s2 * std::exp(u[0]);
		const double alpha = p * share;
		const double beta = p * (1.0 - share);
		const idx_t n = r2.size();
		double h = s2;
		double dh[3] = {0.0, 0.0, 0.0}; // d h / d (omega, alpha, beta)
		double nll = 0.0;
		double g[3] = {0.0, 0.0, 0.0};
		for (idx_t t = 0; t < n; t++) {
			if (t > 0) {
				const double h_prev = h;
				dh[0] = 1.0 + beta * dh[0];
				dh[1] = r2[t - 1] + beta * dh[1];
				dh[2] = h_prev + beta * dh[2];
				h = omega + alpha * r2[t - 1] + beta * h_prev;
			}
			if (!(h > 0.0) || !std::isfinite(h)) {
				return std::numeric_limits<double>::infinity();
			}
			nll += 0.5 * (std::log(2.0 * M_PI) + std::log(h) + r2[t] / h);
			const double dl = 0.5 * (1.0 / h - r2[t] / (h * h));
			for (idx_t k = 0; k < 3; k++) {
				g[k] += dl * dh[k];
			}
		}
		if (grad) {
			const double dp = p * (1.0 - p);
			const double ds = share * (1.0 - share);
			grad[0] = g[0] * omega / double(n);
			grad[1] = (g[1] * share + g[2] * (1.0 - share)) * dp / double(n);
			grad[2] = (g[1] - g[2]) * p * ds / double(n);
		}
		return nll / double(n);
	}
	static double Minimize(const vector<double> &r2, double s2, double *u) {
		double grad[3], next_grad[3];
		double f = Objective(r2, s2, u, grad);
		if (!std::isfinite(f)) {
			return f;
		}
		double inv[3][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}};
		for (idx_t iteration = 0; iteration < 1000; iteration++) {
			double gnorm = std::max(std::fabs(grad[0]), std::max(std::fabs(grad[1]), std::fabs(grad[2])));
			if (gnorm < 1e-12) {
				break;
			}
			double d[3];
			for (idx_t i = 0; i < 3; i++) {
				d[i] = -(inv[i][0] * grad[0] + inv[i][1] * grad[1] + inv[i][2] * grad[2]);
			}
			double slope = d[0] * grad[0] + d[1] * grad[1] + d[2] * grad[2];
			if (!(slope < 0.0)) {
				for (idx_t i = 0; i < 3; i++) {
					for (idx_t j = 0; j < 3; j++) {
						inv[i][j] = i == j ? 1.0 : 0.0;
					}
					d[i] = -grad[i];
				}
				slope = -(grad[0] * grad[0] + grad[1] * grad[1] + grad[2] * grad[2]);
			}
			double step = 1.0;
			double candidate[3];
			double next_f = std::numeric_limits<double>::infinity();
			for (idx_t trial = 0; trial < 60; trial++) {
				for (idx_t i = 0; i < 3; i++) {
					candidate[i] = u[i] + step * d[i];
				}
				next_f = Objective(r2, s2, candidate, next_grad);
				if (std::isfinite(next_f) && next_f <= f + 1e-4 * step * slope) {
					break;
				}
				step *= 0.5;
			}
			if (!(std::isfinite(next_f) && next_f <= f + 1e-4 * step * slope)) {
				break;
			}
			double s[3], y[3];
			for (idx_t i = 0; i < 3; i++) {
				s[i] = candidate[i] - u[i];
				y[i] = next_grad[i] - grad[i];
				u[i] = candidate[i];
				grad[i] = next_grad[i];
			}
			const double improvement = f - next_f;
			f = next_f;
			const double sy = s[0] * y[0] + s[1] * y[1] + s[2] * y[2];
			if (sy > 1e-300) {
				// BFGS inverse-Hessian update.
				double hy[3];
				for (idx_t i = 0; i < 3; i++) {
					hy[i] = inv[i][0] * y[0] + inv[i][1] * y[1] + inv[i][2] * y[2];
				}
				const double yhy = y[0] * hy[0] + y[1] * hy[1] + y[2] * hy[2];
				for (idx_t i = 0; i < 3; i++) {
					for (idx_t j = 0; j < 3; j++) {
						inv[i][j] += ((sy + yhy) * s[i] * s[j]) / (sy * sy) - (hy[i] * s[j] + s[i] * hy[j]) / sy;
					}
				}
			}
			if (improvement <= 1e-16 * std::max(1.0, std::fabs(f)) &&
			    std::max(std::fabs(s[0]), std::max(std::fabs(s[1]), std::fabs(s[2]))) < 1e-12) {
				break;
			}
		}
		return f;
	}
	template <class STATE>
	static bool Compute(STATE &state, double *out) {
		vector<std::array<double, 2>> rows;
		StatSortedSeries<2>(*state.data, rows);
		const idx_t n = rows.size();
		if (n < 10) {
			return false;
		}
		vector<double> r2(n);
		double mean = 0.0;
		for (idx_t t = 0; t < n; t++) {
			r2[t] = rows[t][1] * rows[t][1];
			mean += rows[t][1];
		}
		mean /= double(n);
		double s2 = 0.0;
		for (auto &row : rows) {
			s2 += (row[1] - mean) * (row[1] - mean);
		}
		s2 /= double(n - 1);
		if (!(s2 > 0.0) || !std::isfinite(s2)) {
			return false;
		}
		static const double STARTS[][2] = {{0.05, 0.90}, {0.10, 0.80}, {0.20, 0.60}, {0.02, 0.97}, {0.30, 0.30}};
		double best_f = std::numeric_limits<double>::infinity();
		double best_u[3] = {0.0, 0.0, 0.0};
		for (auto &start : STARTS) {
			const double p = start[0] + start[1];
			double u[3] = {std::log(1.0 - p), std::log(p / (1.0 - p)), std::log(start[0] / start[1])};
			const double f = Minimize(r2, s2, u);
			if (f < best_f) {
				best_f = f;
				std::copy(u, u + 3, best_u);
			}
		}
		if (!std::isfinite(best_f)) {
			return false;
		}
		const double p = Logistic(best_u[1]);
		const double share = Logistic(best_u[2]);
		out[0] = s2 * std::exp(best_u[0]);
		out[1] = p * share;
		out[2] = p * (1.0 - share);
		out[3] = -best_f * double(n);
		out[4] = double(n);
		return true;
	}
};
