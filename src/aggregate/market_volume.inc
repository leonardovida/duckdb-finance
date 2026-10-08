//===--------------------------------------------------------------------===//
// Order-independent volume and liquidity aggregates
//===--------------------------------------------------------------------===//
// fin_vwap, fin_ad_line, fin_amihud_illiquidity, fin_kyle_lambda and
// fin_volume_profile do not depend on row order, so they merge partial states
// freely and run as window functions over any frame (DuckDB segment trees).
// fin_twap merges time-disjoint partial states using its timestamp argument.
// Rows with a NULL input are skipped; a non-finite input (or an invalid volume)
// makes the group NULL.

// Compensated (Neumaier) running sum; partial sums merge with their error terms
// so results are practically independent of how rows were partitioned.
struct FinCompensatedSum {
	double hi;
	double lo;

	void Clear() {
		hi = lo = 0.0;
	}

	void Add(double x) {
		auto sum = hi + x;
		if (std::abs(hi) >= std::abs(x)) {
			lo += (hi - sum) + x;
		} else {
			lo += (x - sum) + hi;
		}
		hi = sum;
	}

	void Add(const FinCompensatedSum &other) {
		Add(other.hi);
		lo += other.lo;
	}

	double Value() const {
		return hi + lo;
	}
};

// Scatter/simple update for N DOUBLE inputs, skipping rows with any NULL.
template <class STATE, class OP, idx_t N>
static void FinDoubleRowsScatter(Vector inputs[], AggregateInputData &, idx_t, Vector &states, idx_t count) {
	UnifiedVectorFormat formats[N];
	const double *data[N];
	for (idx_t c = 0; c < N; c++) {
		FinanceToUnifiedFormat(inputs[c], count, formats[c]);
		data[c] = UnifiedVectorFormat::GetData<double>(formats[c]);
	}
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(states, count, sdata);
	auto state_values = UnifiedVectorFormat::GetData<STATE *>(sdata);
	double row[N];
	for (idx_t i = 0; i < count; i++) {
		bool valid = true;
		for (idx_t c = 0; c < N && valid; c++) {
			auto index = formats[c].sel->get_index(i);
			valid = formats[c].validity.RowIsValid(index);
			row[c] = data[c][index];
		}
		if (valid) {
			OP::UpdateRow(*state_values[sdata.sel->get_index(i)], row);
		}
	}
}

template <class STATE, class OP, idx_t N>
static void FinDoubleRowsSimpleUpdate(Vector inputs[], AggregateInputData &, idx_t, data_ptr_t state_ptr,
                                      idx_t count) {
	UnifiedVectorFormat formats[N];
	const double *data[N];
	for (idx_t c = 0; c < N; c++) {
		FinanceToUnifiedFormat(inputs[c], count, formats[c]);
		data[c] = UnifiedVectorFormat::GetData<double>(formats[c]);
	}
	auto &state = *reinterpret_cast<STATE *>(state_ptr);
	double row[N];
	for (idx_t i = 0; i < count; i++) {
		bool valid = true;
		for (idx_t c = 0; c < N && valid; c++) {
			auto index = formats[c].sel->get_index(i);
			valid = formats[c].validity.RowIsValid(index);
			row[c] = data[c][index];
		}
		if (valid) {
			OP::UpdateRow(state, row);
		}
	}
}

template <class STATE, class OP, idx_t N>
static AggregateFunction FinDoubleRowsAggregate(const string &name) {
	vector<LogicalType> arguments(N, FinanceLogicalType(LogicalTypeId::DOUBLE));
	AggregateFunction function(arguments, FinanceLogicalType(LogicalTypeId::DOUBLE), AggregateFunction::StateSize<STATE>,
	                           AggregateFunction::StateInitialize<STATE, OP>, FinDoubleRowsScatter<STATE, OP, N>,
	                           AggregateFunction::StateCombine<STATE, OP>,
	                           AggregateFunction::StateFinalize<STATE, double, OP>,
	                           FunctionNullHandling::DEFAULT_NULL_HANDLING, FinDoubleRowsSimpleUpdate<STATE, OP, N>);
	function.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	function.SetBindCallback(FinNamedArgumentsBind);
	return NamedAggregateFunction(name, std::move(function));
}

// Two compensated sums plus a row count and an invalid-input flag.
struct FinSumPairState {
	FinCompensatedSum first;
	FinCompensatedSum second;
	idx_t count;
	bool invalid;
};

