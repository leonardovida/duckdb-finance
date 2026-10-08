// Exponential time decay, rolling z-score, multi-factor OLS and labelled
// covariance/correlation matrix aggregates. Every state here merges exactly or
// sorts before computing, so results never depend on thread count or row order.

static Vector &StatListChild(Vector &list) {
#if FINANCE_OLD_DUCKDB_VECTOR_API
	return ListVector::GetEntry(list);
#else
	return ListVector::GetChildMutable(list);
#endif
}

//===--------------------------------------------------------------------===//
// Exponential time decay: weights 2^(-(t_max - t_i) / halflife)
//===--------------------------------------------------------------------===//
enum class DecayKind : uint8_t { SUM, AVG, COUNT, MAX };

struct DecayState {
	FinSum sum;
	FinSum weight;
	double max_value;
	double reference;
	double halflife;
	bool has_rows;
	bool halflife_set;
	bool invalid;
};

template <DecayKind KIND>
struct DecayOperation : public FinOperationDefaults {
	static constexpr bool HAS_VALUE = KIND != DecayKind::COUNT;
	static constexpr idx_t REQUIRED_ARGS = HAS_VALUE ? 3 : 2;
	static constexpr bool ORDER_DEPENDENT = false;
	static constexpr bool WINDOW_INCREMENTAL = true;

	static const char *Name() {
		switch (KIND) {
		case DecayKind::SUM:
			return "fin_exp_decay_sum";
		case DecayKind::AVG:
			return "fin_exp_decay_avg";
		case DecayKind::COUNT:
			return "fin_exp_decay_count";
		default:
			return "fin_exp_decay_max";
		}
	}

	static void ValidateHalflife(const char *name, double value, bool valid) {
		if (!valid || !std::isfinite(value) || !(value > 0.0)) {
			throw InvalidInputException("%s: halflife must be positive and finite", name);
		}
	}

	template <class STATE>
	static void Initialize(STATE &state) {
		state.sum.Reset();
		state.weight.Reset();
		state.max_value = 0.0;
		state.reference = 0.0;
		state.halflife = 0.0;
		state.has_rows = false;
		state.halflife_set = false;
		state.invalid = false;
	}

	template <class STATE>
	static void WindowReset(STATE &state) {
		Initialize(state);
	}

	static void Scale(FinSum &sum, double factor) {
		sum.sum *= factor;
		sum.correction *= factor;
	}

	// Moves the state's reference time forward to `reference`.
	template <class STATE>
	static void Rebase(STATE &state, double reference) {
		if (reference <= state.reference) {
			return;
		}
		const double factor = std::exp2(-(reference - state.reference) / state.halflife);
		Scale(state.sum, factor);
		Scale(state.weight, factor);
		state.max_value *= factor;
		state.reference = reference;
	}

	template <class STATE>
	static void SetHalflife(STATE &state, double halflife) {
		if (state.halflife_set) {
			if (state.halflife != halflife) {
				throw InvalidInputException("%s: halflife must be constant within a group", Name());
			}
			return;
		}
		ValidateHalflife(Name(), halflife, true);
		state.halflife = halflife;
		state.halflife_set = true;
	}

