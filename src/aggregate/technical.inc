//===--------------------------------------------------------------------===//
// Rolling technical indicators (TA-Lib conventions)
//===--------------------------------------------------------------------===//
// Every indicator here is an order-dependent aggregate over a price series. The
// aggregate returns the indicator value at the LAST row of its ordered input:
// grouped calls need `fin_x(close ORDER BY ts)`, and window calls such as
// `fin_x(close) OVER (PARTITION BY s ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING
// AND CURRENT ROW)` reproduce the TA-Lib output series row by row. Rows before
// the TA-Lib lookback (warm-up) return NULL.
//
// Indicator parameters are bind-time constants. They are validated once, stored
// in the bind data and removed from the argument list, so the update loop only
// reads the price columns. Each indicator is a streaming kernel whose state is
// bounded by its periods; ring buffers live in one heap block per state.
//
// Kernels are either bounded (the value depends only on the last `Memory` rows,
// e.g. SMA, Stochastic, CCI) or recursive (the value depends on the whole series,
// e.g. EMA, RSI, KAMA, SAR). Window frames that keep their start are evaluated
// incrementally; other frames are rebuilt, and bounded kernels then replay only
// the last `Memory` rows of the frame.
//
// A NULL in any input column skips the row. A non-finite input makes bounded
// indicators NULL while that row is inside their lookback and recursive
// indicators NULL for the rest of the series.

constexpr idx_t TECH_MAX_INPUTS = 3;
constexpr idx_t TECH_MAX_PARAMS = 8;
constexpr idx_t TECH_MAX_FIELDS = 5;
constexpr double TECH_MAX_PERIOD = 100000.0;

enum class TechParamKind : uint8_t { PERIOD, REAL, MA_TYPE };

struct TechParamSpec {
	const char *name;
	double default_value;
	TechParamKind kind;
	double minimum;
	double maximum;
	bool exclusive_minimum;
};

static constexpr double TECH_MA_SMA = 0.0;
static constexpr double TECH_MA_EMA = 1.0;

struct TechBindData : public FunctionData {
	double values[TECH_MAX_PARAMS] = {0.0};

	unique_ptr<FunctionData> Copy() const override {
		auto result = make_uniq<TechBindData>();
		memcpy(result->values, values, sizeof(values));
		return std::move(result);
	}

	bool Equals(const FunctionData &other_p) const override {
		auto &other = other_p.Cast<TechBindData>();
		return memcmp(values, other.values, sizeof(values)) == 0;
	}
};

static idx_t TechPeriod(double value) {
	return static_cast<idx_t>(value);
}

//===--------------------------------------------------------------------===//
// Building blocks
//===--------------------------------------------------------------------===//
// A fixed-capacity FIFO stored at `offset` in the state's heap block. Offsets
// (not pointers) keep kernels trivially copyable.
struct TechRing {
	idx_t offset;
	idx_t capacity;
	idx_t head;
	idx_t size;

	void Init(idx_t &cursor, idx_t capacity_p) {
		offset = cursor;
		capacity = capacity_p;
		head = 0;
		size = 0;
		cursor += capacity_p;
	}

	void Clear() {
		head = 0;
		size = 0;
	}

	bool Full() const {
		return size == capacity;
	}

	idx_t Slot(idx_t i) const {
		auto slot = head + i;
		return offset + (slot >= capacity ? slot - capacity : slot);
	}

	// Appends a value; when full, evicts and returns the oldest value.
	double Push(double *buffer, double value) {
		if (size < capacity) {
			buffer[Slot(size)] = value;
			size++;
			return 0.0;
		}
		auto evicted = buffer[offset + head];
		buffer[offset + head] = value;
		head = head + 1 == capacity ? 0 : head + 1;
		return evicted;
	}

	// i = 0 is the oldest retained value.
	double At(const double *buffer, idx_t i) const {
		return buffer[Slot(i)];
	}

	double Newest(const double *buffer) const {
		return At(buffer, size - 1);
	}

	double Sum(const double *buffer) const {
		double sum = 0.0;
		for (idx_t i = 0; i < size; i++) {
			sum += At(buffer, i);
		}
		return sum;
	}

	double Max(const double *buffer) const {
		auto result = At(buffer, 0);
		for (idx_t i = 1; i < size; i++) {
			result = std::max(result, At(buffer, i));
		}
		return result;
	}

	double Min(const double *buffer) const {
		auto result = At(buffer, 0);
		for (idx_t i = 1; i < size; i++) {
			result = std::min(result, At(buffer, i));
		}
		return result;
	}
};

// Simple and linearly weighted (weights 1..n, newest heaviest) moving
// averages. Sums are recomputed from the ring in a fixed order, so a value
// depends only on the rows in its lookback, not on how the state got there
// (window frames rebuilt at different rows give bit-identical results).
struct TechSmaStage {
	TechRing ring;

	void Init(idx_t &cursor, idx_t period) {
		ring.Init(cursor, period);
	}

	void Reset() {
		ring.Clear();
	}

	bool Push(double *buffer, double value) {
		ring.Push(buffer, value);
		return ring.Full();
	}

	bool Ready() const {
		return ring.Full();
	}

	double Mean(const double *buffer) const {
		return ring.Sum(buffer) / static_cast<double>(ring.capacity);
	}
};

struct TechWmaStage {
	TechRing ring;
	double denominator;

	void Init(idx_t &cursor, idx_t period) {
		ring.Init(cursor, period);
		denominator = static_cast<double>(period) * static_cast<double>(period + 1) / 2.0;
	}

	void Reset() {
		ring.Clear();
	}

	bool Push(double *buffer, double value) {
		ring.Push(buffer, value);
		return ring.Full();
	}

	bool Ready() const {
		return ring.Full();
	}

	double Mean(const double *buffer) const {
		double weighted = 0.0;
		for (idx_t i = 0; i < ring.size; i++) {
			weighted += static_cast<double>(i + 1) * ring.At(buffer, i);
		}
		return weighted / denominator;
	}
};

// TA-Lib EMA stage: seeded with the SMA of its first `period` inputs, then
// value = k * x + (1 - k) * value with k = 2 / (period + 1).
struct TechEmaStage {
	double k;
	double one_minus_k;
	double period;
	idx_t needed;
	idx_t seen;
	double value;

	void Init(idx_t period_p) {
		period = static_cast<double>(period_p);
		needed = period_p;
		k = 2.0 / (period + 1.0);
		one_minus_k = 1.0 - k;
	}

	void Reset() {
		seen = 0;
		value = 0.0;
	}

	bool Ready() const {
		return seen >= needed;
	}

	bool Push(double x, double &out) {
		if (seen < needed) {
			// Summing x / n keeps the seed finite for inputs near the DOUBLE limit.
			value += x / period;
			seen++;
			if (seen < needed) {
				return false;
			}
		} else {
			value = k * x + one_minus_k * value;
		}
		out = value;
		return true;
	}
};

// Wilder smoothing of up/down moves shared by RSI and CMO (TA-Lib seeding: the
// first average is the mean of the first `period` changes).
struct TechWilderStage {
	double period;
	idx_t needed;
	idx_t changes;
	bool has_previous;
	double previous;
	double gain;
	double loss;

	void Init(idx_t period_p) {
		period = static_cast<double>(period_p);
		needed = period_p;
	}

	void Reset() {
		changes = 0;
		has_previous = false;
		previous = gain = loss = 0.0;
	}

	bool Push(double x) {
		if (!has_previous) {
			has_previous = true;
			previous = x;
			return false;
		}
		auto diff = x - previous;
		previous = x;
		auto up = diff > 0.0 ? diff : 0.0;
		auto down = diff < 0.0 ? -diff : 0.0;
		if (changes < needed) {
			gain += up;
			loss += down;
			changes++;
			if (changes < needed) {
				return false;
			}
			gain /= period;
			loss /= period;
			return true;
		}
		gain = (gain * (period - 1.0) + up) / period;
		loss = (loss * (period - 1.0) + down) / period;
		return true;
	}

	double Rsi() const {
		auto total = gain + loss;
		return total == 0.0 ? 0.0 : 100.0 * (gain / total);
	}

	double Cmo() const {
		auto total = gain + loss;
		return total == 0.0 ? 0.0 : 100.0 * ((gain - loss) / total);
	}
};

// A fast/slow pair of moving averages that both produce their first value at
// row slow - 1. APO/PPO use independent SMA or EMA stages. MACD uses TA-Lib's
// aligned EMAs: the fast EMA is seeded with the SMA of rows [slow - fast,
// slow - 1] instead of rows [0, fast - 1].
struct TechMaPair {
	idx_t fast;
	idx_t slow;
	bool ema;
	bool aligned;
	TechSmaStage fast_sma;
	TechSmaStage slow_sma;
	TechEmaStage fast_ema;
	TechEmaStage slow_ema;
	idx_t seen;
	double fast_value;
	double slow_value;
	double fast_k;
	double slow_k;