struct FinSumPairOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.first.Clear();
		state.second.Clear();
		state.count = 0;
		state.invalid = false;
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.first.Add(source.first);
		target.second.Add(source.second);
		target.count += source.count;
		target.invalid = target.invalid || source.invalid;
	}

	static bool IgnoreNull() {
		return true;
	}
};

// VWAP = sum(price * volume) / sum(volume). Negative volume is invalid; a zero
// total volume gives NULL.
struct FinVwapOperation : public FinSumPairOperation {
	static void UpdateRow(FinSumPairState &state, const double *row) {
		auto price = row[0];
		auto volume = row[1];
		auto notional = price * volume;
		if (!std::isfinite(notional) || !std::isfinite(volume) || volume < 0.0) {
			state.invalid = true;
			return;
		}
		state.first.Add(notional);
		state.second.Add(volume);
		state.count++;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		auto volume = state.second.Value();
		if (state.invalid || state.count == 0 || volume == 0.0) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.first.Value() / volume;
		if (!std::isfinite(target)) {
			finalize_data.ReturnNull();
		}
	}
};

// Chaikin accumulation/distribution line: the sum of the bars' money-flow
// volume (TA-Lib AD; bars with high <= low add 0).
struct FinAdLineOperation : public FinSumPairOperation {
	static void UpdateRow(FinSumPairState &state, const double *row) {
		for (idx_t c = 0; c < 4; c++) {
			if (!std::isfinite(row[c])) {
				state.invalid = true;
				return;
			}
		}
		state.first.Add(TechMoneyFlowVolume(row[0], row[1], row[2], row[3]));
		state.count++;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.first.Value();
		if (!std::isfinite(target)) {
			finalize_data.ReturnNull();
		}
	}
};

// Amihud (2002) illiquidity: mean of |return| / dollar volume over rows with
// positive dollar volume (zero-volume rows carry no price impact and are
// skipped; negative dollar volume is invalid).
struct FinAmihudOperation : public FinSumPairOperation {
	static void UpdateRow(FinSumPairState &state, const double *row) {
		auto magnitude = std::abs(row[0]);
		auto dollar_volume = row[1];
		if (!std::isfinite(magnitude) || !std::isfinite(dollar_volume) || dollar_volume < 0.0) {
			state.invalid = true;
			return;
		}
		if (dollar_volume == 0.0) {
			return;
		}
		state.first.Add(magnitude / dollar_volume);
		state.count++;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.first.Value() / static_cast<double>(state.count);
		if (!std::isfinite(target)) {
			finalize_data.ReturnNull();
		}
	}
};

// Kyle (1985) lambda: OLS slope (with intercept) of price changes on signed
// order flow, accumulated with Welford updates and Chan et al. merges.
struct FinKyleLambdaState {
	double n;
	double mean_x;
	double mean_y;
	double sxx;
	double sxy;
	bool invalid;
};

struct FinKyleLambdaOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.n = state.mean_x = state.mean_y = state.sxx = state.sxy = 0.0;
		state.invalid = false;
	}

	static void UpdateRow(FinKyleLambdaState &state, const double *row) {
		auto y = row[0];
		auto x = row[1];
		if (!std::isfinite(x) || !std::isfinite(y)) {
			state.invalid = true;
			return;
		}
		state.n += 1.0;
		auto dx = x - state.mean_x;
		state.mean_x += dx / state.n;
		state.mean_y += (y - state.mean_y) / state.n;
		state.sxx += dx * (x - state.mean_x);
		state.sxy += dx * (y - state.mean_y);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		target.invalid = target.invalid || source.invalid;
		if (source.n == 0.0) {
			return;
		}
		if (target.n == 0.0) {
			auto invalid = target.invalid;
			target = source;
			target.invalid = invalid;
			return;
		}
		auto n = target.n + source.n;
		auto dx = source.mean_x - target.mean_x;
		auto dy = source.mean_y - target.mean_y;
		auto weight = target.n * source.n / n;
		target.sxx += source.sxx + dx * dx * weight;
		target.sxy += source.sxy + dx * dy * weight;
		target.mean_x += dx * source.n / n;
		target.mean_y += dy * source.n / n;
		target.n = n;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.invalid || state.n < 2.0 || !(state.sxx > 0.0)) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.sxy / state.sxx;
		if (!std::isfinite(target)) {
			finalize_data.ReturnNull();
		}
	}

	static bool IgnoreNull() {
		return true;
	}
};