	template <class STATE>
	static void AddWeighted(STATE &state, double value, double key) {
		if (!state.has_rows) {
			state.reference = key;
			state.has_rows = true;
			state.max_value = value;
			state.sum.Add(value);
			state.weight.Add(1.0);
			return;
		}
		Rebase(state, key);
		const double w = std::exp2(-(state.reference - key) / state.halflife);
		state.sum.Add(value * w);
		state.weight.Add(w);
		state.max_value = std::max(state.max_value, value * w);
	}

	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t) {
		const idx_t key_column = HAS_VALUE ? 1 : 0;
		SetHalflife(state, row.v[key_column + 1]);
		const double value = HAS_VALUE ? row.v[0] : 1.0;
		const double key = row.v[key_column];
		if (!std::isfinite(value) || !std::isfinite(key)) {
			state.invalid = true;
			return;
		}
		AddWeighted(state, value, key);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.invalid = target.invalid || source.invalid;
		if (source.halflife_set) {
			SetHalflife(target, source.halflife);
		}
		if (!source.has_rows) {
			return;
		}
		if (!target.has_rows) {
			auto invalid = target.invalid;
			target = source;
			target.invalid = invalid;
			return;
		}
		STATE incoming = source;
		Rebase(target, incoming.reference);
		Rebase(incoming, target.reference);
		target.sum.Merge(incoming.sum);
		target.weight.Merge(incoming.weight);
		target.max_value = std::max(target.max_value, incoming.max_value);
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || !state.has_rows) {
			finalize_data.ReturnNull();
			return;
		}
		double result;
		switch (KIND) {
		case DecayKind::SUM:
			result = state.sum.Value();
			break;
		case DecayKind::AVG:
			result = state.sum.Value() / state.weight.Value();
			break;
		case DecayKind::COUNT:
			result = state.weight.Value();
			break;
		default:
			result = state.max_value;
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

// Validates a constant half-life at bind. INTERVAL half-lives are read as
// microseconds (timestamps are epoch microseconds); months count as 30 days.
template <class OP>
static unique_ptr<FunctionData> DecayBind(ClientContext &context, AggregateFunction &function,
                                          vector<unique_ptr<Expression>> &arguments) {
	FinRejectNamedArguments(function, arguments);
	const idx_t column = arguments.size() - 1;
	auto &argument = arguments[column];
	if (!argument->IsFoldable()) {
		return nullptr;
	}
	if (argument->return_type.id() == LogicalTypeId::INTERVAL) {
		auto value = ExpressionExecutor::EvaluateScalar(context, *argument, true);
		if (value.IsNull()) {
			OP::ValidateHalflife(OP::Name(), StatNaN(), false);
		}
		int64_t micros;
		if (!Interval::TryGetMicro(IntervalValue::Get(value), micros)) {
			throw InvalidInputException("%s: halflife interval is out of range", OP::Name());
		}
		OP::ValidateHalflife(OP::Name(), double(micros), true);
	} else {
		auto value = ExpressionExecutor::EvaluateScalar(context, *argument, true);
		OP::ValidateHalflife(OP::Name(), value.IsNull() ? StatNaN() : DoubleValue::Get(value.DefaultCastAs(LogicalType::DOUBLE)),
		                     !value.IsNull());
	}
	return nullptr;
}

template <DecayKind KIND>
static void RegisterDecaySet(ExtensionLoader &loader, const string &name) {
	using OP = DecayOperation<KIND>;
	const auto DOUBLE = FinanceLogicalType(LogicalTypeId::DOUBLE);
	vector<vector<LogicalType>> signatures = {
	    {FinanceLogicalType(LogicalTypeId::TIMESTAMP), FinanceLogicalType(LogicalTypeId::INTERVAL)},
	    {FinanceLogicalType(LogicalTypeId::TIMESTAMP_TZ), FinanceLogicalType(LogicalTypeId::INTERVAL)},
	    {DOUBLE, DOUBLE}};
	vector<AggregateFunction> functions;
	for (auto &signature : signatures) {
		if (OP::HAS_VALUE) {
			signature.insert(signature.begin(), DOUBLE);
		}
		auto function = FinAggregate<DecayState, OP>(name, signature);
		function.SetBindCallback(DecayBind<OP>);
		functions.push_back(std::move(function));
	}
	FinRegisterSet(loader, name, std::move(functions));
}

//===--------------------------------------------------------------------===//
// Rolling z-score of the latest observation by an ordering key
//===--------------------------------------------------------------------===//
struct RollingZscoreState {
	FinMoments moments;
	double last_key;
	double last_value;
	bool has_last;
	bool invalid;
};

struct RollingZscoreOperation : public FinOperationDefaults {
	static constexpr idx_t REQUIRED_ARGS = 2;
	static constexpr bool ORDER_DEPENDENT = false;
	static constexpr bool WINDOW_INCREMENTAL = true;

	template <class STATE>
	static void Initialize(STATE &state) {
		state.moments.Reset();
		state.last_key = 0.0;
		state.last_value = 0.0;
		state.has_last = false;
		state.invalid = false;
	}
	template <class STATE>
	static void WindowReset(STATE &state) {
		Initialize(state);
	}
	// Ties on the key resolve to the larger value (finance_last_by_internal).
	template <class STATE>
	static void Observe(STATE &state, double key, double value) {
		if (!state.has_last || key > state.last_key || (key == state.last_key && value > state.last_value)) {
			state.last_key = key;
			state.last_value = value;
			state.has_last = true;
		}
	}
	template <class STATE>
	static void UpdateRow(STATE &state, const FinRow &row, idx_t) {
		if (!std::isfinite(row.v[0])) {
			state.invalid = true;
			return;
		}
		state.moments.Add(row.v[0]);
		Observe(state, row.v[1], row.v[0]);
	}
	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.invalid = target.invalid || source.invalid;
		target.moments.Merge(source.moments);
		if (source.has_last) {
			Observe(target, source.last_key, source.last_value);
		}
	}
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.moments.count < 2.0 || !(state.moments.m2 > 0.0)) {
			finalize_data.ReturnNull();
			return;
		}
		const double sd = std::sqrt(state.moments.m2 / (state.moments.count - 1.0));
		target = (state.last_value - state.moments.mean) / sd;
	}
	template <class STATE>
	static void Destroy(STATE &, AggregateInputData &) {
	}
};

static vector<LogicalType> StatOrderKeyTypes() {
	return {FinanceLogicalType(LogicalTypeId::BIGINT), FinanceLogicalType(LogicalTypeId::DOUBLE),
	        FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::TIMESTAMP),
	        FinanceLogicalType(LogicalTypeId::TIMESTAMP_TZ)};
}