	void Init(idx_t &cursor, double fast_p, double slow_p, bool ema_p, bool aligned_p) {
		fast = TechPeriod(std::min(fast_p, slow_p));
		slow = TechPeriod(std::max(fast_p, slow_p));
		ema = ema_p;
		aligned = aligned_p;
		if (!ema) {
			fast_sma.Init(cursor, fast);
			slow_sma.Init(cursor, slow);
		}
		fast_ema.Init(fast);
		slow_ema.Init(slow);
		fast_k = 2.0 / (static_cast<double>(fast) + 1.0);
		slow_k = 2.0 / (static_cast<double>(slow) + 1.0);
	}

	void Reset() {
		if (!ema) {
			fast_sma.Reset();
			slow_sma.Reset();
		}
		fast_ema.Reset();
		slow_ema.Reset();
		seen = 0;
		fast_value = slow_value = 0.0;
	}

	bool Push(double *buffer, double x) {
		if (!ema) {
			fast_sma.Push(buffer, x);
			return slow_sma.Push(buffer, x);
		}
		if (!aligned) {
			fast_ema.Push(x, fast_value);
			return slow_ema.Push(x, slow_value);
		}
		if (seen < slow) {
			slow_value += x / static_cast<double>(slow);
			if (seen >= slow - fast) {
				fast_value += x / static_cast<double>(fast);
			}
			seen++;
			return seen == slow;
		}
		fast_value = fast_k * x + (1.0 - fast_k) * fast_value;
		slow_value = slow_k * x + (1.0 - slow_k) * slow_value;
		return true;
	}

	void Values(const double *buffer, double &fast_out, double &slow_out) const {
		if (!ema) {
			fast_out = fast_sma.Mean(buffer);
			slow_out = slow_sma.Mean(buffer);
		} else {
			fast_out = fast_value;
			slow_out = slow_value;
		}
	}
};

//===--------------------------------------------------------------------===//
// Indicator kernels
//===--------------------------------------------------------------------===//
// Each operation declares NAME, INPUTS, its parameters, its STRUCT fields (none
// for a DOUBLE result), Memory (rows the value depends on; 0 = whole series)
// and a Kernel with Init / Reset / Push / Value.

#define TECH_NO_FIELDS                                                                                                 \
	static constexpr idx_t FIELD_COUNT = 0;                                                                            \
	static const char *const *Fields() {                                                                               \
		return nullptr;                                                                                                \
	}

#define TECH_PERIOD_PARAM(NAME, DEFAULT) {NAME, DEFAULT, TechParamKind::PERIOD, 1.0, TECH_MAX_PERIOD, false}
#define TECH_PERIOD2_PARAM(NAME, DEFAULT) {NAME, DEFAULT, TechParamKind::PERIOD, 2.0, TECH_MAX_PERIOD, false}

template <class STAGE>
struct TechSingleMaOp {
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]);
	}
	static void Validate(const char *, const double *) {
	}
	struct Kernel {
		STAGE stage;
		void Init(const double *p, idx_t &cursor) {
			stage.Init(cursor, TechPeriod(p[0]));
		}
		void Reset() {
			stage.Reset();
		}
		void Push(double *buffer, const double *in) {
			stage.Push(buffer, in[0]);
		}
		bool Value(const double *buffer, double *out) const {
			if (!stage.Ready()) {
				return false;
			}
			out[0] = stage.Mean(buffer);
			return true;
		}
	};
};

struct TechSmaOp : public TechSingleMaOp<TechSmaStage> {
	static constexpr const char *NAME = "fin_sma";
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 20)};
		return specs;
	}
};

struct TechWmaOp : public TechSingleMaOp<TechWmaStage> {
	static constexpr const char *NAME = "fin_wma";
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 20)};
		return specs;
	}
};

// TRIMA: SMA of an SMA. Odd n: both (n + 1) / 2; even n: n / 2 then n / 2 + 1,
// which gives the triangular weights 1, 2, ..., n/2, n/2, ..., 2, 1.
struct TechTrimaOp {
	static constexpr const char *NAME = "fin_trima";
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 20)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]);
	}
	struct Kernel {
		TechSmaStage first;
		TechSmaStage second;
		void Init(const double *p, idx_t &cursor) {
			auto n = TechPeriod(p[0]);
			auto a = n % 2 == 1 ? (n + 1) / 2 : n / 2;
			auto b = n % 2 == 1 ? (n + 1) / 2 : n / 2 + 1;
			first.Init(cursor, a);
			second.Init(cursor, b);
		}
		void Reset() {
			first.Reset();
			second.Reset();
		}
		void Push(double *buffer, const double *in) {
			if (first.Push(buffer, in[0])) {
				second.Push(buffer, first.Mean(buffer));
			}
		}
		bool Value(const double *buffer, double *out) const {
			if (!second.Ready()) {
				return false;
			}
			out[0] = second.Mean(buffer);
			return true;
		}
	};
};

// EMA chains: EMA (1 stage), DEMA (2), TEMA (3) and T3 (6 stages), each stage
// seeded with the SMA of its first `period` inputs, as TA-Lib does.
template <idx_t STAGES>
struct TechEmaChain {
	TechEmaStage stages[STAGES];
	double values[STAGES];
	bool ready;

	void Init(idx_t period) {
		for (idx_t i = 0; i < STAGES; i++) {
			stages[i].Init(period);
		}
	}

	void Reset() {
		for (idx_t i = 0; i < STAGES; i++) {
			stages[i].Reset();
			values[i] = 0.0;
		}
		ready = false;
	}

	void Push(double x) {
		auto input = x;
		for (idx_t i = 0; i < STAGES; i++) {
			if (!stages[i].Push(input, values[i])) {
				return;
			}
			input = values[i];
		}
		ready = true;
	}
};

template <idx_t STAGES>
struct TechEmaFamilyOp {
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 20)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechEmaChain<STAGES> chain;
		void Init(const double *p, idx_t &) {
			chain.Init(TechPeriod(p[0]));
		}
		void Reset() {
			chain.Reset();
		}
		void Push(double *, const double *in) {
			chain.Push(in[0]);
		}
		bool Value(const double *, double *out) const {
			auto &v = chain.values;
			if (STAGES == 1) {
				out[0] = v[0];
			} else if (STAGES == 2) {
				out[0] = 2.0 * v[0] - v[STAGES - 1];
			} else {
				out[0] = 3.0 * v[0] - 3.0 * v[1] + v[STAGES - 1];
			}
			return chain.ready;
		}
	};
};

struct TechEmaOp : public TechEmaFamilyOp<1> {
	static constexpr const char *NAME = "fin_ema";
};

struct TechDemaOp : public TechEmaFamilyOp<2> {
	static constexpr const char *NAME = "fin_dema";
};

struct TechTemaOp : public TechEmaFamilyOp<3> {
	static constexpr const char *NAME = "fin_tema";
};

// T3 (Tillson): six chained EMAs combined with volume-factor coefficients.
struct TechT3Op {
	static constexpr const char *NAME = "fin_t3";
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 2;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 20),
		                                      {"vfactor", 0.7, TechParamKind::REAL, 0.0, 1.0, false}};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechEmaChain<6> chain;
		double c1, c2, c3, c4;
		void Init(const double *p, idx_t &) {
			chain.Init(TechPeriod(p[0]));
			auto v = p[1];
			auto v2 = v * v;
			c1 = -v2 * v;
			c2 = 3.0 * (v2 - c1);
			c3 = -6.0 * v2 - 3.0 * (v - c1);
			c4 = 1.0 + 3.0 * v - c1 + 3.0 * v2;
		}
		void Reset() {
			chain.Reset();
		}
		void Push(double *, const double *in) {
			chain.Push(in[0]);
		}
		bool Value(const double *, double *out) const {
			auto &e = chain.values;
			out[0] = c1 * e[5] + c2 * e[4] + c3 * e[3] + c4 * e[2];
			return chain.ready;
		}
	};
};