//===--------------------------------------------------------------------===//
// fin_twap
//===--------------------------------------------------------------------===//
// Time-weighted average price: each price holds from its timestamp until the
// next distinct timestamp, TWAP = sum(price_k * (t_{k+1} - t_k)) / (t_last -
// t_first); the last timestamp carries no weight. Prices sharing a timestamp
// are averaged, so ties do not depend on row order. A single timestamp returns
// its mean price.
//
// The state covers a time range: [t0, tl], the price group at t0 (and the
// duration of its interval, t1 - t0) and at tl, and the weighted area of the
// intervals after the first one. Partial states merge when their ranges are
// disjoint, so ordered input, ordered windows and time-partitioned parallel
// input all work; interleaved ranges raise an ordering error.
struct FinTwapState {
	double t0;
	double t1;
	double tl;
	double first_sum;
	double first_count;
	double last_sum;
	double last_count;
	FinCompensatedSum area;
	idx_t distinct;
	bool invalid;
};

struct FinTwapOperation {
	static void Reset(FinTwapState &state) {
		state.t0 = state.t1 = state.tl = 0.0;
		state.first_sum = state.first_count = state.last_sum = state.last_count = 0.0;
		state.area.Clear();
		state.distinct = 0;
		state.invalid = false;
	}

	template <class STATE>
	static void Initialize(STATE &state) {
		Reset(state.twap);
		state.window = nullptr;
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.window;
		state.window = nullptr;
	}

	static double FirstMean(const FinTwapState &state) {
		return state.first_sum / state.first_count;
	}

	static double LastMean(const FinTwapState &state) {
		return state.last_sum / state.last_count;
	}

	// Appends `right` (all of whose times are >= left.tl) to `left`.
	static void Append(FinTwapState &left, const FinTwapState &right) {
		if (left.tl < right.t0) {
			if (left.distinct >= 2) {
				left.area.Add(LastMean(left) * (right.t0 - left.tl));
			} else {
				left.t1 = right.t0;
			}
			if (right.distinct >= 2) {
				left.area.Add(FirstMean(right) * (right.t1 - right.t0));
			}
			left.area.Add(right.area);
			left.distinct += right.distinct;
		} else {
			// left.tl == right.t0: the boundary timestamp's group spans both.
			auto group_sum = left.last_sum + right.first_sum;
			auto group_count = left.last_count + right.first_count;
			if (left.distinct == 1) {
				left.first_sum = group_sum;
				left.first_count = group_count;
				left.t1 = right.distinct >= 2 ? right.t1 : left.t0;
				left.area = right.area;
			} else if (right.distinct >= 2) {
				left.area.Add(group_sum / group_count * (right.t1 - right.t0));
				left.area.Add(right.area);
			}
			if (right.distinct == 1) {
				left.last_sum = group_sum;
				left.last_count = group_count;
				left.tl = right.tl;
				left.distinct += right.distinct - 1;
				return;
			}
			left.distinct += right.distinct - 1;
		}
		left.tl = right.tl;
		left.last_sum = right.last_sum;
		left.last_count = right.last_count;
	}

	static void Merge(FinTwapState &target, const FinTwapState &source) {
		if (source.invalid) {
			target.invalid = true;
		}
		if (target.invalid || source.distinct == 0) {
			return;
		}
		if (target.distinct == 0) {
			target = source;
			return;
		}
		if (target.tl <= source.t0) {
			Append(target, source);
		} else if (source.tl <= target.t0) {
			auto copy = source;
			Append(copy, target);
			target = copy;
		} else {
			throw InvalidInputException(
			    "fin_twap: rows reached the aggregate out of time order. Use fin_twap(price, ts ORDER BY ts) or a "
			    "window ordered by ts");
		}
	}

	static void Update(FinTwapState &state, double price, double time) {
		if (!std::isfinite(price) || !std::isfinite(time)) {
			state.invalid = true;
			return;
		}
		FinTwapState point;
		point.t0 = point.t1 = point.tl = time;
		point.first_sum = point.last_sum = price;
		point.first_count = point.last_count = 1.0;
		point.area.Clear();
		point.distinct = 1;
		point.invalid = false;
		Merge(state, point);
	}

	static double Time(double value) {
		return value;
	}
	static double Time(date_t value) {
		return Date::IsFinite(value) ? static_cast<double>(value.days) : std::numeric_limits<double>::infinity();
	}
	static double Time(timestamp_t value) {
		return Timestamp::IsFinite(value) ? static_cast<double>(value.value) : std::numeric_limits<double>::infinity();
	}
	static double Time(timestamp_tz_t value) {
		return Time(static_cast<timestamp_t>(value));
	}