//===--------------------------------------------------------------------===//
// Multi-factor OLS: fin_ols(y, x_list) / fin_ols_no_intercept(y, x_list)
//===--------------------------------------------------------------------===//
// Streaming co-moments of (x_1..x_k, y) with Welford updates and Chan merges.
struct OlsData {
	idx_t dim = 0; // k + 1
	double count = 0.0;
	vector<double> mean;
	vector<double> comoment; // dim x dim, row-major
	bool invalid = false;

	void Add(const double *values) {
		count += 1.0;
		vector<double> delta(dim);
		for (idx_t i = 0; i < dim; i++) {
			delta[i] = values[i] - mean[i];
			mean[i] += delta[i] / count;
		}
		for (idx_t i = 0; i < dim; i++) {
			for (idx_t j = 0; j <= i; j++) {
				comoment[i * dim + j] += delta[i] * (values[j] - mean[j]);
			}
		}
	}

	void Merge(const OlsData &other) {
		invalid = invalid || other.invalid;
		if (other.dim == 0) {
			return;
		}
		if (dim == 0) {
			auto keep = invalid;
			*this = other;
			invalid = keep;
			return;
		}
		if (dim != other.dim) {
			invalid = true;
			return;
		}
		if (other.count == 0.0) {
			return;
		}
		const double total = count + other.count;
		vector<double> delta(dim);
		for (idx_t i = 0; i < dim; i++) {
			delta[i] = other.mean[i] - mean[i];
		}
		const double weight = count * other.count / total;
		for (idx_t i = 0; i < dim; i++) {
			for (idx_t j = 0; j <= i; j++) {
				comoment[i * dim + j] += other.comoment[i * dim + j] + delta[i] * delta[j] * weight;
			}
		}
		for (idx_t i = 0; i < dim; i++) {
			mean[i] += delta[i] * other.count / total;
		}
		count = total;
	}

	double Comoment(idx_t i, idx_t j) const {
		return i >= j ? comoment[i * dim + j] : comoment[j * dim + i];
	}
};

struct OlsState {
	OlsData *data;
};

template <bool INTERCEPT>
struct OlsOperation {
	static LogicalType ReturnType() {
		const auto DOUBLE = LogicalType(LogicalTypeId::DOUBLE);
		child_list_t<LogicalType> children;
		children.emplace_back("beta", LogicalType::LIST(DOUBLE));
		children.emplace_back("intercept", DOUBLE);
		children.emplace_back("r2", DOUBLE);
		children.emplace_back("stderr", LogicalType::LIST(DOUBLE));
		children.emplace_back("tstat", LogicalType::LIST(DOUBLE));
		children.emplace_back("intercept_stderr", DOUBLE);
		children.emplace_back("intercept_tstat", DOUBLE);
		children.emplace_back("nobs", LogicalType(LogicalTypeId::BIGINT));
		return LogicalType::STRUCT(std::move(children));
	}

	static Value DoubleOrNull(double value) {
		return std::isfinite(value) ? Value::DOUBLE(value) : Value(LogicalType::DOUBLE);
	}

	static Value Compute(const OlsData &data) {
		const auto null_result = Value(ReturnType());
		if (data.invalid || data.dim < 2) {
			return null_result;
		}
		const idx_t k = data.dim - 1;
		const double n = data.count;
		const idx_t parameters = k + (INTERCEPT ? 1 : 0);
		if (n < double(parameters)) {
			return null_result;
		}
		// Cross products of the regressors with and without centering.
		vector<double> xtx(k * k), xty(k);
		for (idx_t i = 0; i < k; i++) {
			for (idx_t j = 0; j < k; j++) {
				xtx[i * k + j] = data.Comoment(i, j) + (INTERCEPT ? 0.0 : n * data.mean[i] * data.mean[j]);
			}
			xty[i] = data.Comoment(i, k) + (INTERCEPT ? 0.0 : n * data.mean[i] * data.mean[k]);
		}
		const double yty = data.Comoment(k, k) + (INTERCEPT ? 0.0 : n * data.mean[k] * data.mean[k]);
		vector<double> inverse = xtx;
		if (!StatInvertSPD(inverse, k)) {
			return null_result;
		}
		vector<double> beta(k, 0.0);
		for (idx_t i = 0; i < k; i++) {
			for (idx_t j = 0; j < k; j++) {
				beta[i] += inverse[i * k + j] * xty[j];
			}
		}
		// SSR = y'y - 2 b'X'y + b'X'X b.
		double fitted = 0.0, cross = 0.0;
		for (idx_t i = 0; i < k; i++) {
			cross += beta[i] * xty[i];
			for (idx_t j = 0; j < k; j++) {
				fitted += beta[i] * xtx[i * k + j] * beta[j];
			}
		}
		const double ssr = std::max(0.0, yty - 2.0 * cross + fitted);
		const double df = n - double(parameters);
		const double sigma2 = df > 0.0 ? ssr / df : StatNaN();
		vector<Value> beta_values, se_values, t_values;
		for (idx_t i = 0; i < k; i++) {
			const double se = std::sqrt(sigma2 * inverse[i * k + i]);
			beta_values.push_back(DoubleOrNull(beta[i]));
			se_values.push_back(DoubleOrNull(se));
			t_values.push_back(DoubleOrNull(se > 0.0 ? beta[i] / se : StatNaN()));
		}
		double intercept = 0.0, intercept_se = StatNaN();
		if (INTERCEPT) {
			intercept = data.mean[k];
			double quad = 0.0;
			for (idx_t i = 0; i < k; i++) {
				intercept -= beta[i] * data.mean[i];
				for (idx_t j = 0; j < k; j++) {
					quad += data.mean[i] * inverse[i * k + j] * data.mean[j];
				}
			}
			intercept_se = std::sqrt(sigma2 * (1.0 / n + quad));
		}
		// Centered R^2 with an intercept, uncentered R^2 without (statsmodels convention).
		const double r2 = yty > 0.0 ? 1.0 - ssr / yty : StatNaN();
		child_list_t<Value> children;
		children.emplace_back("beta", Value::LIST(LogicalType::DOUBLE, beta_values));
		children.emplace_back("intercept", DoubleOrNull(intercept));
		children.emplace_back("r2", DoubleOrNull(r2));
		children.emplace_back("stderr", Value::LIST(LogicalType::DOUBLE, se_values));
		children.emplace_back("tstat", Value::LIST(LogicalType::DOUBLE, t_values));
		children.emplace_back("intercept_stderr", DoubleOrNull(intercept_se));
		children.emplace_back("intercept_tstat",
		                      DoubleOrNull(INTERCEPT && intercept_se > 0.0 ? intercept / intercept_se : StatNaN()));
		children.emplace_back("nobs", Value::BIGINT(int64_t(n)));
		return Value::STRUCT(std::move(children));
	}
};