// KAMA (Kaufman): efficiency ratio over `period` changes, smoothing constant
// (ER * (2/(fast+1) - 2/(slow+1)) + 2/(slow+1))^2, seeded with the price at row
// period - 1; first value at row `period` (TA-Lib).
struct TechKamaOp {
	static constexpr const char *NAME = "fin_kama";
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 3;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 10), TECH_PERIOD_PARAM("fast", 2),
		                                      TECH_PERIOD_PARAM("slow", 30)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechRing prices;
		idx_t period;
		double const_max;
		double const_diff;
		double path;
		idx_t updates;
		double kama;
		bool ready;
		void Init(const double *p, idx_t &cursor) {
			period = TechPeriod(p[0]);
			prices.Init(cursor, period + 1);
			const_max = 2.0 / (p[2] + 1.0);
			const_diff = 2.0 / (p[1] + 1.0) - const_max;
		}
		void Reset() {
			prices.Clear();
			path = 0.0;
			updates = 0;
			kama = 0.0;
			ready = false;
		}
		void Push(double *buffer, const double *in) {
			auto x = in[0];
			if (prices.Full()) {
				// Drop the oldest change, then add the newest one.
				path -= std::abs(prices.At(buffer, 1) - prices.At(buffer, 0));
			}
			auto had_previous = prices.size > 0;
			auto previous = had_previous ? prices.Newest(buffer) : 0.0;
			prices.Push(buffer, x);
			if (had_previous) {
				path += std::abs(x - previous);
			}
			if (!prices.Full()) {
				return;
			}
			if (++updates >= period) {
				updates = 0;
				path = 0.0;
				for (idx_t i = 1; i < prices.size; i++) {
					path += std::abs(prices.At(buffer, i) - prices.At(buffer, i - 1));
				}
			}
			if (!ready) {
				kama = previous;
			}
			auto change = x - prices.At(buffer, 0);
			auto efficiency = (path <= change || path == 0.0) ? 1.0 : std::abs(change / path);
			auto smoothing = efficiency * const_diff + const_max;
			smoothing *= smoothing;
			kama = (x - kama) * smoothing + kama;
			ready = true;
		}
		bool Value(const double *, double *out) const {
			out[0] = kama;
			return ready;
		}
	};
};

// Hull moving average: WMA(2 * WMA(x, n/2) - WMA(x, n), floor(sqrt(n))).
struct TechHmaOp {
	static constexpr const char *NAME = "fin_hma";
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD2_PARAM("period", 20)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t SqrtPeriod(idx_t n) {
		auto root = static_cast<idx_t>(std::sqrt(static_cast<double>(n)));
		while ((root + 1) * (root + 1) <= n) {
			root++;
		}
		while (root * root > n) {
			root--;
		}
		return root;
	}
	static idx_t Memory(const double *p) {
		auto n = TechPeriod(p[0]);
		return n + SqrtPeriod(n) - 1;
	}
	struct Kernel {
		TechWmaStage half;
		TechWmaStage full;
		TechWmaStage hull;
		void Init(const double *p, idx_t &cursor) {
			auto n = TechPeriod(p[0]);
			half.Init(cursor, n / 2);
			full.Init(cursor, n);
			hull.Init(cursor, SqrtPeriod(n));
		}
		void Reset() {
			half.Reset();
			full.Reset();
			hull.Reset();
		}
		void Push(double *buffer, const double *in) {
			half.Push(buffer, in[0]);
			if (full.Push(buffer, in[0])) {
				hull.Push(buffer, 2.0 * half.Mean(buffer) - full.Mean(buffer));
			}
		}
		bool Value(const double *buffer, double *out) const {
			if (!hull.Ready()) {
				return false;
			}
			out[0] = hull.Mean(buffer);
			return true;
		}
	};
};

// Least-squares line over the last n values, x = 0 (oldest) .. n - 1 (newest).
enum class TechRegressionKind : uint8_t { ENDPOINT, SLOPE, INTERCEPT, FORECAST };

template <TechRegressionKind KIND>
struct TechRegressionOp {
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD2_PARAM("period", 14)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]);
	}
	struct Kernel {
		TechRing ring;
		void Init(const double *p, idx_t &cursor) {
			ring.Init(cursor, TechPeriod(p[0]));
		}
		void Reset() {
			ring.Clear();
		}
		void Push(double *buffer, const double *in) {
			ring.Push(buffer, in[0]);
		}
		bool Value(const double *buffer, double *out) const {
			if (!ring.Full()) {
				return false;
			}
			auto n = static_cast<double>(ring.size);
			auto mean = ring.Sum(buffer) / n;
			auto x_mean = (n - 1.0) / 2.0;
			double sxy = 0.0;
			for (idx_t i = 0; i < ring.size; i++) {
				sxy += (static_cast<double>(i) - x_mean) * (ring.At(buffer, i) - mean);
			}
			auto slope = sxy / (n * (n * n - 1.0) / 12.0);
			auto intercept = mean - slope * x_mean;
			switch (KIND) {
			case TechRegressionKind::ENDPOINT:
				out[0] = intercept + slope * (n - 1.0);
				break;
			case TechRegressionKind::SLOPE:
				out[0] = slope;
				break;
			case TechRegressionKind::INTERCEPT:
				out[0] = intercept;
				break;
			default:
				out[0] = intercept + slope * n;
				break;
			}
			return true;
		}
	};
};

struct TechLinearRegOp : public TechRegressionOp<TechRegressionKind::ENDPOINT> {
	static constexpr const char *NAME = "fin_linearreg";
};
struct TechLinearRegSlopeOp : public TechRegressionOp<TechRegressionKind::SLOPE> {
	static constexpr const char *NAME = "fin_linearreg_slope";
};
struct TechLinearRegInterceptOp : public TechRegressionOp<TechRegressionKind::INTERCEPT> {
	static constexpr const char *NAME = "fin_linearreg_intercept";
};
struct TechTsfOp : public TechRegressionOp<TechRegressionKind::FORECAST> {
	static constexpr const char *NAME = "fin_tsf";
};

// Momentum family over x_t and x_{t - period}. A zero base price returns NULL
// for the ratio forms (TA-Lib returns 0).
enum class TechMomentumKind : uint8_t { MOM, ROC, ROCP, ROCR, ROCR100 };

template <TechMomentumKind KIND>
struct TechMomentumOp {
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 10)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]) + 1;
	}
	struct Kernel {
		TechRing ring;
		void Init(const double *p, idx_t &cursor) {
			ring.Init(cursor, TechPeriod(p[0]) + 1);
		}
		void Reset() {
			ring.Clear();
		}
		void Push(double *buffer, const double *in) {
			ring.Push(buffer, in[0]);
		}
		bool Value(const double *buffer, double *out) const {
			if (!ring.Full()) {
				return false;
			}
			auto now = ring.Newest(buffer);
			auto base = ring.At(buffer, 0);
			if (KIND == TechMomentumKind::MOM) {
				out[0] = now - base;
				return true;
			}
			if (base == 0.0) {
				return false;
			}
			switch (KIND) {
			case TechMomentumKind::ROC:
				out[0] = (now / base - 1.0) * 100.0;
				break;
			case TechMomentumKind::ROCP:
				out[0] = (now - base) / base;
				break;
			case TechMomentumKind::ROCR:
				out[0] = now / base;
				break;
			default:
				out[0] = now / base * 100.0;
				break;
			}
			return true;
		}
	};
};

struct TechMomOp : public TechMomentumOp<TechMomentumKind::MOM> {
	static constexpr const char *NAME = "fin_mom";
};
struct TechRocOp : public TechMomentumOp<TechMomentumKind::ROC> {
	static constexpr const char *NAME = "fin_roc";
};
struct TechRocpOp : public TechMomentumOp<TechMomentumKind::ROCP> {
	static constexpr const char *NAME = "fin_rocp";
};
struct TechRocrOp : public TechMomentumOp<TechMomentumKind::ROCR> {
	static constexpr const char *NAME = "fin_rocr";
};
struct TechRocr100Op : public TechMomentumOp<TechMomentumKind::ROCR100> {
	static constexpr const char *NAME = "fin_rocr100";
};

template <bool CMO>
struct TechWilderOscillatorOp {
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 14)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechWilderStage wilder;
		bool ready;
		void Init(const double *p, idx_t &) {
			wilder.Init(TechPeriod(p[0]));
		}
		void Reset() {
			wilder.Reset();
			ready = false;
		}
		void Push(double *, const double *in) {
			ready = wilder.Push(in[0]);
		}
		bool Value(const double *, double *out) const {
			out[0] = CMO ? wilder.Cmo() : wilder.Rsi();
			return ready;
		}
	};
};

struct TechRsiOp : public TechWilderOscillatorOp<false> {
	static constexpr const char *NAME = "fin_rsi";
};
struct TechCmoOp : public TechWilderOscillatorOp<true> {
	static constexpr const char *NAME = "fin_cmo";
};

