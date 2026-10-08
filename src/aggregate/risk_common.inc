// Shared machinery for the returns/risk native aggregates.
//
// Operations implemented on top of this file see every input row as a FinRow of
// doubles. BOOLEAN inputs arrive as 0/1, integer inputs are widened, and VARCHAR
// configuration inputs (method names) are parsed by OP::ParseText once per
// distinct string pointer, so a constant method is parsed once per chunk rather
// than once per row.

constexpr idx_t FIN_MAX_AGGREGATE_ARGS = 8;

struct FinRow {
	double v[FIN_MAX_AGGREGATE_ARGS];
	bool valid[FIN_MAX_AGGREGATE_ARGS];
};

struct FinTextCache {
	bool set[FIN_MAX_AGGREGATE_ARGS] = {false};
	string text[FIN_MAX_AGGREGATE_ARGS];
	double code[FIN_MAX_AGGREGATE_ARGS] = {0.0};
};

static bool FinTextEquals(string_t text, const char *literal) {
	auto size = text.GetSize();
	if (size != strlen(literal)) {
		return false;
	}
	auto data = text.GetData();
	for (idx_t i = 0; i < size; i++) {
		if (std::tolower(static_cast<unsigned char>(data[i])) != literal[i]) {
			return false;
		}
	}
	return true;
}

// Text configuration is compared against the previous row's value and parsed
// only when it changes, so a constant method costs one short comparison per row.
template <class OP>
static double FinParseCachedText(FinTextCache &cache, idx_t column, string_t text) {
	auto size = text.GetSize();
	if (cache.set[column] && cache.text[column].size() == size &&
	    (size == 0 || memcmp(cache.text[column].data(), text.GetData(), size) == 0)) {
		return cache.code[column];
	}
	cache.code[column] = OP::ParseText(column, text);
	cache.text[column].assign(text.GetData(), size);
	cache.set[column] = true;
	return cache.code[column];
}

template <class OP>
static void FinReadValue(const_data_ptr_t base, PhysicalType type, idx_t index, FinRow &row, idx_t column,
                         FinTextCache &cache) {
	switch (type) {
	case PhysicalType::DOUBLE:
		row.v[column] = reinterpret_cast<const double *>(base)[index];
		break;
	case PhysicalType::BOOL:
		row.v[column] = reinterpret_cast<const bool *>(base)[index] ? 1.0 : 0.0;
		break;
	case PhysicalType::INT32:
		row.v[column] = static_cast<double>(reinterpret_cast<const int32_t *>(base)[index]);
		break;
	case PhysicalType::INT64:
		row.v[column] = static_cast<double>(reinterpret_cast<const int64_t *>(base)[index]);
		break;
	case PhysicalType::INTERVAL: {
		// Intervals (e.g. half-lives) are read as microseconds; months count as 30 days.
		int64_t micros;
		auto interval = reinterpret_cast<const interval_t *>(base)[index];
		row.v[column] = Interval::TryGetMicro(interval, micros) ? static_cast<double>(micros)
		                                                       : std::numeric_limits<double>::quiet_NaN();
		break;
	}
	case PhysicalType::VARCHAR: {
		// Point at the string_t header and parse once per distinct string.
		auto text = reinterpret_cast<const string_t *>(base)[index];
		row.v[column] = FinParseCachedText<OP>(cache, column, text);
		break;
	}
	default:
		throw InternalException("Unsupported finance aggregate argument type");
	}
}

// A row counts when its leading value columns are non-NULL and every other
// argument is non-NULL unless the operation accepts NULL for it (for example a
// NULL GARCH seed meaning "use the sample variance"). This matches DuckDB's
// default of skipping rows with any NULL argument.
template <class OP>
static bool FinRowCounts(const FinRow &row, idx_t input_count) {
	for (idx_t c = 0; c < input_count; c++) {
		if (!row.valid[c] && (c < OP::REQUIRED_ARGS || !OP::NullableArgument(c))) {
			return false;
		}
	}
	return true;
}