	template <class A_TYPE, class B_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const A_TYPE &price, const B_TYPE &time, AggregateBinaryInput &) {
		Update(state.twap, static_cast<double>(price), Time(time));
	}

	template <class A_TYPE, class B_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const A_TYPE &price, const B_TYPE &time, AggregateBinaryInput &,
	                              idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			Update(state.twap, static_cast<double>(price), Time(time));
		}
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		Merge(target.twap, source.twap);
	}

	static bool Value(const FinTwapState &state, double &out) {
		if (state.invalid || state.distinct == 0) {
			return false;
		}
		if (state.distinct == 1) {
			out = FirstMean(state);
		} else {
			auto area = state.area;
			area.Add(FirstMean(state) * (state.t1 - state.t0));
			out = area.Value() / (state.tl - state.t0);
		}
		return std::isfinite(out);
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		double value;
		if (!Value(state.twap, value)) {
			finalize_data.ReturnNull();
			return;
		}
		target = value;
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct FinTwapAggState {
	FinTwapState twap;
	FinWindowAux *window;
};

// Window evaluation: DuckDB segment trees merge non-adjacent pieces, which a
// time-interval state cannot do, so windows are evaluated here. Running frames
// append the rows that entered the frame; other frames are rebuilt. Rows must
// arrive in time order (window ORDER BY ts).
template <class TIME>
static void FinTwapWindow(AggregateInputData &, const WindowPartitionInput &partition, const_data_ptr_t,
                          data_ptr_t l_state, const SubFrames &frames, Vector &result, idx_t rid) {
	auto &state = *reinterpret_cast<FinTwapAggState *>(l_state);
	if (!state.window) {
		state.window = new FinWindowAux();
	}
	auto &aux = *state.window;
	aux.Initialize(partition);
	const auto &filter_mask = partition.filter_mask;
	auto feed = [&](idx_t begin, idx_t end) {
		for (idx_t i = begin; i < end; i++) {
			if (!filter_mask.RowIsValid(i)) {
				continue;
			}
			auto offset = aux.Seek(i);
			auto &prices = aux.page->data[0];
			auto &times = aux.page->data[1];
			if (!FlatVector::Validity(prices).RowIsValid(offset) || !FlatVector::Validity(times).RowIsValid(offset)) {
				continue;
			}
			FinTwapOperation::Update(state.twap, FlatVector::GetData<double>(prices)[offset],
			                         FinTwapOperation::Time(FlatVector::GetData<TIME>(times)[offset]));
		}
	};
	if (frames.size() == 1) {
		const auto begin = frames[0].start;
		const auto end = std::max(frames[0].start, frames[0].end);
		if (aux.has_prev && begin == aux.prev_start && end >= aux.prev_end) {
			feed(aux.prev_end, end);
		} else {
			FinTwapOperation::Reset(state.twap);
			feed(begin, end);
		}
		aux.has_prev = true;
		aux.prev_start = begin;
		aux.prev_end = end;
	} else {
		FinTwapOperation::Reset(state.twap);
		for (const auto &frame : frames) {
			feed(frame.start, frame.end);
		}
		aux.has_prev = false;
	}
	double value;
	if (FinTwapOperation::Value(state.twap, value)) {
		FlatVector::GetData<double>(result)[rid] = value;
	} else {
		FlatVector::SetNull(result, rid, true);
	}
}

template <class TIME>
static AggregateFunction FinTwapAggregate(const LogicalType &time_type) {
	auto function = AggregateFunction::BinaryAggregate<FinTwapAggState, double, TIME, double, FinTwapOperation,
	                                                   AggregateDestructorType::LEGACY>(
	    FinanceLogicalType(LogicalTypeId::DOUBLE), time_type, FinanceLogicalType(LogicalTypeId::DOUBLE));
	function.SetStateDestructorCallback(AggregateFunction::StateDestroy<FinTwapAggState, FinTwapOperation>);
	function.SetWindowCallback(FinTwapWindow<TIME>);
	function.SetOrderDependent(AggregateOrderDependent::ORDER_DEPENDENT);
	function.SetBindCallback(FinNamedArgumentsBind);
	return NamedAggregateFunction("fin_twap", std::move(function));
}

//===--------------------------------------------------------------------===//
// fin_volume_profile
//===--------------------------------------------------------------------===//
// Volume per equal-width price bin over [min price, max price]: bin i covers
// [min + i w, min + (i + 1) w) with w = (max - min) / bins, the last bin closed.
// Volume is kept per distinct price (exact) up to FIN_PROFILE_EXACT prices;
// beyond that, prices are pre-aggregated on a grid of at most FIN_PROFILE_CELLS
// cells of width 2^e (the smallest e that spans the price range), and each cell
// is assigned to the bin containing its midpoint. Grid cells depend only on the
// price range, never on row order, so memory stays bounded (about 32 KB per
// state) and results are deterministic.
static constexpr idx_t FIN_PROFILE_EXACT = 1024;
static constexpr idx_t FIN_PROFILE_CELLS = 4096;
static constexpr double FIN_PROFILE_MAX_BINS = 100000.0;

struct FinProfileData {
	// Exact mode: (price, volume) pairs; the prefix [0, unique) is sorted by
	// price with one entry per price, later entries are pending.
	vector<std::pair<double, double>> exact;
	idx_t unique = 0;
	bool grid = false;
	int exponent = 0;
	double base = 0.0;
	vector<double> cells;
	vector<double> bins;

	void Clear() {
		exact.clear();
		unique = 0;
		grid = false;
		cells.clear();
	}
};

struct FinProfileState {
	FinProfileData *data;
	double min;
	double max;
	double bins;
	idx_t count;
	bool invalid;
	FinWindowAux *window;
};

struct FinVolumeProfileOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.data = nullptr;
		state.window = nullptr;
		Reset(state);
	}

	static void Reset(FinProfileState &state) {
		if (state.data) {
			state.data->Clear();
		}
		state.min = state.max = 0.0;
		state.bins = 0.0;
		state.count = 0;
		state.invalid = false;
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.data;
		state.data = nullptr;
		delete state.window;
		state.window = nullptr;
	}

	static double Cell(double price, int exponent) {
		return std::floor(std::ldexp(price, -exponent));
	}

	// Smallest exponent whose cells span [min, max] (min < max).
	static int Exponent(double min, double max) {
		int exponent;
		std::frexp((max - min) / static_cast<double>(FIN_PROFILE_CELLS), &exponent);
		exponent -= 3;
		while (Cell(max, exponent) - Cell(min, exponent) >= static_cast<double>(FIN_PROFILE_CELLS)) {
			exponent++;
		}
		return exponent;
	}

	// Sorts the exact entries and merges equal prices (sums in sorted order).
	static void Compact(FinProfileData &data) {
		auto &entries = data.exact;
		if (data.unique == entries.size()) {
			return;
		}
		std::sort(entries.begin(), entries.end());
		idx_t out = 0;
		for (idx_t i = 0; i < entries.size(); i++) {
			if (out > 0 && entries[out - 1].first == entries[i].first) {
				entries[out - 1].second += entries[i].second;
			} else {
				entries[out++] = entries[i];
			}
		}
		entries.resize(out);
		data.unique = out;
	}

	static void AddCell(FinProfileData &data, double cell, double volume) {
		data.cells[static_cast<idx_t>(cell - data.base)] += volume;
	}

	// Moves the data onto the grid for [min, max].
	static void Regrid(FinProfileData &data, double min, double max) {
		auto exponent = Exponent(min, max);
		auto base = Cell(min, exponent);
		vector<double> cells(FIN_PROFILE_CELLS, 0.0);
		if (data.grid) {
			for (idx_t j = 0; j < data.cells.size(); j++) {
				if (data.cells[j] != 0.0) {
					auto cell = std::floor(std::ldexp(data.base + static_cast<double>(j), data.exponent - exponent));
					cells[static_cast<idx_t>(cell - base)] += data.cells[j];
				}
			}
		} else {
			Compact(data);
			for (auto &entry : data.exact) {
				cells[static_cast<idx_t>(Cell(entry.first, exponent) - base)] += entry.second;
			}
			data.exact.clear();
			data.unique = 0;
		}
		data.grid = true;
		data.exponent = exponent;
		data.base = base;
		data.cells = std::move(cells);
	}

	static void CheckExact(FinProfileState &state) {
		auto &data = *state.data;
		if (data.exact.size() >= 2 * FIN_PROFILE_EXACT) {
			Compact(data);
			if (data.exact.size() > FIN_PROFILE_EXACT) {
				Regrid(data, state.min, state.max);
			}
		}
	}

	static void Insert(FinProfileState &state, double price, double volume) {
		if (!state.data) {
			state.data = new FinProfileData();
		}
		auto &data = *state.data;
		if (data.grid) {
			if (Cell(state.min, data.exponent) < data.base ||
			    Cell(state.max, data.exponent) - data.base >= static_cast<double>(FIN_PROFILE_CELLS)) {
				Regrid(data, state.min, state.max);
			}
			AddCell(data, Cell(price, data.exponent), volume);
			return;
		}
		data.exact.emplace_back(price, volume);
		CheckExact(state);
	}

	static void Update(FinProfileState &state, double price, double volume, double bins) {
		if (state.invalid) {
			return;
		}
		if (!std::isfinite(price) || !std::isfinite(volume) || volume < 0.0) {
			state.invalid = true;
			return;
		}
		price += 0.0; // -0.0 and 0.0 are the same price
		state.bins = bins;
		if (state.count == 0) {
			state.min = state.max = price;
		} else {
			state.min = std::min(state.min, price);
			state.max = std::max(state.max, price);
		}
		state.count++;
		Insert(state, price, volume);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (source.invalid) {
			target.invalid = true;
		}
		if (target.invalid || source.count == 0) {
			return;
		}
		target.bins = source.bins;
		if (target.count == 0) {
			target.min = source.min;
			target.max = source.max;
		} else {
			target.min = std::min(target.min, source.min);
			target.max = std::max(target.max, source.max);
		}
		target.count += source.count;
		if (!target.data) {
			target.data = new FinProfileData();
		}
		auto &data = *target.data;
		auto &other = *source.data;
		if (!data.grid && !other.grid) {
			data.exact.insert(data.exact.end(), other.exact.begin(), other.exact.end());
			CheckExact(target);
			return;
		}
		if (!data.grid || Cell(target.min, data.exponent) < data.base ||
		    Cell(target.max, data.exponent) - data.base >= static_cast<double>(FIN_PROFILE_CELLS)) {
			Regrid(data, target.min, target.max);
		}
		if (other.grid) {
			for (idx_t j = 0; j < other.cells.size(); j++) {
				if (other.cells[j] != 0.0) {
					auto cell =
					    std::floor(std::ldexp(other.base + static_cast<double>(j), other.exponent - data.exponent));
					AddCell(data, cell, other.cells[j]);
				}
			}
		} else {
			auto entries = other.exact;
			std::sort(entries.begin(), entries.end());
			for (auto &entry : entries) {
				AddCell(data, Cell(entry.first, data.exponent), entry.second);
			}
		}
	}

	static idx_t Bin(double price, double min, double width, idx_t bins) {
		auto position = std::floor((price - min) / width);
		if (!(position >= 0.0)) {
			return 0;
		}
		return position >= static_cast<double>(bins) ? bins - 1 : static_cast<idx_t>(position);
	}

	// Appends the profile of `state` as list row `row` of `result`.
	static void Write(FinProfileState &state, Vector &result, idx_t row) {
		auto entries = FlatVector::GetData<list_entry_t>(result);
		auto offset = ListVector::GetListSize(result);
		if (state.invalid || state.count == 0) {
			FlatVector::SetNull(result, row, true);
			entries[row] = list_entry_t(offset, 0);
			return;
		}
		auto &data = *state.data;
		auto bins = state.min == state.max ? idx_t(1) : static_cast<idx_t>(state.bins);
		auto width = (state.max - state.min) / static_cast<double>(bins);
		auto &volume = data.bins;
		volume.assign(bins, 0.0);
		if (data.grid) {
			for (idx_t j = 0; j < data.cells.size(); j++) {
				if (data.cells[j] == 0.0) {
					continue;
				}
				auto midpoint = std::ldexp(data.base + static_cast<double>(j) + 0.5, data.exponent);
				midpoint = std::min(std::max(midpoint, state.min), state.max);
				volume[bins == 1 ? 0 : Bin(midpoint, state.min, width, bins)] += data.cells[j];
			}
		} else {
			Compact(data);
			for (auto &entry : data.exact) {
				volume[bins == 1 ? 0 : Bin(entry.first, state.min, width, bins)] += entry.second;
			}
		}
		ListVector::Reserve(result, offset + bins);
		auto &child = ListVector::GetEntry(result);
		auto &fields = StructVector::GetEntries(child);
		auto lows = FlatVector::GetData<double>(*fields[0]);
		auto highs = FlatVector::GetData<double>(*fields[1]);
		auto volumes = FlatVector::GetData<double>(*fields[2]);
		for (idx_t i = 0; i < bins; i++) {
			lows[offset + i] = state.min + static_cast<double>(i) * width;
			highs[offset + i] = i + 1 == bins ? state.max : state.min + static_cast<double>(i + 1) * width;
			volumes[offset + i] = volume[i];
		}
		entries[row] = list_entry_t(offset, bins);
		ListVector::SetListSize(result, offset + bins);
	}
};