static void OlsInitialize(const AggregateFunction &, data_ptr_t state) {
	reinterpret_cast<OlsState *>(state)->data = nullptr;
}

static void OlsUpdateRows(Vector inputs[], idx_t count, const std::function<OlsState &(idx_t)> &state_for_row) {
	UnifiedVectorFormat ydata, ldata, cdata;
	FinanceToUnifiedFormat(inputs[0], count, ydata);
	FinanceToUnifiedFormat(inputs[1], count, ldata);
	auto &child = StatListChild(inputs[1]);
	const auto child_size = ListVector::GetListSize(inputs[1]);
	FinanceToUnifiedFormat(child, child_size, cdata);
	auto y_values = UnifiedVectorFormat::GetData<double>(ydata);
	auto entries = UnifiedVectorFormat::GetData<list_entry_t>(ldata);
	auto child_values = UnifiedVectorFormat::GetData<double>(cdata);
	vector<double> row;
	for (idx_t i = 0; i < count; i++) {
		auto yidx = ydata.sel->get_index(i);
		auto lidx = ldata.sel->get_index(i);
		if (!ydata.validity.RowIsValid(yidx) || !ldata.validity.RowIsValid(lidx)) {
			continue;
		}
		auto entry = entries[lidx];
		bool has_null = false;
		row.resize(entry.length + 1);
		for (idx_t j = 0; j < entry.length; j++) {
			auto cidx = cdata.sel->get_index(entry.offset + j);
			if (!cdata.validity.RowIsValid(cidx)) {
				has_null = true;
				break;
			}
			row[j] = child_values[cidx];
		}
		if (has_null) {
			continue;
		}
		row[entry.length] = y_values[yidx];
		auto &state = state_for_row(i);
		if (!state.data) {
			state.data = new OlsData();
		}
		auto &data = *state.data;
		if (data.invalid) {
			continue;
		}
		if (data.dim == 0) {
			if (entry.length == 0) {
				data.invalid = true;
				continue;
			}
			data.dim = entry.length + 1;
			data.mean.assign(data.dim, 0.0);
			data.comoment.assign(data.dim * data.dim, 0.0);
		}
		bool finite = entry.length + 1 == data.dim;
		for (idx_t j = 0; finite && j < row.size(); j++) {
			finite = std::isfinite(row[j]);
		}
		if (!finite) {
			data.invalid = true;
			continue;
		}
		data.Add(row.data());
	}
}

static void OlsScatterUpdate(Vector inputs[], AggregateInputData &, idx_t, Vector &states, idx_t count) {
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(states, count, sdata);
	auto state_ptrs = UnifiedVectorFormat::GetData<OlsState *>(sdata);
	OlsUpdateRows(inputs, count, [&](idx_t i) -> OlsState & { return *state_ptrs[sdata.sel->get_index(i)]; });
}

static void OlsSimpleUpdate(Vector inputs[], AggregateInputData &, idx_t, data_ptr_t state_ptr, idx_t count) {
	auto &state = *reinterpret_cast<OlsState *>(state_ptr);
	OlsUpdateRows(inputs, count, [&](idx_t) -> OlsState & { return state; });
}