// MACD: EMA(fast) - EMA(slow) aligned as in TA-Lib, signal = EMA(signal) of the
// MACD line, hist = macd - signal. fast and slow are swapped when slow < fast.
struct TechMacdOp {
	static constexpr const char *NAME = "fin_macd";
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 3;
	static constexpr idx_t FIELD_COUNT = 3;
	static const char *const *Fields() {
		static const char *const fields[] = {"macd", "signal", "hist"};
		return fields;
	}
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD2_PARAM("fast", 12), TECH_PERIOD2_PARAM("slow", 26),
		                                      TECH_PERIOD_PARAM("signal", 9)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechMaPair pair;
		TechEmaStage signal;
		double macd;
		double signal_value;
		bool ready;
		void Init(const double *p, idx_t &cursor) {
			pair.Init(cursor, p[0], p[1], true, true);
			signal.Init(TechPeriod(p[2]));
		}
		void Reset() {
			pair.Reset();
			signal.Reset();
			ready = false;
		}
		void Push(double *buffer, const double *in) {
			if (!pair.Push(buffer, in[0])) {
				return;
			}
			macd = pair.fast_value - pair.slow_value;
			ready = signal.Push(macd, signal_value);
		}
		bool Value(const double *, double *out) const {
			out[0] = macd;
			out[1] = signal_value;
			out[2] = macd - signal_value;
			return ready;
		}
	};
};

// APO = fastMA - slowMA; PPO = 100 * (fastMA - slowMA) / slowMA. ma_type is
// 'sma' (TA-Lib default) or 'ema'.
template <bool PERCENT>
struct TechPriceOscillatorOp {
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 3;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD2_PARAM("fast", 12), TECH_PERIOD2_PARAM("slow", 26),
		                                      {"ma_type", TECH_MA_SMA, TechParamKind::MA_TYPE, 0.0, 1.0, false}};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return p[2] == TECH_MA_SMA ? TechPeriod(std::max(p[0], p[1])) : 0;
	}
	struct Kernel {
		TechMaPair pair;
		bool ready;
		void Init(const double *p, idx_t &cursor) {
			pair.Init(cursor, p[0], p[1], p[2] == TECH_MA_EMA, false);
		}
		void Reset() {
			pair.Reset();
			ready = false;
		}
		void Push(double *buffer, const double *in) {
			ready = pair.Push(buffer, in[0]);
		}
		bool Value(const double *buffer, double *out) const {
			if (!ready) {
				return false;
			}
			double fast, slow;
			pair.Values(buffer, fast, slow);
			if (!PERCENT) {
				out[0] = fast - slow;
				return true;
			}
			if (slow == 0.0) {
				return false;
			}
			out[0] = 100.0 * (fast - slow) / slow;
			return true;
		}
	};
};

struct TechApoOp : public TechPriceOscillatorOp<false> {
	static constexpr const char *NAME = "fin_apo";
};
struct TechPpoOp : public TechPriceOscillatorOp<true> {
	static constexpr const char *NAME = "fin_ppo";
};

// TRIX: 1-period rate of change (in percent) of a triple-smoothed EMA.
struct TechTrixOp {
	static constexpr const char *NAME = "fin_trix";
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 30)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechEmaChain<3> chain;
		double previous;
		double current;
		idx_t outputs;
		void Init(const double *p, idx_t &) {
			chain.Init(TechPeriod(p[0]));
		}
		void Reset() {
			chain.Reset();
			previous = current = 0.0;
			outputs = 0;
		}
		void Push(double *, const double *in) {
			chain.Push(in[0]);
			if (chain.ready) {
				previous = current;
				current = chain.values[2];
				outputs++;
			}
		}
		bool Value(const double *, double *out) const {
			if (outputs < 2 || previous == 0.0) {
				return false;
			}
			out[0] = (current - previous) / previous * 100.0;
			return true;
		}
	};
};

// Highest high / lowest low helpers over paired rings.
struct TechRange {
	TechRing high;
	TechRing low;
	void Init(idx_t &cursor, idx_t period) {
		high.Init(cursor, period);
		low.Init(cursor, period);
	}
	void Reset() {
		high.Clear();
		low.Clear();
	}
	void Push(double *buffer, double h, double l) {
		high.Push(buffer, h);
		low.Push(buffer, l);
	}
	bool Full() const {
		return high.Full();
	}
};

// Stochastic (TA-Lib STOCH with SMA smoothing): fastK over k rows, slowK =
// SMA(fastK, smooth), slowD = SMA(slowK, d). A flat range gives fastK = 0.
struct TechStochOp {
	static constexpr const char *NAME = "fin_stoch";
	static constexpr idx_t INPUTS = 3;
	static constexpr idx_t PARAM_COUNT = 3;
	static constexpr idx_t FIELD_COUNT = 2;
	static const char *const *Fields() {
		static const char *const fields[] = {"k", "d"};
		return fields;
	}
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("k", 14), TECH_PERIOD_PARAM("d", 3),
		                                      TECH_PERIOD_PARAM("smooth", 3)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]) + TechPeriod(p[1]) + TechPeriod(p[2]) - 2;
	}
	struct Kernel {
		TechRange range;
		TechSmaStage slow_k;
		TechSmaStage slow_d;
		void Init(const double *p, idx_t &cursor) {
			range.Init(cursor, TechPeriod(p[0]));
			slow_k.Init(cursor, TechPeriod(p[2]));
			slow_d.Init(cursor, TechPeriod(p[1]));
		}
		void Reset() {
			range.Reset();
			slow_k.Reset();
			slow_d.Reset();
		}
		void Push(double *buffer, const double *in) {
			range.Push(buffer, in[0], in[1]);
			if (!range.Full()) {
				return;
			}
			auto highest = range.high.Max(buffer);
			auto lowest = range.low.Min(buffer);
			auto diff = (highest - lowest) / 100.0;
			auto fast_k = diff != 0.0 ? (in[2] - lowest) / diff : 0.0;
			if (slow_k.Push(buffer, fast_k)) {
				slow_d.Push(buffer, slow_k.Mean(buffer));
			}
		}
		bool Value(const double *buffer, double *out) const {
			if (!slow_d.Ready()) {
				return false;
			}
			out[0] = slow_k.Mean(buffer);
			out[1] = slow_d.Mean(buffer);
			return true;
		}
	};
};

// Stochastic RSI (TA-Lib STOCHRSI): fastK = stochastic of RSI(period) over k
// RSI values, fastD = SMA(fastK, d). A flat RSI range gives fastK = 0.
struct TechStochRsiOp {
	static constexpr const char *NAME = "fin_stochrsi";
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 3;
	static constexpr idx_t FIELD_COUNT = 2;
	static const char *const *Fields() {
		static const char *const fields[] = {"k", "d"};
		return fields;
	}
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 14), TECH_PERIOD_PARAM("k", 3),
		                                      TECH_PERIOD_PARAM("d", 3)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechWilderStage wilder;
		TechRing rsi;
		TechSmaStage fast_d;
		double k_value;
		void Init(const double *p, idx_t &cursor) {
			wilder.Init(TechPeriod(p[0]));
			rsi.Init(cursor, TechPeriod(p[1]));
			fast_d.Init(cursor, TechPeriod(p[2]));
		}
		void Reset() {
			wilder.Reset();
			rsi.Clear();
			fast_d.Reset();
		}
		void Push(double *buffer, const double *in) {
			if (!wilder.Push(in[0])) {
				return;
			}
			auto value = wilder.Rsi();
			rsi.Push(buffer, value);
			if (!rsi.Full()) {
				return;
			}
			auto highest = rsi.Max(buffer);
			auto lowest = rsi.Min(buffer);
			auto diff = (highest - lowest) / 100.0;
			k_value = diff != 0.0 ? (value - lowest) / diff : 0.0;
			fast_d.Push(buffer, k_value);
		}
		bool Value(const double *buffer, double *out) const {
			if (!fast_d.Ready()) {
				return false;
			}
			out[0] = k_value;
			out[1] = fast_d.Mean(buffer);
			return true;
		}
	};
};

// Williams %R: -100 * (HH - close) / (HH - LL) over `period` rows; flat range 0.
struct TechWillrOp {
	static constexpr const char *NAME = "fin_willr";
	static constexpr idx_t INPUTS = 3;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 14)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]);
	}
	struct Kernel {
		TechRange range;
		double close;
		void Init(const double *p, idx_t &cursor) {
			range.Init(cursor, TechPeriod(p[0]));
		}
		void Reset() {
			range.Reset();
		}
		void Push(double *buffer, const double *in) {
			range.Push(buffer, in[0], in[1]);
			close = in[2];
		}
		bool Value(const double *buffer, double *out) const {
			if (!range.Full()) {
				return false;
			}
			auto highest = range.high.Max(buffer);
			auto lowest = range.low.Min(buffer);
			auto diff = (highest - lowest) / -100.0;
			out[0] = diff != 0.0 ? (highest - close) / diff : 0.0;
			return true;
		}
	};
};