static double FinProfileBins(double value) {
	if (!std::isfinite(value) || std::trunc(value) != value || value < 1.0 || value > FIN_PROFILE_MAX_BINS) {
		throw InvalidInputException("fin_volume_profile: bins must be an integer between 1 and 100000");
	}
	return value;
}

template <class STATE_ACCESS>
static void FinVolumeProfileUpdateRows(Vector inputs[], idx_t input_count, idx_t count, STATE_ACCESS &&state_for_row) {
	UnifiedVectorFormat formats[3];
	const double *data[3];
	for (idx_t c = 0; c < input_count; c++) {
		FinanceToUnifiedFormat(inputs[c], count, formats[c]);
		data[c] = UnifiedVectorFormat::GetData<double>(formats[c]);
	}
	double previous_bins = -1.0;
	for (idx_t i = 0; i < count; i++) {
		auto price_index = formats[0].sel->get_index(i);
		auto volume_index = formats[1].sel->get_index(i);
		if (!formats[0].validity.RowIsValid(price_index) || !formats[1].validity.RowIsValid(volume_index)) {
			continue;
		}
		double bins = 10.0;
		if (input_count == 3) {
			auto bins_index = formats[2].sel->get_index(i);
			if (!formats[2].validity.RowIsValid(bins_index)) {
				throw InvalidInputException("fin_volume_profile: bins must not be NULL");
			}
			bins = data[2][bins_index];
			if (bins != previous_bins) {
				FinProfileBins(bins);
				previous_bins = bins;
			}
		}
		FinVolumeProfileOperation::Update(state_for_row(i), data[0][price_index], data[1][volume_index], bins);
	}
}