template <class STATE, class OP, class STATE_ACCESS>
static void FinUpdateLoop(Vector inputs[], idx_t input_count, idx_t count, STATE_ACCESS &&state_for_row) {
	D_ASSERT(input_count <= FIN_MAX_AGGREGATE_ARGS);
	UnifiedVectorFormat formats[FIN_MAX_AGGREGATE_ARGS];
	PhysicalType types[FIN_MAX_AGGREGATE_ARGS];
	for (idx_t c = 0; c < input_count; c++) {
		FinanceToUnifiedFormat(inputs[c], count, formats[c]);
		types[c] = inputs[c].GetType().InternalType();
	}
	FinTextCache cache;
	FinRow row;
	idx_t indexes[FIN_MAX_AGGREGATE_ARGS];
	for (idx_t i = 0; i < count; i++) {
		for (idx_t c = 0; c < input_count; c++) {
			indexes[c] = formats[c].sel->get_index(i);
			row.valid[c] = formats[c].validity.RowIsValid(indexes[c]);
		}
		if (!FinRowCounts<OP>(row, input_count)) {
			continue;
		}
		for (idx_t c = 0; c < input_count; c++) {
			if (row.valid[c]) {
				FinReadValue<OP>(formats[c].data, types[c], indexes[c], row, c, cache);
			} else {
				row.v[c] = std::numeric_limits<double>::quiet_NaN();
			}
		}
		OP::UpdateRow(state_for_row(i), row, input_count);
	}
}

template <class STATE, class OP>
static void FinScatterUpdate(Vector inputs[], AggregateInputData &, idx_t input_count, Vector &states, idx_t count) {
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(states, count, sdata);
	auto state_values = UnifiedVectorFormat::GetData<STATE *>(sdata);
	FinUpdateLoop<STATE, OP>(inputs, input_count, count,
	                         [&](idx_t i) -> STATE & { return *state_values[sdata.sel->get_index(i)]; });
}

template <class STATE, class OP>
static void FinSimpleUpdate(Vector inputs[], AggregateInputData &, idx_t input_count, data_ptr_t state_ptr,
                            idx_t count) {
	auto &state = *reinterpret_cast<STATE *>(state_ptr);
	FinUpdateLoop<STATE, OP>(inputs, input_count, count, [&](idx_t) -> STATE & { return state; });
}

//===--------------------------------------------------------------------===//
// Window support
//===--------------------------------------------------------------------===//
// A frame-by-frame window evaluator. Running frames (fixed start, growing end)
// are updated incrementally; any other frame is rebuilt from the frame rows into
// the same local state, so no per-row history copies are made and memory stays
// bounded by one frame.
struct FinWindowAux {
	const ColumnDataCollection *inputs = nullptr;
	ColumnDataScanState scan;
	unique_ptr<DataChunk> page;
	bool has_prev = false;
	idx_t prev_start = 0;
	idx_t prev_end = 0;
	FinTextCache cache;
	// Decoded rows of the current single frame, kept so that a sliding frame
	// only reads the rows entering it from the collection.
	struct CachedRow {
		idx_t index;
		FinRow row;
	};
	std::deque<CachedRow> rows;
	bool rows_valid = false;
	idx_t rows_start = 0;
	idx_t rows_end = 0;

	void Initialize(const WindowPartitionInput &partition) {
		if (page && inputs == partition.inputs) {
			return;
		}
		D_ASSERT(partition.inputs);
		inputs = partition.inputs;
		scan = ColumnDataScanState();
		page = make_uniq<DataChunk>();
		inputs->InitializeScan(scan, partition.column_ids);
		inputs->InitializeScanChunk(scan, *page);
		has_prev = false;
		cache = FinTextCache();
		rows.clear();
		rows_valid = false;
	}

	idx_t Seek(idx_t row_idx) {
		if (!(row_idx < scan.next_row_index && scan.current_row_index <= row_idx)) {
			inputs->Seek(row_idx, scan, *page);
		}
		return row_idx - scan.current_row_index;
	}

	// Decodes one row; returns false (without decoding) when the row does not count.
	template <class OP>
	bool Read(idx_t row_idx, FinRow &row) {
		auto offset = Seek(row_idx);
		const auto column_count = page->ColumnCount();
		for (idx_t c = 0; c < column_count; c++) {
			row.valid[c] = FlatVector::Validity(page->data[c]).RowIsValid(offset);
		}
		if (!FinRowCounts<OP>(row, column_count)) {
			return false;
		}
		for (idx_t c = 0; c < column_count; c++) {
			auto &vector = page->data[c];
			if (row.valid[c]) {
				FinReadValue<OP>(FlatVector::GetData(vector), vector.GetType().InternalType(), offset, row, c, cache);
			} else {
				row.v[c] = std::numeric_limits<double>::quiet_NaN();
			}
		}
		return true;
	}
};

template <class OP, bool VALUE_REPLAY>
struct FinReplayer {
	template <class STATE, class ROWS>
	static void Run(STATE &state, const ROWS &rows, idx_t input_count) {
		for (const auto &cached : rows) {
			OP::UpdateRow(state, cached.row, input_count);
		}
	}
};