// CCI: (TP - SMA(TP)) / (constant * mean absolute deviation of TP), TP = (H+L+C)/3.
struct TechCciOp {
	static constexpr const char *NAME = "fin_cci";
	static constexpr idx_t INPUTS = 3;
	static constexpr idx_t PARAM_COUNT = 2;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 20),
		                                      {"constant", 0.015, TechParamKind::REAL, 0.0, 1e300, true}};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]);
	}
	struct Kernel {
		TechRing typical;
		double constant;
		void Init(const double *p, idx_t &cursor) {
			typical.Init(cursor, TechPeriod(p[0]));
			constant = p[1];
		}
		void Reset() {
			typical.Clear();
		}
		void Push(double *buffer, const double *in) {
			typical.Push(buffer, (in[0] + in[1] + in[2]) / 3.0);
		}
		bool Value(const double *buffer, double *out) const {
			if (!typical.Full()) {
				return false;
			}
			auto n = static_cast<double>(typical.size);
			auto mean = typical.Sum(buffer) / n;
			double deviation = 0.0;
			for (idx_t i = 0; i < typical.size; i++) {
				deviation += std::abs(typical.At(buffer, i) - mean);
			}
			auto distance = typical.Newest(buffer) - mean;
			out[0] = (distance != 0.0 && deviation != 0.0) ? distance / (constant * (deviation / n)) : 0.0;
			return true;
		}
	};
};

// Rolling mean and variance over a ring (two-pass for accuracy).
static void TechRingMoments(const TechRing &ring, const double *buffer, double ddof, double &mean, double &variance) {
	auto n = static_cast<double>(ring.size);
	mean = ring.Sum(buffer) / n;
	double squares = 0.0;
	double residual = 0.0;
	for (idx_t i = 0; i < ring.size; i++) {
		auto d = ring.At(buffer, i) - mean;
		squares += d * d;
		residual += d;
	}
	variance = std::max(0.0, (squares - residual * residual / n) / (n - ddof));
}

static constexpr TechParamSpec TECH_DDOF_PARAM = {"ddof", 0.0, TechParamKind::PERIOD, 0.0, TECH_MAX_PERIOD, false};

static void TechValidateDdof(const char *name, double period, double ddof) {
	if (ddof >= period) {
		throw InvalidInputException("%s: ddof must be smaller than period", name);
	}
}

// Bollinger Bands: middle = SMA(period); bands = middle +/- k * stddev with
// population standard deviation by default (ddof 0, TA-Lib).
struct TechBbandsOp {
	static constexpr const char *NAME = "fin_bbands";
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 3;
	static constexpr idx_t FIELD_COUNT = 5;
	static const char *const *Fields() {
		static const char *const fields[] = {"lower", "middle", "upper", "width", "percent_b"};
		return fields;
	}
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 20),
		                                      {"k", 2.0, TechParamKind::REAL, -1e300, 1e300, false},
		                                      TECH_DDOF_PARAM};
		return specs;
	}
	static void Validate(const char *name, const double *p) {
		TechValidateDdof(name, p[0], p[2]);
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]);
	}
	struct Kernel {
		TechRing ring;
		double k;
		double ddof;
		void Init(const double *p, idx_t &cursor) {
			ring.Init(cursor, TechPeriod(p[0]));
			k = p[1];
			ddof = p[2];
		}
		void Reset() {
			ring.Clear();
		}
		void Push(double *buffer, const double *in) {
			ring.Push(buffer, in[0]);
		}
		bool Value(const double *buffer, double *out) const {
			if (!ring.Full()) {
				return false;
			}
			double mean, variance;
			TechRingMoments(ring, buffer, ddof, mean, variance);
			auto band = k * std::sqrt(variance);
			auto lower = mean - band;
			auto upper = mean + band;
			out[0] = lower;
			out[1] = mean;
			out[2] = upper;
			out[3] = mean != 0.0 ? (upper - lower) / mean : std::numeric_limits<double>::quiet_NaN();
			out[4] = upper != lower ? (ring.Newest(buffer) - lower) / (upper - lower)
			                        : std::numeric_limits<double>::quiet_NaN();
			return true;
		}
	};
};

template <bool ROOT>
struct TechDispersionOp {
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 2;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 20), TECH_DDOF_PARAM};
		return specs;
	}
	static void Validate(const char *name, const double *p) {
		TechValidateDdof(name, p[0], p[1]);
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]);
	}
	struct Kernel {
		TechRing ring;
		double ddof;
		void Init(const double *p, idx_t &cursor) {
			ring.Init(cursor, TechPeriod(p[0]));
			ddof = p[1];
		}
		void Reset() {
			ring.Clear();
		}
		void Push(double *buffer, const double *in) {
			ring.Push(buffer, in[0]);
		}
		bool Value(const double *buffer, double *out) const {
			if (!ring.Full()) {
				return false;
			}
			double mean, variance;
			TechRingMoments(ring, buffer, ddof, mean, variance);
			out[0] = ROOT ? std::sqrt(variance) : variance;
			return true;
		}
	};
};

struct TechStddevOp : public TechDispersionOp<true> {
	static constexpr const char *NAME = "fin_stddev";
};
struct TechVarOp : public TechDispersionOp<false> {
	static constexpr const char *NAME = "fin_var_indicator";
};

// Keltner channel: middle = EMA(close, period); bands = middle +/- multiplier *
// ATR(atr_period) with TA-Lib's Wilder ATR (seeded with the mean of the first
// atr_period true ranges, first true range at the second row).
struct TechKeltnerOp {
	static constexpr const char *NAME = "fin_keltner";
	static constexpr idx_t INPUTS = 3;
	static constexpr idx_t PARAM_COUNT = 3;
	static constexpr idx_t FIELD_COUNT = 3;
	static const char *const *Fields() {
		static const char *const fields[] = {"lower", "middle", "upper"};
		return fields;
	}
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 20), TECH_PERIOD_PARAM("atr_period", 10),
		                                      {"multiplier", 2.0, TechParamKind::REAL, -1e300, 1e300, false}};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechEmaStage middle;
		double middle_value;
		bool middle_ready;
		double atr_period;
		idx_t atr_needed;
		idx_t ranges;
		bool has_close;
		double previous_close;
		double atr;
		double multiplier;
		void Init(const double *p, idx_t &) {
			middle.Init(TechPeriod(p[0]));
			atr_period = p[1];
			atr_needed = TechPeriod(p[1]);
			multiplier = p[2];
		}
		void Reset() {
			middle.Reset();
			middle_ready = false;
			ranges = 0;
			has_close = false;
			previous_close = atr = 0.0;
		}
		void Push(double *, const double *in) {
			middle_ready = middle.Push(in[2], middle_value);
			if (has_close) {
				auto range = std::max(in[0] - in[1], std::max(std::abs(previous_close - in[0]),
				                                                std::abs(in[1] - previous_close)));
				if (ranges < atr_needed) {
					atr += range / atr_period;
					ranges++;
				} else {
					atr = (atr * (atr_period - 1.0) + range) / atr_period;
				}
			}
			has_close = true;
			previous_close = in[2];
		}
		bool Value(const double *, double *out) const {
			if (!middle_ready || ranges < atr_needed) {
				return false;
			}
			out[0] = middle_value - multiplier * atr;
			out[1] = middle_value;
			out[2] = middle_value + multiplier * atr;
			return true;
		}
	};
};

// Donchian channel over `period` rows: upper = highest high, lower = lowest low.
struct TechDonchianOp {
	static constexpr const char *NAME = "fin_donchian";
	static constexpr idx_t INPUTS = 2;
	static constexpr idx_t PARAM_COUNT = 1;
	static constexpr idx_t FIELD_COUNT = 3;
	static const char *const *Fields() {
		static const char *const fields[] = {"lower", "middle", "upper"};
		return fields;
	}
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 20)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]);
	}
	struct Kernel {
		TechRange range;
		void Init(const double *p, idx_t &cursor) {
			range.Init(cursor, TechPeriod(p[0]));
		}
		void Reset() {
			range.Reset();
		}
		void Push(double *buffer, const double *in) {
			range.Push(buffer, in[0], in[1]);
		}
		bool Value(const double *buffer, double *out) const {
			if (!range.Full()) {
				return false;
			}
			auto upper = range.high.Max(buffer);
			auto lower = range.low.Min(buffer);
			out[0] = lower;
			out[1] = (upper + lower) / 2.0;
			out[2] = upper;
			return true;
		}
	};
};