static void FinVolumeProfileScatter(Vector inputs[], AggregateInputData &, idx_t input_count, Vector &states,
                                    idx_t count) {
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(states, count, sdata);
	auto state_values = UnifiedVectorFormat::GetData<FinProfileState *>(sdata);
	FinVolumeProfileUpdateRows(inputs, input_count, count,
	                           [&](idx_t i) -> FinProfileState & { return *state_values[sdata.sel->get_index(i)]; });
}

static void FinVolumeProfileSimpleUpdate(Vector inputs[], AggregateInputData &, idx_t input_count,
                                         data_ptr_t state_ptr, idx_t count) {
	auto &state = *reinterpret_cast<FinProfileState *>(state_ptr);
	FinVolumeProfileUpdateRows(inputs, input_count, count, [&](idx_t) -> FinProfileState & { return state; });
}

static void FinVolumeProfileFinalize(Vector &states, AggregateInputData &, Vector &result, idx_t count,
                                     idx_t offset) {
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(states, count, sdata);
	auto state_values = UnifiedVectorFormat::GetData<FinProfileState *>(sdata);
	for (idx_t i = 0; i < count; i++) {
		FinVolumeProfileOperation::Write(*state_values[sdata.sel->get_index(i)], result, i + offset);
	}
}

// Window evaluation rebuilds the frame's profile in a reused local state, so
// small frames cost a sort of their rows and no allocation per row.
static void FinVolumeProfileWindow(AggregateInputData &, const WindowPartitionInput &partition, const_data_ptr_t,
                                   data_ptr_t l_state, const SubFrames &frames, Vector &result, idx_t rid) {
	auto &state = *reinterpret_cast<FinProfileState *>(l_state);
	if (!state.window) {
		state.window = new FinWindowAux();
	}
	auto &aux = *state.window;
	aux.Initialize(partition);
	FinVolumeProfileOperation::Reset(state);
	const auto &filter_mask = partition.filter_mask;
	const bool has_bins = partition.column_ids.size() >= 3;
	for (const auto &frame : frames) {
		for (idx_t i = frame.start; i < frame.end; i++) {
			if (!filter_mask.RowIsValid(i)) {
				continue;
			}
			auto offset = aux.Seek(i);
			auto &prices = aux.page->data[0];
			auto &volumes = aux.page->data[1];
			if (!FlatVector::Validity(prices).RowIsValid(offset) || !FlatVector::Validity(volumes).RowIsValid(offset)) {
				continue;
			}
			double bins = 10.0;
			if (has_bins) {
				auto &bin_vector = aux.page->data[2];
				if (!FlatVector::Validity(bin_vector).RowIsValid(offset)) {
					throw InvalidInputException("fin_volume_profile: bins must not be NULL");
				}
				bins = FinProfileBins(FlatVector::GetData<double>(bin_vector)[offset]);
			}
			FinVolumeProfileOperation::Update(state, FlatVector::GetData<double>(prices)[offset],
			                                  FlatVector::GetData<double>(volumes)[offset], bins);
		}
	}
	FinVolumeProfileOperation::Write(state, result, rid);
}