static void OlsCombine(Vector &source, Vector &target, AggregateInputData &, idx_t count) {
	auto sources = FlatVector::GetData<OlsState *>(source);
	auto targets = FlatVector::GetData<OlsState *>(target);
	for (idx_t i = 0; i < count; i++) {
		if (!sources[i]->data) {
			continue;
		}
		if (!targets[i]->data) {
			targets[i]->data = new OlsData(*sources[i]->data);
			continue;
		}
		targets[i]->data->Merge(*sources[i]->data);
	}
}

template <bool INTERCEPT>
static void OlsFinalize(Vector &states, AggregateInputData &, Vector &result, idx_t count, idx_t offset) {
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(states, count, sdata);
	auto state_ptrs = UnifiedVectorFormat::GetData<OlsState *>(sdata);
	for (idx_t i = 0; i < count; i++) {
		auto &state = *state_ptrs[sdata.sel->get_index(i)];
		result.SetValue(i + offset, state.data ? OlsOperation<INTERCEPT>::Compute(*state.data)
		                                       : Value(OlsOperation<INTERCEPT>::ReturnType()));
	}
}

static void OlsDestroy(Vector &states, AggregateInputData &, idx_t count) {
	auto state_ptrs = FlatVector::GetData<OlsState *>(states);
	for (idx_t i = 0; i < count; i++) {
		delete state_ptrs[i]->data;
		state_ptrs[i]->data = nullptr;
	}
}

template <bool INTERCEPT>
static AggregateFunction OlsAggregate(const string &name) {
	AggregateFunction result({LogicalType::DOUBLE, LogicalType::LIST(LogicalType::DOUBLE)},
	                         OlsOperation<INTERCEPT>::ReturnType(), AggregateFunction::StateSize<OlsState>,
	                         OlsInitialize, OlsScatterUpdate, OlsCombine, OlsFinalize<INTERCEPT>,
	                         FunctionNullHandling::SPECIAL_HANDLING, OlsSimpleUpdate);
	result.SetStateDestructorCallback(OlsDestroy);
	result.SetBindCallback(FinNamedArgumentsBind);
	result.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	result.name = FinanceFunctionName(name);
	return result;
}

//===--------------------------------------------------------------------===//
// Labelled covariance / correlation matrices from long-format (ts, asset, r)
//===--------------------------------------------------------------------===//
// Rows are paired by the ordering key. Each matrix entry uses the dates on
// which both assets have a return (pairwise-complete, pandas DataFrame.cov /
// corr convention) with sample (n - 1) normalization. Labels are the asset
// values cast to VARCHAR, sorted ascending. A duplicate (ts, asset) pair, or a
// NaN/inf return, makes the result NULL.
struct CovMatrixData {
	struct Entry {
		double key;
		uint32_t label;
		double value;
	};
	unordered_map<string, uint32_t> label_index;
	vector<string> labels;
	vector<Entry> entries;
	bool invalid = false;

	uint32_t Label(const string &label) {
		auto it = label_index.find(label);
		if (it != label_index.end()) {
			return it->second;
		}
		auto index = uint32_t(labels.size());
		labels.push_back(label);
		label_index.emplace(label, index);
		return index;
	}
};

struct CovMatrixState {
	CovMatrixData *data;
};

static void CovMatrixInitialize(const AggregateFunction &, data_ptr_t state) {
	reinterpret_cast<CovMatrixState *>(state)->data = nullptr;
}

static double StatReadKey(const UnifiedVectorFormat &format, PhysicalType type, idx_t index) {
	switch (type) {
	case PhysicalType::INT32:
		return double(UnifiedVectorFormat::GetData<int32_t>(format)[index]);
	case PhysicalType::INT64:
		return double(UnifiedVectorFormat::GetData<int64_t>(format)[index]);
	case PhysicalType::DOUBLE:
		return UnifiedVectorFormat::GetData<double>(format)[index];
	default:
		throw InternalException("Unsupported finance ordering key type");
	}
}

static void CovMatrixUpdateRows(Vector inputs[], idx_t count, const std::function<CovMatrixState &(idx_t)> &state_for_row) {
	UnifiedVectorFormat kdata, ldata, vdata;
	FinanceToUnifiedFormat(inputs[0], count, kdata);
	FinanceToUnifiedFormat(inputs[1], count, ldata);
	FinanceToUnifiedFormat(inputs[2], count, vdata);
	const auto key_type = inputs[0].GetType().InternalType();
	auto labels = UnifiedVectorFormat::GetData<string_t>(ldata);
	auto values = UnifiedVectorFormat::GetData<double>(vdata);
	for (idx_t i = 0; i < count; i++) {
		auto kidx = kdata.sel->get_index(i);
		auto lidx = ldata.sel->get_index(i);
		auto vidx = vdata.sel->get_index(i);
		if (!kdata.validity.RowIsValid(kidx) || !ldata.validity.RowIsValid(lidx) || !vdata.validity.RowIsValid(vidx)) {
			continue;
		}
		auto &state = state_for_row(i);
		if (!state.data) {
			state.data = new CovMatrixData();
		}
		auto &data = *state.data;
		const double value = values[vidx];
		const double key = StatReadKey(kdata, key_type, kidx);
		if (!std::isfinite(value) || !std::isfinite(key)) {
			data.invalid = true;
			continue;
		}
		data.entries.push_back({key, data.Label(labels[lidx].GetString()), value});
	}
}