template <class OP>
struct FinReplayer<OP, true> {
	template <class STATE, class ROWS>
	static void Run(STATE &state, const ROWS &rows, idx_t input_count) {
		if (rows.empty()) {
			return;
		}
		const auto &first = rows.front().row;
		OP::UpdateRow(state, first, input_count);
		for (auto it = rows.begin() + 1; it != rows.end(); ++it) {
			const auto &row = it->row;
			bool same = true;
			for (idx_t c = 1; c < input_count; c++) {
				same = same && row.valid[c] == first.valid[c] &&
				       (row.v[c] == first.v[c] || (std::isnan(row.v[c]) && std::isnan(first.v[c])));
			}
			if (same) {
				OP::AddValue(state, row.v[0]);
			} else {
				OP::UpdateRow(state, row, input_count);
			}
		}
	}
};

template <class STATE, class OP, class RESULT_TYPE>
static void FinWindow(AggregateInputData &aggr_input_data, const WindowPartitionInput &partition, const_data_ptr_t,
                      data_ptr_t l_state, const SubFrames &frames, Vector &result, idx_t rid) {
	auto &state = *reinterpret_cast<STATE *>(l_state);
	if (!state.window) {
		state.window = new FinWindowAux();
	}
	auto &aux = *state.window;
	aux.Initialize(partition);
	const auto input_count = partition.column_ids.size();
	const auto &filter_mask = partition.filter_mask;
	FinRow row;
	auto feed = [&](idx_t begin, idx_t end) {
		for (idx_t i = begin; i < end; i++) {
			if (!filter_mask.RowIsValid(i)) {
				continue;
			}
			if (aux.template Read<OP>(i, row)) {
				OP::UpdateRow(state, row, input_count);
			}
		}
	};
	const bool incremental = OP::WINDOW_INCREMENTAL && aux.has_prev && frames.size() == 1 &&
	                         frames[0].start == aux.prev_start && frames[0].end >= aux.prev_end;
	if (incremental) {
		// Running frame: append the rows that entered the frame.
		feed(aux.prev_end, frames[0].end);
		aux.rows_valid = false;
	} else if (frames.size() == 1) {
		// Any other single frame: slide the decoded row cache, then rebuild the
		// state from the cached frame rows.
		const auto start = frames[0].start;
		const auto end = frames[0].end;
		if (!aux.rows_valid || start < aux.rows_start || end < aux.rows_end || start > aux.rows_end) {
			aux.rows.clear();
			aux.rows_start = aux.rows_end = start;
		}
		while (!aux.rows.empty() && aux.rows.front().index < start) {
			aux.rows.pop_front();
		}
		for (idx_t i = aux.rows_end; i < end; i++) {
			if (!filter_mask.RowIsValid(i)) {
				continue;
			}
			if (aux.template Read<OP>(i, row)) {
				aux.rows.push_back({i, row});
			}
		}
		aux.rows_start = start;
		aux.rows_end = end;
		aux.rows_valid = true;
		OP::WindowReset(state);
		FinReplayer<OP, OP::VALUE_REPLAY>::Run(state, aux.rows, input_count);
	} else {
		aux.rows_valid = false;
		OP::WindowReset(state);
		for (const auto &frame : frames) {
			feed(frame.start, frame.end);
		}
	}
	aux.has_prev = frames.size() == 1;
	if (aux.has_prev) {
		aux.prev_start = frames[0].start;
		aux.prev_end = frames[0].end;
	}
	AggregateFinalizeData finalize_data(result, aggr_input_data);
	finalize_data.result_idx = rid;
	auto rdata = FlatVector::GetData<RESULT_TYPE>(result);
	OP::template Finalize<RESULT_TYPE, STATE>(state, rdata[rid], finalize_data);
}

//===--------------------------------------------------------------------===//
// Bind: named-argument rejection and constant validation
//===--------------------------------------------------------------------===//
// DuckDB binds native function arguments by position and silently drops `:=`
// names. A named argument on a constant (`annualization := 12`) is detectable at
// bind because the expression keeps the name as its alias, so reject it rather
// than silently applying the value to the wrong parameter. Column references
// carry their column name as alias and cannot be distinguished.
static void FinRejectNamedArguments(const AggregateFunction &function, vector<unique_ptr<Expression>> &arguments) {
	for (auto &argument : arguments) {
		if (argument->GetExpressionClass() == ExpressionClass::BOUND_COLUMN_REF || argument->GetAlias().empty()) {
			continue;
		}
		throw InvalidInputException("%s: named argument '%s := ...' is not supported; native aggregate arguments "
		                            "bind by position, so pass every argument positionally",
		                            function.name, argument->GetAlias());
	}
}