static unique_ptr<FunctionData> FinVolumeProfileBind(ClientContext &context, AggregateFunction &function,
                                                     vector<unique_ptr<Expression>> &arguments) {
	FinRejectNamedArguments(function, arguments);
	if (arguments.size() == 3) {
		auto &bins = *arguments[2];
		if (!bins.IsFoldable()) {
			throw InvalidInputException("fin_volume_profile: bins must be a constant");
		}
		auto value = ExpressionExecutor::EvaluateScalar(context, bins, true);
		if (value.IsNull()) {
			throw InvalidInputException("fin_volume_profile: bins must not be NULL");
		}
		FinProfileBins(DoubleValue::Get(value.DefaultCastAs(LogicalType::DOUBLE)));
	}
	return nullptr;
}

static LogicalType FinVolumeProfileType() {
	child_list_t<LogicalType> children;
	children.emplace_back("price_low", LogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("price_high", LogicalType(LogicalTypeId::DOUBLE));
	children.emplace_back("volume", LogicalType(LogicalTypeId::DOUBLE));
	return LogicalType::LIST(LogicalType::STRUCT(std::move(children)));
}


static void RegisterMarketVolumeAggregates(ExtensionLoader &loader) {
	AggregateFunctionSet vwap(FinanceFunctionName("fin_vwap"));
	vwap.AddFunction(FinDoubleRowsAggregate<FinSumPairState, FinVwapOperation, 2>("fin_vwap"));
	loader.RegisterFunction(std::move(vwap));

	AggregateFunctionSet ad_line(FinanceFunctionName("fin_ad_line"));
	ad_line.AddFunction(FinDoubleRowsAggregate<FinSumPairState, FinAdLineOperation, 4>("fin_ad_line"));
	loader.RegisterFunction(std::move(ad_line));

	AggregateFunctionSet amihud(FinanceFunctionName("fin_amihud_illiquidity"));
	amihud.AddFunction(FinDoubleRowsAggregate<FinSumPairState, FinAmihudOperation, 2>("fin_amihud_illiquidity"));
	loader.RegisterFunction(std::move(amihud));

	AggregateFunctionSet kyle(FinanceFunctionName("fin_kyle_lambda"));
	kyle.AddFunction(FinDoubleRowsAggregate<FinKyleLambdaState, FinKyleLambdaOperation, 2>("fin_kyle_lambda"));
	loader.RegisterFunction(std::move(kyle));

	AggregateFunctionSet twap(FinanceFunctionName("fin_twap"));
	twap.AddFunction(FinTwapAggregate<timestamp_t>(FinanceLogicalType(LogicalTypeId::TIMESTAMP)));
	twap.AddFunction(FinTwapAggregate<timestamp_tz_t>(FinanceLogicalType(LogicalTypeId::TIMESTAMP_TZ)));
	twap.AddFunction(FinTwapAggregate<date_t>(FinanceLogicalType(LogicalTypeId::DATE)));
	twap.AddFunction(FinTwapAggregate<double>(FinanceLogicalType(LogicalTypeId::DOUBLE)));
	loader.RegisterFunction(std::move(twap));

	AggregateFunctionSet profile(FinanceFunctionName("fin_volume_profile"));
	for (idx_t arity = 2; arity <= 3; arity++) {
		vector<LogicalType> arguments(arity, FinanceLogicalType(LogicalTypeId::DOUBLE));
		AggregateFunction function(
		    arguments, FinVolumeProfileType(), AggregateFunction::StateSize<FinProfileState>,
		    AggregateFunction::StateInitialize<FinProfileState, FinVolumeProfileOperation,
		                                       AggregateDestructorType::LEGACY>,
		    FinVolumeProfileScatter, AggregateFunction::StateCombine<FinProfileState, FinVolumeProfileOperation>,
		    FinVolumeProfileFinalize, FunctionNullHandling::DEFAULT_NULL_HANDLING, FinVolumeProfileSimpleUpdate);
		function.SetStateDestructorCallback(
		    AggregateFunction::StateDestroy<FinProfileState, FinVolumeProfileOperation>);
		function.SetBindCallback(FinVolumeProfileBind);
		function.SetWindowCallback(FinVolumeProfileWindow);
		function.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
		function.name = FinanceFunctionName("fin_volume_profile");
		profile.AddFunction(std::move(function));
	}
	loader.RegisterFunction(std::move(profile));
}