static void CovMatrixScatterUpdate(Vector inputs[], AggregateInputData &, idx_t, Vector &states, idx_t count) {
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(states, count, sdata);
	auto state_ptrs = UnifiedVectorFormat::GetData<CovMatrixState *>(sdata);
	CovMatrixUpdateRows(inputs, count,
	                    [&](idx_t i) -> CovMatrixState & { return *state_ptrs[sdata.sel->get_index(i)]; });
}

static void CovMatrixSimpleUpdate(Vector inputs[], AggregateInputData &, idx_t, data_ptr_t state_ptr, idx_t count) {
	auto &state = *reinterpret_cast<CovMatrixState *>(state_ptr);
	CovMatrixUpdateRows(inputs, count, [&](idx_t) -> CovMatrixState & { return state; });
}

static void CovMatrixCombine(Vector &source, Vector &target, AggregateInputData &, idx_t count) {
	auto sources = FlatVector::GetData<CovMatrixState *>(source);
	auto targets = FlatVector::GetData<CovMatrixState *>(target);
	for (idx_t i = 0; i < count; i++) {
		auto src = sources[i]->data;
		if (!src) {
			continue;
		}
		if (!targets[i]->data) {
			targets[i]->data = new CovMatrixData(*src);
			continue;
		}
		auto &dst = *targets[i]->data;
		dst.invalid = dst.invalid || src->invalid;
		vector<uint32_t> remap(src->labels.size());
		for (idx_t l = 0; l < src->labels.size(); l++) {
			remap[l] = dst.Label(src->labels[l]);
		}
		for (auto &entry : src->entries) {
			dst.entries.push_back({entry.key, remap[entry.label], entry.value});
		}
	}
}

template <bool CORRELATION>
static LogicalType CovMatrixReturnType() {
	child_list_t<LogicalType> children;
	children.emplace_back("labels", LogicalType::LIST(LogicalType::VARCHAR));
	children.emplace_back("matrix", LogicalType::LIST(LogicalType::LIST(LogicalType::DOUBLE)));
	return LogicalType::STRUCT(std::move(children));
}

template <bool CORRELATION>
static Value CovMatrixCompute(CovMatrixData &data) {
	const auto null_result = Value(CovMatrixReturnType<CORRELATION>());
	if (data.invalid || data.entries.empty()) {
		return null_result;
	}
	const idx_t p = data.labels.size();
	vector<idx_t> order(p);
	for (idx_t i = 0; i < p; i++) {
		order[i] = i;
	}
	std::sort(order.begin(), order.end(), [&](idx_t l, idx_t r) { return data.labels[l] < data.labels[r]; });
	vector<uint32_t> rank(p);
	for (idx_t i = 0; i < p; i++) {
		rank[order[i]] = uint32_t(i);
	}
	auto entries = data.entries;
	for (auto &entry : entries) {
		entry.label = rank[entry.label];
	}
	std::sort(entries.begin(), entries.end(), [](const CovMatrixData::Entry &l, const CovMatrixData::Entry &r) {
		return l.key < r.key || (l.key == r.key && l.label < r.label);
	});
	// Pairwise moments for i >= j: count, mean_i, mean_j, m2_i, m2_j, c_ij.
	vector<std::array<double, 6>> pairs(p * (p + 1) / 2, std::array<double, 6> {0, 0, 0, 0, 0, 0});
	idx_t start = 0;
	while (start < entries.size()) {
		idx_t end = start + 1;
		while (end < entries.size() && entries[end].key == entries[start].key) {
			if (entries[end].label == entries[end - 1].label) {
				return null_result;
			}
			end++;
		}
		for (idx_t a = start; a < end; a++) {
			for (idx_t b = start; b <= a; b++) {
				const idx_t i = entries[a].label, j = entries[b].label;
				auto &m = pairs[i * (i + 1) / 2 + j];
				const double xi = entries[a].value, xj = entries[b].value;
				m[0] += 1.0;
				const double di = xi - m[1], dj = xj - m[2];
				m[1] += di / m[0];
				m[2] += dj / m[0];
				m[3] += di * (xi - m[1]);
				m[4] += dj * (xj - m[2]);
				m[5] += di * (xj - m[2]);
			}
		}
		start = end;
	}
	vector<Value> label_values, rows;
	for (idx_t i = 0; i < p; i++) {
		label_values.push_back(Value(data.labels[order[i]]));
	}
	for (idx_t i = 0; i < p; i++) {
		vector<Value> row;
		for (idx_t j = 0; j < p; j++) {
			const auto &m = pairs[i >= j ? i * (i + 1) / 2 + j : j * (j + 1) / 2 + i];
			double value = StatNaN();
			if (CORRELATION) {
				if (m[0] >= 2.0 && m[3] > 0.0 && m[4] > 0.0) {
					value = i == j ? 1.0 : std::max(-1.0, std::min(1.0, m[5] / std::sqrt(m[3] * m[4])));
				}
			} else if (m[0] >= 2.0) {
				value = m[5] / (m[0] - 1.0);
			}
			row.push_back(std::isfinite(value) ? Value::DOUBLE(value) : Value(LogicalType::DOUBLE));
		}
		rows.push_back(Value::LIST(LogicalType::DOUBLE, row));
	}
	child_list_t<Value> children;
	children.emplace_back("labels", Value::LIST(LogicalType::VARCHAR, label_values));
	children.emplace_back("matrix", Value::LIST(LogicalType::LIST(LogicalType::DOUBLE), rows));
	return Value::STRUCT(std::move(children));
}