// Aroon over period + 1 rows: up = 100 * (period - rows since highest high) /
// period (ties pick the most recent extreme, as TA-Lib).
template <bool OSCILLATOR>
struct TechAroonOp {
	static constexpr idx_t INPUTS = 2;
	static constexpr idx_t PARAM_COUNT = 1;
	static constexpr idx_t FIELD_COUNT = OSCILLATOR ? 0 : 3;
	static const char *const *Fields() {
		static const char *const fields[] = {"aroon_up", "aroon_down", "oscillator"};
		return OSCILLATOR ? nullptr : fields;
	}
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("period", 14)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]) + 1;
	}
	struct Kernel {
		TechRange range;
		void Init(const double *p, idx_t &cursor) {
			range.Init(cursor, TechPeriod(p[0]) + 1);
		}
		void Reset() {
			range.Reset();
		}
		void Push(double *buffer, const double *in) {
			range.Push(buffer, in[0], in[1]);
		}
		bool Value(const double *buffer, double *out) const {
			if (!range.Full()) {
				return false;
			}
			idx_t highest_index = 0;
			idx_t lowest_index = 0;
			auto highest = range.high.At(buffer, 0);
			auto lowest = range.low.At(buffer, 0);
			for (idx_t i = 1; i < range.high.size; i++) {
				auto h = range.high.At(buffer, i);
				auto l = range.low.At(buffer, i);
				if (h >= highest) {
					highest = h;
					highest_index = i;
				}
				if (l <= lowest) {
					lowest = l;
					lowest_index = i;
				}
			}
			auto period = static_cast<double>(range.high.size - 1);
			auto newest = static_cast<double>(range.high.size - 1);
			auto factor = 100.0 / period;
			auto up = factor * (period - (newest - static_cast<double>(highest_index)));
			auto down = factor * (period - (newest - static_cast<double>(lowest_index)));
			if (OSCILLATOR) {
				out[0] = up - down;
			} else {
				out[0] = up;
				out[1] = down;
				out[2] = up - down;
			}
			return true;
		}
	};
};

struct TechAroonStructOp : public TechAroonOp<false> {
	static constexpr const char *NAME = "fin_aroon";
};
struct TechAroonOscOp : public TechAroonOp<true> {
	static constexpr const char *NAME = "fin_aroonosc";
};

// Parabolic SAR, TA-Lib SAR / SAREXT algorithm. The initial direction comes
// from the first two bars' directional movement (or the sign of start_value);
// SAREXT reports short positions as negative values.
template <bool EXTENDED>
struct TechSarKernel {
	double start_value;
	double offset_on_reverse;
	double af_init_long, af_step_long, af_max_long;
	double af_init_short, af_step_short, af_max_short;
	idx_t seen;
	double first_high;
	double first_low;
	bool is_long;
	double sar;
	double ep;
	double af_long;
	double af_short;
	double new_high;
	double new_low;
	double output;

	void Configure(const double *p) {
		if (EXTENDED) {
			start_value = p[0];
			offset_on_reverse = p[1];
			af_init_long = p[2];
			af_step_long = p[3];
			af_max_long = p[4];
			af_init_short = p[5];
			af_step_short = p[6];
			af_max_short = p[7];
		} else {
			start_value = 0.0;
			offset_on_reverse = 0.0;
			af_init_long = af_step_long = af_init_short = af_step_short = p[0];
			af_max_long = af_max_short = p[1];
		}
		if (af_init_long > af_max_long) {
			af_init_long = af_max_long;
		}
		if (af_step_long > af_max_long) {
			af_step_long = af_max_long;
		}
		if (af_init_short > af_max_short) {
			af_init_short = af_max_short;
		}
		if (af_step_short > af_max_short) {
			af_step_short = af_max_short;
		}
	}

	void Reset() {
		seen = 0;
		output = 0.0;
	}

	void Push(double high, double low) {
		if (seen == 0) {
			first_high = high;
			first_low = low;
			seen = 1;
			return;
		}
		if (seen == 1) {
			if (start_value == 0.0) {
				auto up_move = high - first_high;
				auto down_move = first_low - low;
				auto minus_dm = (down_move > 0.0 && up_move < down_move) ? down_move : 0.0;
				is_long = !(minus_dm > 0.0);
			} else {
				is_long = start_value > 0.0;
			}
			af_long = af_init_long;
			af_short = af_init_short;
			if (start_value == 0.0) {
				ep = is_long ? high : low;
				sar = is_long ? first_low : first_high;
			} else if (start_value > 0.0) {
				ep = high;
				sar = start_value;
			} else {
				ep = low;
				sar = std::abs(start_value);
			}
			new_low = low;
			new_high = high;
		}
		auto prev_low = new_low;
		auto prev_high = new_high;
		new_low = low;
		new_high = high;
		if (is_long) {
			if (new_low <= sar) {
				is_long = false;
				sar = ep;
				sar = std::max(sar, std::max(prev_high, new_high));
				if (offset_on_reverse != 0.0) {
					sar += sar * offset_on_reverse;
				}
				output = EXTENDED ? -sar : sar;
				af_short = af_init_short;
				ep = new_low;
				sar = sar + af_short * (ep - sar);
				sar = std::max(sar, std::max(prev_high, new_high));
			} else {
				output = sar;
				if (new_high > ep) {
					ep = new_high;
					af_long = std::min(af_long + af_step_long, af_max_long);
				}
				sar = sar + af_long * (ep - sar);
				sar = std::min(sar, std::min(prev_low, new_low));
			}
		} else {
			if (new_high >= sar) {
				is_long = true;
				sar = ep;
				sar = std::min(sar, std::min(prev_low, new_low));
				if (offset_on_reverse != 0.0) {
					sar -= sar * offset_on_reverse;
				}
				output = sar;
				af_long = af_init_long;
				ep = new_high;
				sar = sar + af_long * (ep - sar);
				sar = std::min(sar, std::min(prev_low, new_low));
			} else {
				output = EXTENDED ? -sar : sar;
				if (new_low < ep) {
					ep = new_low;
					af_short = std::min(af_short + af_step_short, af_max_short);
				}
				sar = sar + af_short * (ep - sar);
				sar = std::max(sar, std::max(prev_high, new_high));
			}
		}
		seen++;
	}
};

struct TechSarOp {
	static constexpr const char *NAME = "fin_sar";
	static constexpr idx_t INPUTS = 2;
	static constexpr idx_t PARAM_COUNT = 2;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {{"acceleration", 0.02, TechParamKind::REAL, 0.0, 1e300, false},
		                                      {"maximum", 0.2, TechParamKind::REAL, 0.0, 1e300, false}};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechSarKernel<false> sar;
		void Init(const double *p, idx_t &) {
			sar.Configure(p);
		}
		void Reset() {
			sar.Reset();
		}
		void Push(double *, const double *in) {
			sar.Push(in[0], in[1]);
		}
		bool Value(const double *, double *out) const {
			out[0] = sar.output;
			return sar.seen >= 2;
		}
	};
};

struct TechSarExtOp {
	static constexpr const char *NAME = "fin_sarext";
	static constexpr idx_t INPUTS = 2;
	static constexpr idx_t PARAM_COUNT = 8;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {{"start_value", 0.0, TechParamKind::REAL, -1e300, 1e300, false},
		                                      {"offset_on_reverse", 0.0, TechParamKind::REAL, 0.0, 1e300, false},
		                                      {"af_init_long", 0.02, TechParamKind::REAL, 0.0, 1e300, false},
		                                      {"af_long", 0.02, TechParamKind::REAL, 0.0, 1e300, false},
		                                      {"af_max_long", 0.2, TechParamKind::REAL, 0.0, 1e300, false},
		                                      {"af_init_short", 0.02, TechParamKind::REAL, 0.0, 1e300, false},
		                                      {"af_short", 0.02, TechParamKind::REAL, 0.0, 1e300, false},
		                                      {"af_max_short", 0.2, TechParamKind::REAL, 0.0, 1e300, false}};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechSarKernel<true> sar;
		void Init(const double *p, idx_t &) {
			sar.Configure(p);
		}
		void Reset() {
			sar.Reset();
		}
		void Push(double *, const double *in) {
			sar.Push(in[0], in[1]);
		}
		bool Value(const double *, double *out) const {
			out[0] = sar.output;
			return sar.seen >= 2;
		}
	};
};

//===--------------------------------------------------------------------===//
// Aggregate driver
//===--------------------------------------------------------------------===//
template <class OP>
struct TechState {
	typename OP::Kernel kernel;
	double params[TECH_MAX_PARAMS];
	double last_input[TECH_MAX_INPUTS];
	double *buffer;
	idx_t buffer_size;
	idx_t memory;
	idx_t count;
	idx_t bad_position;
	bool prepared;
	FinWindowAux *window;
};

template <class OP>
struct TechDriver {
	using STATE = TechState<OP>;

	template <class S>
	static void Initialize(S &state) {
		state.buffer = nullptr;
		state.buffer_size = 0;
		state.memory = 0;
		state.count = 0;
		state.bad_position = 0;
		state.prepared = false;
		state.window = nullptr;
		for (idx_t i = 0; i < TECH_MAX_INPUTS; i++) {
			state.last_input[i] = 0.0;
		}
	}