static unique_ptr<FunctionData> FinNamedArgumentsBind(ClientContext &, AggregateFunction &function,
                                                      vector<unique_ptr<Expression>> &arguments) {
	FinRejectNamedArguments(function, arguments);
	return nullptr;
}

template <class OP>
static unique_ptr<FunctionData> FinValidatingBind(ClientContext &context, AggregateFunction &function,
                                                  vector<unique_ptr<Expression>> &arguments) {
	FinRejectNamedArguments(function, arguments);
	// Constant configuration is validated once at bind so invalid settings fail
	// even on empty input. Non-constant configuration (for example macro
	// parameters) is validated by UpdateRow.
	for (idx_t c = OP::REQUIRED_ARGS; c < arguments.size(); c++) {
		auto &argument = *arguments[c];
		if (!argument.IsFoldable()) {
			continue;
		}
		auto value = ExpressionExecutor::EvaluateScalar(context, argument, true);
		if (value.IsNull()) {
			OP::ValidateParameter(c, std::numeric_limits<double>::quiet_NaN(), false);
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

// Default hooks for operations without text or extra parameter validation.
struct FinOperationDefaults {
	// True when the state is a plain value history: window replay then validates
	// the configuration once and appends the remaining values directly.
	static constexpr bool VALUE_REPLAY = false;
	static bool NullableArgument(idx_t) {
		return false;
	}

	static double ParseText(idx_t, string_t) {
		throw InternalException("finance aggregate has no text parameter");
	}
	static void ValidateParameter(idx_t, double, bool) {
	}
};

template <class STATE, class OP, class RESULT_TYPE = double>
static AggregateFunction FinAggregate(const string &name, vector<LogicalType> arguments,
                                      const LogicalType &return_type = LogicalType(LogicalTypeId::DOUBLE)) {
	AggregateFunction result(std::move(arguments), return_type, AggregateFunction::StateSize<STATE>,
	                         AggregateFunction::StateInitialize<STATE, OP, AggregateDestructorType::LEGACY>,
	                         FinScatterUpdate<STATE, OP>, AggregateFunction::StateCombine<STATE, OP>,
	                         AggregateFunction::StateFinalize<STATE, RESULT_TYPE, OP>,
	                         FunctionNullHandling::DEFAULT_NULL_HANDLING, FinSimpleUpdate<STATE, OP>);
	result.SetStateDestructorCallback(AggregateFunction::StateDestroy<STATE, OP>);
	result.SetBindCallback(FinValidatingBind<OP>);
	result.SetOrderDependent(OP::ORDER_DEPENDENT ? AggregateOrderDependent::ORDER_DEPENDENT
	                                             : AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	result.name = FinanceFunctionName(name);
	return result;
}

// History-keeping aggregates also get a frame-by-frame window callback.
template <class STATE, class OP, class RESULT_TYPE = double>
static AggregateFunction FinWindowAggregate(const string &name, vector<LogicalType> arguments,
                                            const LogicalType &return_type = LogicalType(LogicalTypeId::DOUBLE)) {
	auto result = FinAggregate<STATE, OP, RESULT_TYPE>(name, std::move(arguments), return_type);
	result.SetWindowCallback(FinWindow<STATE, OP, RESULT_TYPE>);
	return result;
}

static vector<LogicalType> FinDoubles(idx_t count) {
	return vector<LogicalType>(count, LogicalType(LogicalTypeId::DOUBLE));
}

static void FinRegisterSet(ExtensionLoader &loader, const string &name, vector<AggregateFunction> functions) {
	AggregateFunctionSet set(FinanceFunctionName(name));
	for (auto &function : functions) {
		set.AddFunction(std::move(function));
	}
	loader.RegisterFunction(std::move(set));
}

//===--------------------------------------------------------------------===//
// Numeric helpers
//===--------------------------------------------------------------------===//
// Geometric de-annualization of an annual rate: (1 + rate)^(1 / periods) - 1.
static double FinPeriodicRate(double annual_rate, double annualization) {
	if (annual_rate == 0.0) {
		return 0.0;
	}
	if (!std::isfinite(annual_rate) || annual_rate <= -1.0) {
		return std::numeric_limits<double>::quiet_NaN();
	}
	return std::expm1(std::log1p(annual_rate) / annualization);
}

struct FinPeriodicRateCache {
	double rate = 0.0;
	double annualization = 0.0;
	double periodic = 0.0;
	bool set = false;

	double Get(double annual_rate, double periodicity) {
		if (!set || rate != annual_rate || annualization != periodicity) {
			rate = annual_rate;
			annualization = periodicity;
			periodic = FinPeriodicRate(annual_rate, periodicity);
			set = true;
		}
		return periodic;
	}
};

// Welford running moments with Chan et al. pairwise merging.
struct FinMoments {
	double count;
	double mean;
	double m2;

	void Reset() {
		count = 0.0;
		mean = 0.0;
		m2 = 0.0;
	}

	void Add(double value) {
		count += 1.0;
		auto delta = value - mean;
		mean += delta / count;
		m2 += delta * (value - mean);
	}

	void Merge(const FinMoments &other) {
		if (other.count == 0.0) {
			return;
		}
		if (count == 0.0) {
			*this = other;
			return;
		}
		auto total = count + other.count;
		auto delta = other.mean - mean;
		mean += delta * (other.count / total);
		m2 += other.m2 + delta * delta * (count * other.count / total);
		count = total;
	}
};

// Neumaier-compensated sum.
struct FinSum {
	double sum;
	double correction;

	void Reset() {
		sum = 0.0;
		correction = 0.0;
	}

	void Add(double value) {
		auto next = sum + value;
		correction += std::abs(sum) >= std::abs(value) ? (sum - next) + value : (value - next) + sum;
		sum = next;
	}

	void Merge(const FinSum &other) {
		Add(other.sum);
		Add(other.correction);
	}

	double Value() const {
		return sum + correction;
	}
};

// Standard normal quantile: Acklam's rational approximation refined by one
// Halley step against erfc, accurate to about 1e-15 relative.
static double FinNormalQuantile(double p) {
	if (!(p > 0.0 && p < 1.0)) {
		return std::numeric_limits<double>::quiet_NaN();
	}
	static const double a[] = {-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
	                           1.383577518672690e+02,  -3.066479806614716e+01, 2.506628277459239e+00};
	static const double b[] = {-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
	                           6.680131188771972e+01,  -1.328068155288572e+01};
	static const double c[] = {-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
	                           -2.549732539343734e+00, 4.374664141464968e+00,  2.938163982698783e+00};
	static const double d[] = {7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
	                           3.754408661907416e+00};
	double x;
	if (p < 0.02425) {
		auto q = std::sqrt(-2.0 * std::log(p));
		x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
		    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0);
	} else if (p > 1.0 - 0.02425) {
		auto q = std::sqrt(-2.0 * std::log1p(-p));
		x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
		    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0);
	} else {
		auto q = p - 0.5;
		auto r = q * q;
		x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
		    (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1.0);
	}
	constexpr double SQRT_2PI = 2.50662827463100050242;
	constexpr double SQRT_HALF = 0.70710678118654752440;
	for (int iteration = 0; iteration < 2; iteration++) {
		auto e = 0.5 * std::erfc(-x * SQRT_HALF) - p;
		auto u = e * SQRT_2PI * std::exp(0.5 * x * x);
		x = x - u / (1.0 + 0.5 * x * u);
	}
	return x;
}

static double FinNormalPdf(double x) {
	constexpr double INV_SQRT_2PI = 0.39894228040143267794;
	return INV_SQRT_2PI * std::exp(-0.5 * x * x);
}

// Linear-interpolation quantile position (quantile_cont / numpy 'linear').
// Positions within 1e-9 of an order statistic snap to it so that 1 - 0.9 =
// 0.09999999999999998 does not exclude the order statistic it names.
static double FinQuantilePosition(double quantile, idx_t n) {
	auto position = quantile * static_cast<double>(n - 1);
	auto rounded = std::round(position);
	if (std::abs(position - rounded) <= 1e-9 * std::max(1.0, rounded)) {
		position = rounded;
	}
	return std::min(std::max(position, 0.0), static_cast<double>(n - 1));
}

// Continuous quantile; partially reorders values.
static double FinContinuousQuantile(vector<double> &values, double quantile) {
	D_ASSERT(!values.empty());
	if (values.size() == 1) {
		return values[0];
	}
	auto position = FinQuantilePosition(quantile, values.size());
	auto lower = static_cast<idx_t>(std::floor(position));
	auto fraction = position - static_cast<double>(lower);
	std::nth_element(values.begin(), values.begin() + lower, values.end());
	auto lower_value = values[lower];
	if (fraction == 0.0 || lower + 1 >= values.size()) {
		return lower_value;
	}
	auto upper_value = *std::min_element(values.begin() + lower + 1, values.end());
	return ConvexCombination(lower_value, upper_value, fraction);
}