template <bool CORRELATION>
static void CovMatrixFinalize(Vector &states, AggregateInputData &, Vector &result, idx_t count, idx_t offset) {
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(states, count, sdata);
	auto state_ptrs = UnifiedVectorFormat::GetData<CovMatrixState *>(sdata);
	for (idx_t i = 0; i < count; i++) {
		auto &state = *state_ptrs[sdata.sel->get_index(i)];
		result.SetValue(i + offset, state.data ? CovMatrixCompute<CORRELATION>(*state.data)
		                                       : Value(CovMatrixReturnType<CORRELATION>()));
	}
}

static void CovMatrixDestroy(Vector &states, AggregateInputData &, idx_t count) {
	auto state_ptrs = FlatVector::GetData<CovMatrixState *>(states);
	for (idx_t i = 0; i < count; i++) {
		delete state_ptrs[i]->data;
		state_ptrs[i]->data = nullptr;
	}
}

// The asset argument accepts any type; it is cast to VARCHAR labels at bind.
static unique_ptr<FunctionData> CovMatrixBind(ClientContext &context, AggregateFunction &function,
                                              vector<unique_ptr<Expression>> &arguments) {
	FinRejectNamedArguments(function, arguments);
	if (arguments[1]->return_type.id() != LogicalTypeId::VARCHAR) {
		arguments[1] = BoundCastExpression::AddCastToType(context, std::move(arguments[1]), LogicalType::VARCHAR);
	}
	function.arguments[1] = LogicalType::VARCHAR;
	return nullptr;
}

template <bool CORRELATION>
static void RegisterCovMatrixSet(ExtensionLoader &loader, const string &name) {
	AggregateFunctionSet set(FinanceFunctionName(name));
	for (auto &key_type : StatOrderKeyTypes()) {
		AggregateFunction function({key_type, LogicalType::ANY, LogicalType::DOUBLE}, CovMatrixReturnType<CORRELATION>(),
		                           AggregateFunction::StateSize<CovMatrixState>, CovMatrixInitialize,
		                           CovMatrixScatterUpdate, CovMatrixCombine, CovMatrixFinalize<CORRELATION>,
		                           FunctionNullHandling::SPECIAL_HANDLING, CovMatrixSimpleUpdate);
		function.SetStateDestructorCallback(CovMatrixDestroy);
		function.SetBindCallback(CovMatrixBind);
		function.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
		function.name = FinanceFunctionName(name);
		set.AddFunction(std::move(function));
	}
	loader.RegisterFunction(std::move(set));
}