	static void Prepare(STATE &state, const TechBindData &bind) {
		if (state.prepared) {
			return;
		}
		memcpy(state.params, bind.values, sizeof(state.params));
		idx_t cursor = 0;
		state.kernel.Init(state.params, cursor);
		if (cursor > 0) {
			state.buffer = new double[cursor];
			state.buffer_size = cursor;
		}
		state.memory = OP::Memory(state.params);
		state.kernel.Reset();
		state.prepared = true;
	}

	static void Reset(STATE &state) {
		state.count = 0;
		state.bad_position = 0;
		for (idx_t i = 0; i < TECH_MAX_INPUTS; i++) {
			state.last_input[i] = 0.0;
		}
		state.kernel.Reset();
	}

	static void Push(STATE &state, double *in) {
		state.count++;
		bool finite = true;
		for (idx_t i = 0; i < OP::INPUTS; i++) {
			finite = finite && std::isfinite(in[i]);
		}
		if (!finite) {
			state.bad_position = state.count;
			if (state.memory == 0) {
				return;
			}
			// Bounded indicators keep their window aligned with a stand-in row;
			// the result stays NULL until the bad row leaves the lookback.
			for (idx_t i = 0; i < OP::INPUTS; i++) {
				in[i] = state.last_input[i];
			}
		} else {
			for (idx_t i = 0; i < OP::INPUTS; i++) {
				state.last_input[i] = in[i];
			}
		}
		if (state.memory == 0 && state.bad_position != 0) {
			return;
		}
		state.kernel.Push(state.buffer, in);
	}

	static bool Value(const STATE &state, double *out) {
		if (!state.prepared || state.count == 0) {
			return false;
		}
		if (state.bad_position != 0 && (state.memory == 0 || state.count - state.bad_position < state.memory)) {
			return false;
		}
		return state.kernel.Value(state.buffer, out);
	}

	static void Write(const STATE &state, Vector &result, idx_t index) {
		double out[TECH_MAX_FIELDS];
		if (!Value(state, out)) {
			FlatVector::SetNull(result, index, true);
			return;
		}
		if (OP::FIELD_COUNT == 0) {
			if (!std::isfinite(out[0])) {
				FlatVector::SetNull(result, index, true);
				return;
			}
			FlatVector::GetData<double>(result)[index] = out[0];
			return;
		}
		auto &children = StructVector::GetEntries(result);
		for (idx_t f = 0; f < OP::FIELD_COUNT; f++) {
			auto &child = *children[f];
			if (std::isfinite(out[f])) {
				FlatVector::GetData<double>(child)[index] = out[f];
			} else {
				FlatVector::SetNull(child, index, true);
			}
		}
	}

	template <class S, class O>
	static void Combine(const S &source, S &target, AggregateInputData &) {
		if (source.count == 0) {
			return;
		}
		if (target.count != 0) {
			throw InvalidInputException(
			    "%s: rows reached the aggregate in an undefined order. Use an ordered call such as %s(... ORDER BY ts) "
			    "or a window with ORDER BY and a frame that ends at the current row",
			    OP::NAME, OP::NAME);
		}
		auto buffer = target.buffer;
		auto buffer_size = target.buffer_size;
		auto window = target.window;
		target = source;
		target.window = window;
		target.buffer = buffer;
		target.buffer_size = buffer_size;
		if (source.buffer_size > 0) {
			if (target.buffer_size != source.buffer_size) {
				delete[] target.buffer;
				target.buffer = new double[source.buffer_size];
				target.buffer_size = source.buffer_size;
			}
			memcpy(target.buffer, source.buffer, sizeof(double) * source.buffer_size);
		}
	}

	template <class S>
	static void Destroy(S &state, AggregateInputData &) {
		delete[] state.buffer;
		state.buffer = nullptr;
		delete state.window;
		state.window = nullptr;
	}
};

template <class OP, class STATE_ACCESS>
static void TechUpdateRows(Vector inputs[], AggregateInputData &aggr_input_data, idx_t count,
                           STATE_ACCESS &&state_for_row) {
	auto &bind = aggr_input_data.bind_data->Cast<TechBindData>();
	UnifiedVectorFormat formats[TECH_MAX_INPUTS];
	const double *data[TECH_MAX_INPUTS];
	for (idx_t c = 0; c < OP::INPUTS; c++) {
		inputs[c].ToUnifiedFormat(count, formats[c]);
		data[c] = UnifiedVectorFormat::GetData<double>(formats[c]);
	}
	double row[TECH_MAX_INPUTS];
	for (idx_t i = 0; i < count; i++) {
		bool valid = true;
		for (idx_t c = 0; c < OP::INPUTS; c++) {
			auto index = formats[c].sel->get_index(i);
			if (!formats[c].validity.RowIsValid(index)) {
				valid = false;
				break;
			}
			row[c] = data[c][index];
		}
		if (!valid) {
			continue;
		}
		auto &state = state_for_row(i);
		TechDriver<OP>::Prepare(state, bind);
		TechDriver<OP>::Push(state, row);
	}
}

template <class OP>
static void TechScatterUpdate(Vector inputs[], AggregateInputData &aggr_input_data, idx_t, Vector &states,
                              idx_t count) {
	UnifiedVectorFormat sdata;
	states.ToUnifiedFormat(count, sdata);
	auto state_values = UnifiedVectorFormat::GetData<TechState<OP> *>(sdata);
	TechUpdateRows<OP>(inputs, aggr_input_data, count,
	                   [&](idx_t i) -> TechState<OP> & { return *state_values[sdata.sel->get_index(i)]; });
}

template <class OP>
static void TechSimpleUpdate(Vector inputs[], AggregateInputData &aggr_input_data, idx_t, data_ptr_t state_ptr,
                             idx_t count) {
	auto &state = *reinterpret_cast<TechState<OP> *>(state_ptr);
	TechUpdateRows<OP>(inputs, aggr_input_data, count, [&](idx_t) -> TechState<OP> & { return state; });
}

template <class OP>
static void TechFinalize(Vector &states, AggregateInputData &, Vector &result, idx_t count, idx_t offset) {
	UnifiedVectorFormat sdata;
	states.ToUnifiedFormat(count, sdata);
	auto state_values = UnifiedVectorFormat::GetData<TechState<OP> *>(sdata);
	for (idx_t i = 0; i < count; i++) {
		TechDriver<OP>::Write(*state_values[sdata.sel->get_index(i)], result, i + offset);
	}
}

// Window evaluation. Frames with a fixed start (running frames) append the rows
// that entered the frame. Bounded indicators also slide incrementally while the
// frame holds at least `Memory` counted rows; any other frame is rebuilt, and a
// bounded indicator then replays only the last `Memory` counted rows.
template <class OP>
static void TechWindow(AggregateInputData &aggr_input_data, const WindowPartitionInput &partition, const_data_ptr_t,
                       data_ptr_t l_state, const SubFrames &frames, Vector &result, idx_t rid) {
	using DRIVER = TechDriver<OP>;
	auto &state = *reinterpret_cast<TechState<OP> *>(l_state);
	DRIVER::Prepare(state, aggr_input_data.bind_data->Cast<TechBindData>());
	if (!state.window) {
		state.window = new FinWindowAux();
	}
	auto &aux = *state.window;
	aux.Initialize(partition);
	const auto &filter_mask = partition.filter_mask;
	bool all_valid = filter_mask.AllValid();
	for (idx_t c = 0; c < partition.all_valid.size(); c++) {
		all_valid = all_valid && partition.all_valid[c];
	}
	double row[TECH_MAX_INPUTS];
	auto read = [&](idx_t i) -> bool {
		if (!filter_mask.RowIsValid(i)) {
			return false;
		}
		auto offset = aux.Seek(i);
		for (idx_t c = 0; c < OP::INPUTS; c++) {
			auto &vector = aux.page->data[c];
			if (!FlatVector::Validity(vector).RowIsValid(offset)) {
				return false;
			}
			row[c] = FlatVector::GetData<double>(vector)[offset];
		}
		return true;
	};
	auto feed = [&](idx_t begin, idx_t end) {
		for (idx_t i = begin; i < end; i++) {
			if (read(i)) {
				DRIVER::Push(state, row);
			}
		}
	};
	const auto memory = state.memory;
	if (frames.size() == 1) {
		const auto begin = frames[0].start;
		const auto end = std::max(frames[0].start, frames[0].end);
		const bool extends = aux.has_prev && end >= aux.prev_end && begin >= aux.prev_start && begin <= aux.prev_end;
		if (extends && (begin == aux.prev_start || (memory > 0 && all_valid && end - begin >= memory))) {
			feed(aux.prev_end, end);
		} else {
			DRIVER::Reset(state);
			auto start = begin;
			if (memory > 0) {
				if (all_valid) {
					start = end - begin > memory ? end - memory : begin;
				} else {
					idx_t needed = memory;
					idx_t i = end;
					while (i > begin && needed > 0) {
						--i;
						if (read(i)) {
							needed--;
						}
					}
					start = i;
				}
			}
			feed(start, end);
		}
		aux.has_prev = true;
		aux.prev_start = begin;
		aux.prev_end = end;
	} else {
		DRIVER::Reset(state);
		for (const auto &frame : frames) {
			feed(frame.start, frame.end);
		}
		aux.has_prev = false;
	}
	DRIVER::Write(state, result, rid);
}