//===--------------------------------------------------------------------===//
// Registration
//===--------------------------------------------------------------------===//
static void RegisterStatisticsAggregates(ExtensionLoader &loader) {
	const auto DOUBLE = FinanceLogicalType(LogicalTypeId::DOUBLE);
	const auto BIGINT = FinanceLogicalType(LogicalTypeId::BIGINT);
	const auto VARCHAR = FinanceLogicalType(LogicalTypeId::VARCHAR);
	const auto BOOLEAN = FinanceLogicalType(LogicalTypeId::BOOLEAN);

	// Public windowable natives.
	RegisterDecaySet<DecayKind::SUM>(loader, "fin_exp_decay_sum");
	RegisterDecaySet<DecayKind::AVG>(loader, "fin_exp_decay_avg");
	RegisterDecaySet<DecayKind::AVG>(loader, "fin_ema_halflife");
	RegisterDecaySet<DecayKind::COUNT>(loader, "fin_exp_decay_count");
	RegisterDecaySet<DecayKind::MAX>(loader, "fin_exp_decay_max");
	{
		vector<AggregateFunction> functions;
		for (auto &key_type : StatOrderKeyTypes()) {
			functions.push_back(FinAggregate<RollingZscoreState, RollingZscoreOperation>("fin_rolling_zscore",
			                                                                             {DOUBLE, key_type}));
		}
		FinRegisterSet(loader, "fin_rolling_zscore", std::move(functions));
	}
	FinRegisterSet(loader, "fin_rolling_beta",
	               {FinAggregate<BetaState, BetaOperation>("fin_rolling_beta", {DOUBLE, DOUBLE})});
	loader.RegisterFunction(OlsAggregate<true>("fin_ols"));
	loader.RegisterFunction(OlsAggregate<false>("fin_ols_no_intercept"));
	RegisterCovMatrixSet<false>(loader, "fin_cov_matrix");
	RegisterCovMatrixSet<true>(loader, "fin_corr_matrix");
	FinRegisterSet(loader, "fin_ks_test",
	               {StatStructAggregate<StatHistoryState, KSTestOperation>("fin_ks_test", {DOUBLE, DOUBLE})});
	FinRegisterSet(loader, "fin_mann_whitney_u",
	               {StatStructAggregate<StatHistoryState, MannWhitneyOperation>("fin_mann_whitney_u", {DOUBLE, DOUBLE})});

	// Internal kernels behind SQL macros (macros provide named parameters,
	// hashing of categorical inputs and ordering-key normalization).
	loader.RegisterFunction(
	    StatStructAggregate<StatHistoryState, AnovaOperation>("finance_anova_oneway_internal", {DOUBLE, BIGINT}));
	loader.RegisterFunction(StatScalarAggregate<StatHistoryState, CorrelationOperation<0>>(
	    "finance_rank_corr_internal", {DOUBLE, DOUBLE, VARCHAR}));
	loader.RegisterFunction(StatScalarAggregate<StatHistoryState, CorrelationOperation<1>>(
	    "finance_factor_ic_internal", {DOUBLE, DOUBLE, VARCHAR}));
	loader.RegisterFunction(StatScalarAggregate<StatHistoryState, MutualInformationOperation>(
	    "finance_mutual_information_internal", {DOUBLE, DOUBLE, BIGINT}));
	loader.RegisterFunction(StatScalarAggregate<StatHistoryState, CategoricalAssociationOperation<0>>(
	    "finance_cramers_v_internal", {BIGINT, BIGINT, BOOLEAN}));
	loader.RegisterFunction(StatScalarAggregate<StatHistoryState, CategoricalAssociationOperation<1>>(
	    "finance_theils_u_internal", {BIGINT, BIGINT}));

	AggregateFunctionSet turnover(FinanceFunctionName("finance_factor_turnover_internal"));
	AggregateFunctionSet autocorr(FinanceFunctionName("finance_autocorr_internal"));
	AggregateFunctionSet crosscorr(FinanceFunctionName("finance_crosscorr_internal"));
	AggregateFunctionSet hurst(FinanceFunctionName("finance_hurst_internal"));
	AggregateFunctionSet half_life(FinanceFunctionName("finance_half_life_internal"));
	AggregateFunctionSet adf(FinanceFunctionName("finance_adf_internal"));
	AggregateFunctionSet ljung_box(FinanceFunctionName("finance_ljung_box_internal"));
	AggregateFunctionSet newey_west(FinanceFunctionName("finance_newey_west_internal"));
	AggregateFunctionSet garch_fit(FinanceFunctionName("finance_garch11_fit_internal"));
	for (auto &key : StatOrderKeyTypes()) {
		turnover.AddFunction(StatScalarAggregate<StatHistoryState, FactorTurnoverOperation>(
		    "finance_factor_turnover_internal", {key, BIGINT, DOUBLE, BIGINT}));
		autocorr.AddFunction(StatScalarAggregate<StatHistoryState, LaggedCorrelationOperation<0>>(
		    "finance_autocorr_internal", {DOUBLE, key, BIGINT}));
		crosscorr.AddFunction(StatScalarAggregate<StatHistoryState, LaggedCorrelationOperation<1>>(
		    "finance_crosscorr_internal", {DOUBLE, DOUBLE, key, BIGINT}));
		hurst.AddFunction(
		    StatScalarAggregate<StatHistoryState, HurstOperation>("finance_hurst_internal", {DOUBLE, key}));
		half_life.AddFunction(
		    StatScalarAggregate<StatHistoryState, HalfLifeOperation>("finance_half_life_internal", {DOUBLE, key}));
		adf.AddFunction(StatStructAggregate<StatHistoryState, AdfOperation>("finance_adf_internal",
		                                                                    {DOUBLE, key, BIGINT, VARCHAR}));
		ljung_box.AddFunction(StatStructAggregate<StatHistoryState, LjungBoxOperation>("finance_ljung_box_internal",
		                                                                               {DOUBLE, key, BIGINT}));
		newey_west.AddFunction(StatScalarAggregate<StatHistoryState, NeweyWestOperation>(
		    "finance_newey_west_internal", {DOUBLE, DOUBLE, key, BIGINT}));
		garch_fit.AddFunction(
		    StatStructAggregate<StatHistoryState, GarchFitOperation>("finance_garch11_fit_internal", {DOUBLE, key}));
	}
	loader.RegisterFunction(std::move(turnover));
	loader.RegisterFunction(std::move(autocorr));
	loader.RegisterFunction(std::move(crosscorr));
	loader.RegisterFunction(std::move(hurst));
	loader.RegisterFunction(std::move(half_life));
	loader.RegisterFunction(std::move(adf));
	loader.RegisterFunction(std::move(ljung_box));
	loader.RegisterFunction(std::move(newey_west));
	loader.RegisterFunction(std::move(garch_fit));
}