//===--------------------------------------------------------------------===//
// Bind and registration
//===--------------------------------------------------------------------===//
static double TechParseMaType(const char *name, const string &text) {
	auto lower = StringUtil::Lower(text);
	if (lower == "sma") {
		return TECH_MA_SMA;
	}
	if (lower == "ema") {
		return TECH_MA_EMA;
	}
	throw InvalidInputException("%s: unknown ma_type '%s' (expected 'sma' or 'ema')", name, text);
}

template <class OP>
static unique_ptr<FunctionData> TechBind(ClientContext &context, AggregateFunction &function,
                                         vector<unique_ptr<Expression>> &arguments) {
	FinRejectNamedArguments(function, arguments);
	auto data = make_uniq<TechBindData>();
	auto specs = OP::Params();
	for (idx_t j = 0; j < OP::PARAM_COUNT; j++) {
		data->values[j] = specs[j].default_value;
	}
	for (idx_t j = 0; j + OP::INPUTS < arguments.size(); j++) {
		auto &argument = *arguments[OP::INPUTS + j];
		auto &spec = specs[j];
		if (!argument.IsFoldable()) {
			throw InvalidInputException("%s: %s must be a constant", OP::NAME, spec.name);
		}
		auto value = ExpressionExecutor::EvaluateScalar(context, argument, true);
		if (value.IsNull()) {
			throw InvalidInputException("%s: %s must not be NULL", OP::NAME, spec.name);
		}
		if (spec.kind == TechParamKind::MA_TYPE) {
			data->values[j] = TechParseMaType(OP::NAME, StringValue::Get(value.DefaultCastAs(LogicalType::VARCHAR)));
			continue;
		}
		auto number = DoubleValue::Get(value.DefaultCastAs(LogicalType::DOUBLE));
		if (spec.kind == TechParamKind::PERIOD) {
			if (!std::isfinite(number) || std::trunc(number) != number || number < spec.minimum ||
			    number > spec.maximum) {
				throw InvalidInputException("%s: %s must be an integer between %lld and %lld", OP::NAME, spec.name,
				                            static_cast<int64_t>(spec.minimum), static_cast<int64_t>(spec.maximum));
			}
		} else if (!std::isfinite(number) || number < spec.minimum || number > spec.maximum ||
		           (spec.exclusive_minimum && number == spec.minimum)) {
			if (spec.maximum < 1e300) {
				throw InvalidInputException("%s: %s must be between %g and %g", OP::NAME, spec.name, spec.minimum,
				                            spec.maximum);
			}
			if (spec.minimum > -1e300) {
				throw InvalidInputException("%s: %s must be finite and %s %g", OP::NAME, spec.name,
				                            spec.exclusive_minimum ? "greater than" : "at least", spec.minimum);
			}
			throw InvalidInputException("%s: %s must be finite", OP::NAME, spec.name);
		}
		data->values[j] = number;
	}
	OP::Validate(OP::NAME, data->values);
	// The parameters now live in the bind data; the aggregate only sees prices.
	while (arguments.size() > OP::INPUTS) {
		Function::EraseArgument(function, arguments, arguments.size() - 1);
	}
	return std::move(data);
}

template <class OP>
static LogicalType TechReturnType() {
	if (OP::FIELD_COUNT == 0) {
		return LogicalType(LogicalTypeId::DOUBLE);
	}
	child_list_t<LogicalType> children;
	auto fields = OP::Fields();
	for (idx_t f = 0; f < OP::FIELD_COUNT; f++) {
		children.emplace_back(fields[f], LogicalType(LogicalTypeId::DOUBLE));
	}
	return LogicalType::STRUCT(std::move(children));
}

template <class OP>
static void RegisterTechnicalIndicator(ExtensionLoader &loader) {
	using STATE = TechState<OP>;
	using DRIVER = TechDriver<OP>;
	AggregateFunctionSet set(FinanceFunctionName(OP::NAME));
	auto return_type = TechReturnType<OP>();
	auto specs = OP::Params();
	for (idx_t provided = 0; provided <= OP::PARAM_COUNT; provided++) {
		vector<LogicalType> arguments(OP::INPUTS, LogicalType(LogicalTypeId::DOUBLE));
		for (idx_t j = 0; j < provided; j++) {
			arguments.push_back(specs[j].kind == TechParamKind::MA_TYPE ? LogicalType(LogicalTypeId::VARCHAR)
			                                                            : LogicalType(LogicalTypeId::DOUBLE));
		}
		AggregateFunction function(arguments, return_type, AggregateFunction::StateSize<STATE>,
		                           AggregateFunction::StateInitialize<STATE, DRIVER, AggregateDestructorType::LEGACY>,
		                           TechScatterUpdate<OP>, AggregateFunction::StateCombine<STATE, DRIVER>,
		                           TechFinalize<OP>, FunctionNullHandling::DEFAULT_NULL_HANDLING,
		                           TechSimpleUpdate<OP>);
		function.SetStateDestructorCallback(AggregateFunction::StateDestroy<STATE, DRIVER>);
		function.SetBindCallback(TechBind<OP>);
		function.SetWindowCallback(TechWindow<OP>);
		function.SetOrderDependent(AggregateOrderDependent::ORDER_DEPENDENT);
		function.name = FinanceFunctionName(OP::NAME);
		set.AddFunction(std::move(function));
	}
	loader.RegisterFunction(std::move(set));
}

static void RegisterTechnicalAggregates(ExtensionLoader &loader) {
	RegisterTechnicalIndicator<TechSmaOp>(loader);
	RegisterTechnicalIndicator<TechWmaOp>(loader);
	RegisterTechnicalIndicator<TechEmaOp>(loader);
	RegisterTechnicalIndicator<TechDemaOp>(loader);
	RegisterTechnicalIndicator<TechTemaOp>(loader);
	RegisterTechnicalIndicator<TechTrimaOp>(loader);
	RegisterTechnicalIndicator<TechT3Op>(loader);
	RegisterTechnicalIndicator<TechKamaOp>(loader);
	RegisterTechnicalIndicator<TechHmaOp>(loader);
	RegisterTechnicalIndicator<TechLinearRegOp>(loader);
	RegisterTechnicalIndicator<TechLinearRegSlopeOp>(loader);
	RegisterTechnicalIndicator<TechLinearRegInterceptOp>(loader);
	RegisterTechnicalIndicator<TechTsfOp>(loader);
	RegisterTechnicalIndicator<TechMomOp>(loader);
	RegisterTechnicalIndicator<TechRocOp>(loader);
	RegisterTechnicalIndicator<TechRocpOp>(loader);
	RegisterTechnicalIndicator<TechRocrOp>(loader);
	RegisterTechnicalIndicator<TechRocr100Op>(loader);
	RegisterTechnicalIndicator<TechRsiOp>(loader);
	RegisterTechnicalIndicator<TechCmoOp>(loader);
	RegisterTechnicalIndicator<TechMacdOp>(loader);
	RegisterTechnicalIndicator<TechApoOp>(loader);
	RegisterTechnicalIndicator<TechPpoOp>(loader);
	RegisterTechnicalIndicator<TechTrixOp>(loader);
	RegisterTechnicalIndicator<TechStochOp>(loader);
	RegisterTechnicalIndicator<TechStochRsiOp>(loader);
	RegisterTechnicalIndicator<TechWillrOp>(loader);
	RegisterTechnicalIndicator<TechCciOp>(loader);
	RegisterTechnicalIndicator<TechBbandsOp>(loader);
	RegisterTechnicalIndicator<TechStddevOp>(loader);
	RegisterTechnicalIndicator<TechVarOp>(loader);
	RegisterTechnicalIndicator<TechKeltnerOp>(loader);
	RegisterTechnicalIndicator<TechDonchianOp>(loader);
	RegisterTechnicalIndicator<TechAroonStructOp>(loader);
	RegisterTechnicalIndicator<TechAroonOscOp>(loader);
	RegisterTechnicalIndicator<TechSarOp>(loader);
	RegisterTechnicalIndicator<TechSarExtOp>(loader);
}
