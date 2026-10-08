//===--------------------------------------------------------------------===//
// Volatility, directional movement, volume and microstructure indicators
//===--------------------------------------------------------------------===//
// These kernels plug into the technical indicator driver (technical.inc): they
// are order-dependent aggregates that return the value at the last ordered row,
// follow the TA-Lib definitions, seeding and warm-up, and keep state bounded by
// their periods.

// TA-Lib true range: max(H - L, |H - previous close|, |L - previous close|).
static double TechTrueRange(double high, double low, double previous_close) {
	return std::max(high - low, std::max(std::abs(high - previous_close), std::abs(low - previous_close)));
}

// Directional movement with TA-Lib's Wilder sums. For change n (n >= 1):
// +DM = H - H[-1] when that is positive and larger than L[-1] - L, -DM the
// mirror image. The first period - 1 changes are summed; later changes update
// S = S - S / period + x. +DM/-DM are reported from change max(period - 1, 1),
// +DI/-DI (100 * S_dm / S_tr) and DX from change `period`.
struct TechDirectionalStage {
	double period;
	idx_t seed;
	idx_t changes;
	bool has_previous;
	double previous_high;
	double previous_low;
	double previous_close;
	double plus;
	double minus;
	double range;

	void Init(idx_t period_p) {
		period = static_cast<double>(period_p);
		seed = period_p - 1;
	}

	void Reset() {
		changes = 0;
		has_previous = false;
		previous_high = previous_low = previous_close = 0.0;
		plus = minus = range = 0.0;
	}

	bool Push(double high, double low, double close) {
		if (!has_previous) {
			has_previous = true;
			previous_high = high;
			previous_low = low;
			previous_close = close;
			return false;
		}
		auto up = high - previous_high;
		auto down = previous_low - low;
		auto plus_dm = (up > 0.0 && up > down) ? up : 0.0;
		auto minus_dm = (down > 0.0 && up < down) ? down : 0.0;
		auto true_range = TechTrueRange(high, low, previous_close);
		if (changes < seed) {
			plus += plus_dm;
			minus += minus_dm;
			range += true_range;
		} else {
			plus = plus - plus / period + plus_dm;
			minus = minus - minus / period + minus_dm;
			range = range - range / period + true_range;
		}
		changes++;
		previous_high = high;
		previous_low = low;
		previous_close = close;
		return true;
	}

	bool DmReady() const {
		return changes >= std::max<idx_t>(seed, 1);
	}

	bool DiReady() const {
		return changes >= seed + 1;
	}

	double PlusDi() const {
		return range != 0.0 ? 100.0 * (plus / range) : 0.0;
	}

	double MinusDi() const {
		return range != 0.0 ? 100.0 * (minus / range) : 0.0;
	}

	// DX; false when it is undefined (zero true range or zero DI sum).
	bool Dx(double &out) const {
		if (range == 0.0) {
			return false;
		}
		auto plus_di = 100.0 * (plus / range);
		auto minus_di = 100.0 * (minus / range);
		auto total = plus_di + minus_di;
		if (total == 0.0) {
			return false;
		}
		out = 100.0 * (std::abs(minus_di - plus_di) / total);
		return true;
	}
};

#define TECH_HLC_PERIOD_OP(MINIMUM, DEFAULT)                                                                           \
	static constexpr idx_t INPUTS = 3;                                                                                 \
	static constexpr idx_t PARAM_COUNT = 1;                                                                            \
	TECH_NO_FIELDS                                                                                                     \
	static const TechParamSpec *Params() {                                                                             \
		static const TechParamSpec specs[] = {{"period", DEFAULT, TechParamKind::PERIOD, MINIMUM, TECH_MAX_PERIOD,     \
		                                       false}};                                                               \
		return specs;                                                                                                  \
	}                                                                                                                  \
	static void Validate(const char *, const double *) {                                                               \
	}

// TA-Lib TRANGE: the true range of the last row, using the previous row's close.
struct TechTrueRangeOp {
	static constexpr const char *NAME = "fin_true_range";
	static constexpr idx_t INPUTS = 3;
	static constexpr idx_t PARAM_COUNT = 0;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		return nullptr;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 2;
	}
	struct Kernel {
		idx_t seen;
		double previous_close;
		double value;
		void Init(const double *, idx_t &) {
		}
		void Reset() {
			seen = 0;
			previous_close = value = 0.0;
		}
		void Push(double *, const double *in) {
			if (seen > 0) {
				value = TechTrueRange(in[0], in[1], previous_close);
			}
			previous_close = in[2];
			seen++;
		}
		bool Value(const double *, double *out) const {
			out[0] = value;
			return seen >= 2;
		}
	};
};

// TA-Lib ATR / NATR: Wilder average of the true range, seeded with the mean of
// the first `period` true ranges (rows 1..period). NATR = 100 * ATR / close
// (0 when the close is 0, as TA-Lib).
template <bool NORMALIZED>
struct TechAtrOp {
	TECH_HLC_PERIOD_OP(1.0, 14)
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		double period;
		idx_t needed;
		idx_t ranges;
		bool has_close;
		double previous_close;
		double atr;
		void Init(const double *p, idx_t &) {
			period = p[0];
			needed = TechPeriod(p[0]);
		}
		void Reset() {
			ranges = 0;
			has_close = false;
			previous_close = atr = 0.0;
		}
		void Push(double *, const double *in) {
			if (has_close) {
				auto range = TechTrueRange(in[0], in[1], previous_close);
				if (ranges < needed) {
					atr += range;
					if (++ranges == needed) {
						atr /= period;
					}
				} else {
					atr = (atr * (period - 1.0) + range) / period;
				}
			}
			has_close = true;
			previous_close = in[2];
		}
		bool Value(const double *, double *out) const {
			if (ranges < needed) {
				return false;
			}
			if (NORMALIZED) {
				out[0] = previous_close != 0.0 ? (atr / previous_close) * 100.0 : 0.0;
			} else {
				out[0] = atr;
			}
			return true;
		}
	};
};

struct TechAtrIndicatorOp : public TechAtrOp<false> {
	static constexpr const char *NAME = "fin_atr";
};

struct TechNatrOp : public TechAtrOp<true> {
	static constexpr const char *NAME = "fin_natr";
};

enum class TechDirectionalKind : uint8_t { PLUS_DM, MINUS_DM, PLUS_DI, MINUS_DI, DX };

// TA-Lib PLUS_DM, MINUS_DM, PLUS_DI, MINUS_DI and DX. DX keeps its previous
// value while it is undefined (0 before the first defined value), as TA-Lib.
// TA-Lib's period-1 DI special case returns a fraction; this returns percent
// for every period.
template <TechDirectionalKind KIND>
struct TechDirectionalOp {
	static constexpr bool DM = KIND == TechDirectionalKind::PLUS_DM || KIND == TechDirectionalKind::MINUS_DM;
	static constexpr idx_t INPUTS = DM ? 2 : 3;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {
		    {"period", 14, TechParamKind::PERIOD, KIND == TechDirectionalKind::DX ? 2.0 : 1.0, TECH_MAX_PERIOD, false}};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechDirectionalStage stage;
		double dx;
		void Init(const double *p, idx_t &) {
			stage.Init(TechPeriod(p[0]));
		}
		void Reset() {
			stage.Reset();
			dx = 0.0;
		}
		void Push(double *, const double *in) {
			// The DM forms take (high, low); the close only feeds the true range.
			auto close = DM ? in[1] : in[2];
			if (stage.Push(in[0], in[1], close) && KIND == TechDirectionalKind::DX && stage.DiReady()) {
				double value;
				if (stage.Dx(value)) {
					dx = value;
				}
			}
		}
		bool Value(const double *, double *out) const {
			switch (KIND) {
			case TechDirectionalKind::PLUS_DM:
				out[0] = stage.plus;
				return stage.DmReady();
			case TechDirectionalKind::MINUS_DM:
				out[0] = stage.minus;
				return stage.DmReady();
			case TechDirectionalKind::PLUS_DI:
				out[0] = stage.PlusDi();
				return stage.DiReady();
			case TechDirectionalKind::MINUS_DI:
				out[0] = stage.MinusDi();
				return stage.DiReady();
			default:
				out[0] = dx;
				return stage.DiReady();
			}
		}
	};
};

struct TechPlusDmOp : public TechDirectionalOp<TechDirectionalKind::PLUS_DM> {
	static constexpr const char *NAME = "fin_plus_dm";
};
struct TechMinusDmOp : public TechDirectionalOp<TechDirectionalKind::MINUS_DM> {
	static constexpr const char *NAME = "fin_minus_dm";
};
struct TechPlusDiOp : public TechDirectionalOp<TechDirectionalKind::PLUS_DI> {
	static constexpr const char *NAME = "fin_plus_di";
};
struct TechMinusDiOp : public TechDirectionalOp<TechDirectionalKind::MINUS_DI> {
	static constexpr const char *NAME = "fin_minus_di";
};
struct TechDxOp : public TechDirectionalOp<TechDirectionalKind::DX> {
	static constexpr const char *NAME = "fin_dx";
};

// TA-Lib ADX: seeded with the mean of the first `period` DX steps (from change
// `period`), then ADX = (ADX * (period - 1) + DX) / period. Steps where DX is
// undefined leave ADX unchanged (and add nothing to the seed), as TA-Lib.
// ADXR = (ADX + ADX `period - 1` rows earlier) / 2 (TA-Lib ADXR).
template <bool RATING>
struct TechAdxOp {
	TECH_HLC_PERIOD_OP(2.0, 14)
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechDirectionalStage stage;
		TechRing history;
		double period;
		idx_t needed;
		idx_t steps;
		double adx;
		void Init(const double *p, idx_t &cursor) {
			stage.Init(TechPeriod(p[0]));
			period = p[0];
			needed = TechPeriod(p[0]);
			if (RATING) {
				history.Init(cursor, needed);
			}
		}
		void Reset() {
			stage.Reset();
			if (RATING) {
				history.Clear();
			}
			steps = 0;
			adx = 0.0;
		}
		void Push(double *buffer, const double *in) {
			if (!stage.Push(in[0], in[1], in[2]) || !stage.DiReady()) {
				return;
			}
			double dx;
			auto defined = stage.Dx(dx);
			if (steps < needed) {
				if (defined) {
					adx += dx;
				}
				if (++steps == needed) {
					adx /= period;
				}
			} else if (defined) {
				adx = (adx * (period - 1.0) + dx) / period;
			}
			if (RATING && steps >= needed) {
				history.Push(buffer, adx);
			}
		}
		bool Value(const double *buffer, double *out) const {
			if (steps < needed) {
				return false;
			}
			if (!RATING) {
				out[0] = adx;
				return true;
			}
			if (!history.Full()) {
				return false;
			}
			out[0] = (history.Newest(buffer) + history.At(buffer, 0)) / 2.0;
			return true;
		}
	};
};

struct TechAdxIndicatorOp : public TechAdxOp<false> {
	static constexpr const char *NAME = "fin_adx";
};

struct TechAdxrOp : public TechAdxOp<true> {
	static constexpr const char *NAME = "fin_adxr";
};

// TA-Lib MFI over the last `period` typical-price changes: money flow TP * V is
// positive when TP rises, negative when it falls, ignored when unchanged.
// MFI = 100 * positive / (positive + negative); 0 without any flow (TA-Lib).
struct TechMfiOp {
	static constexpr const char *NAME = "fin_mfi";
	static constexpr idx_t INPUTS = 4;
	static constexpr idx_t PARAM_COUNT = 1;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD2_PARAM("period", 14)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(p[0]) + 1;
	}
	struct Kernel {
		TechRing positive;
		TechRing negative;
		bool has_previous;
		double previous;
		void Init(const double *p, idx_t &cursor) {
			positive.Init(cursor, TechPeriod(p[0]));
			negative.Init(cursor, TechPeriod(p[0]));
		}
		void Reset() {
			positive.Clear();
			negative.Clear();
			has_previous = false;
			previous = 0.0;
		}
		void Push(double *buffer, const double *in) {
			auto typical = (in[0] + in[1] + in[2]) / 3.0;
			if (has_previous) {
				auto flow = typical * in[3];
				positive.Push(buffer, typical > previous ? flow : 0.0);
				negative.Push(buffer, typical < previous ? flow : 0.0);
			}
			has_previous = true;
			previous = typical;
		}
		bool Value(const double *buffer, double *out) const {
			if (!positive.Full()) {
				return false;
			}
			auto up = positive.Sum(buffer);
			auto total = up + negative.Sum(buffer);
			out[0] = total != 0.0 ? 100.0 * (up / total) : 0.0;
			return true;
		}
	};
};

// TA-Lib ULTOSC: buying pressure BP = C - min(L, C[-1]) and true range over the
// three periods (sorted ascending, weights 4, 2, 1):
// 100 * (4 BP1/TR1 + 2 BP2/TR2 + BP3/TR3) / 7; a zero TR sum drops its term.
struct TechUltoscOp {
	static constexpr const char *NAME = "fin_ultosc";
	static constexpr idx_t INPUTS = 3;
	static constexpr idx_t PARAM_COUNT = 3;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("short", 7), TECH_PERIOD_PARAM("medium", 14),
		                                      TECH_PERIOD_PARAM("long", 28)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *p) {
		return TechPeriod(std::max(p[0], std::max(p[1], p[2]))) + 1;
	}
	struct Kernel {
		idx_t periods[3];
		TechRing pressure;
		TechRing range;
		bool has_close;
		double previous_close;
		void Init(const double *p, idx_t &cursor) {
			for (idx_t i = 0; i < 3; i++) {
				periods[i] = TechPeriod(p[i]);
			}
			std::sort(periods, periods + 3);
			pressure.Init(cursor, periods[2]);
			range.Init(cursor, periods[2]);
		}
		void Reset() {
			pressure.Clear();
			range.Clear();
			has_close = false;
			previous_close = 0.0;
		}
		void Push(double *buffer, const double *in) {
			if (has_close) {
				auto true_low = std::min(in[1], previous_close);
				auto true_high = std::max(in[0], previous_close);
				pressure.Push(buffer, in[2] - true_low);
				range.Push(buffer, true_high - true_low);
			}
			has_close = true;
			previous_close = in[2];
		}
		bool Value(const double *buffer, double *out) const {
			if (!range.Full()) {
				return false;
			}
			static const double weights[] = {4.0, 2.0, 1.0};
			double total = 0.0;
			for (idx_t k = 0; k < 3; k++) {
				double bp = 0.0;
				double tr = 0.0;
				for (idx_t i = range.size - periods[k]; i < range.size; i++) {
					bp += pressure.At(buffer, i);
					tr += range.At(buffer, i);
				}
				if (tr != 0.0) {
					total += weights[k] * (bp / tr);
				}
			}
			out[0] = 100.0 * (total / 7.0);
			return true;
		}
	};
};

// TA-Lib OBV: starts at the first row's volume, then adds the volume when the
// close rises and subtracts it when the close falls.
struct TechObvOp {
	static constexpr const char *NAME = "fin_obv";
	static constexpr idx_t INPUTS = 2;
	static constexpr idx_t PARAM_COUNT = 0;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		return nullptr;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		bool seen;
		double previous;
		double obv;
		void Init(const double *, idx_t &) {
		}
		void Reset() {
			seen = false;
			previous = obv = 0.0;
		}
		void Push(double *, const double *in) {
			if (!seen) {
				obv = in[1];
			} else if (in[0] > previous) {
				obv += in[1];
			} else if (in[0] < previous) {
				obv -= in[1];
			}
			seen = true;
			previous = in[0];
		}
		bool Value(const double *, double *out) const {
			out[0] = obv;
			return seen;
		}
	};
};

// Chaikin money-flow contribution of one bar: ((C - L) - (H - C)) / (H - L) * V,
// 0 when H <= L (TA-Lib AD).
static double TechMoneyFlowVolume(double high, double low, double close, double volume) {
	auto range = high - low;
	return range > 0.0 ? (((close - low) - (high - close)) / range) * volume : 0.0;
}

// TA-Lib ADOSC: EMA(AD, fast) - EMA(AD, slow) with k = 2 / (period + 1), both
// EMAs seeded with the first AD value; first value at row max(fast, slow) - 1.
struct TechAdoscOp {
	static constexpr const char *NAME = "fin_adosc";
	static constexpr idx_t INPUTS = 4;
	static constexpr idx_t PARAM_COUNT = 2;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD2_PARAM("fast", 3), TECH_PERIOD2_PARAM("slow", 10)};
		return specs;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		double fast_k;
		double slow_k;
		idx_t needed;
		idx_t seen;
		double ad;
		double fast;
		double slow;
		void Init(const double *p, idx_t &) {
			fast_k = 2.0 / (p[0] + 1.0);
			slow_k = 2.0 / (p[1] + 1.0);
			needed = TechPeriod(std::max(p[0], p[1]));
		}
		void Reset() {
			seen = 0;
			ad = fast = slow = 0.0;
		}
		void Push(double *, const double *in) {
			ad += TechMoneyFlowVolume(in[0], in[1], in[2], in[3]);
			if (seen == 0) {
				fast = slow = ad;
			} else {
				fast = fast_k * ad + (1.0 - fast_k) * fast;
				slow = slow_k * ad + (1.0 - slow_k) * slow;
			}
			seen++;
		}
		bool Value(const double *, double *out) const {
			out[0] = fast - slow;
			return seen >= needed;
		}
	};
};

// Roll (1984) effective spread 2 * sqrt(-cov(dP_t, dP_{t-1})) from the sample
// (n - 1) covariance of consecutive price changes. NULL when the serial
// covariance is not negative or fewer than two change pairs exist (four prices).
struct TechRollSpreadOp {
	static constexpr const char *NAME = "fin_roll_spread";
	static constexpr idx_t INPUTS = 1;
	static constexpr idx_t PARAM_COUNT = 0;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		return nullptr;
	}
	static void Validate(const char *, const double *) {
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		idx_t prices;
		double previous_price;
		double previous_change;
		double pairs;
		double mean_x;
		double mean_y;
		double comoment;
		void Init(const double *, idx_t &) {
		}
		void Reset() {
			prices = 0;
			previous_price = previous_change = 0.0;
			pairs = mean_x = mean_y = comoment = 0.0;
		}
		void Push(double *, const double *in) {
			auto price = in[0];
			if (prices > 0) {
				auto change = price - previous_price;
				if (prices > 1) {
					// Welford co-moment update for the pair (change, previous change).
					pairs += 1.0;
					auto dx = change - mean_x;
					mean_x += dx / pairs;
					mean_y += (previous_change - mean_y) / pairs;
					comoment += dx * (previous_change - mean_y);
				}
				previous_change = change;
			}
			previous_price = price;
			prices++;
		}
		bool Value(const double *, double *out) const {
			if (pairs < 2.0) {
				return false;
			}
			auto covariance = comoment / (pairs - 1.0);
			if (!(covariance < 0.0)) {
				return false;
			}
			out[0] = 2.0 * std::sqrt(-covariance);
			return true;
		}
	};
};

// VPIN (Easley, Lopez de Prado and O'Hara 2012): rows fill equal-volume buckets
// of `bucket_volume`; a row that crosses a bucket boundary is split pro rata
// (its signed volume scaled by the share of its volume in each bucket). VPIN =
// sum of |buy - sell| = |signed volume| over the last `buckets` completed
// buckets / (buckets * bucket_volume). NULL until `buckets` buckets complete.
struct TechVpinOp {
	static constexpr const char *NAME = "fin_vpin";
	static constexpr idx_t INPUTS = 2;
	static constexpr idx_t PARAM_COUNT = 2;
	TECH_NO_FIELDS
	static const TechParamSpec *Params() {
		static const TechParamSpec specs[] = {TECH_PERIOD_PARAM("buckets", 50),
		                                      {"bucket_volume", 0.0, TechParamKind::REAL, 0.0, 1e300, true}};
		return specs;
	}
	static void Validate(const char *name, const double *p) {
		if (!(p[1] > 0.0) || !std::isfinite(p[1])) {
			throw InvalidInputException("%s: bucket_volume is required and must be positive: use %s(signed_volume, "
			                            "volume, buckets, bucket_volume ORDER BY ts)",
			                            name, name);
		}
	}
	static idx_t Memory(const double *) {
		return 0;
	}
	struct Kernel {
		TechRing imbalances;
		idx_t buckets;
		double bucket_volume;
		double filled;
		double imbalance;
		bool invalid;
		void Init(const double *p, idx_t &cursor) {
			buckets = TechPeriod(p[0]);
			bucket_volume = p[1];
			imbalances.Init(cursor, buckets);
		}
		void Reset() {
			imbalances.Clear();
			filled = imbalance = 0.0;
			invalid = false;
		}
		void Push(double *buffer, const double *in) {
			auto signed_volume = in[0];
			auto volume = in[1];
			if (volume < 0.0 || std::abs(signed_volume) > volume * (1.0 + 1e-12)) {
				invalid = true;
				return;
			}
			if (volume == 0.0) {
				return;
			}
			auto share = signed_volume / volume;
			auto remaining = volume;
			while (remaining > 0.0) {
				auto room = bucket_volume - filled;
				if (remaining < room) {
					filled += remaining;
					imbalance += share * remaining;
					return;
				}
				imbalance += share * room;
				imbalances.Push(buffer, std::abs(imbalance));
				filled = imbalance = 0.0;
				remaining -= room;
				// Whole buckets inside one large row all have the row's imbalance;
				// only the last `buckets` of them can be retained.
				auto whole = std::floor(remaining / bucket_volume);
				if (whole >= 1.0) {
					auto keep = std::min(whole, static_cast<double>(buckets));
					for (idx_t i = 0; i < static_cast<idx_t>(keep); i++) {
						imbalances.Push(buffer, std::abs(share) * bucket_volume);
					}
					remaining -= whole * bucket_volume;
				}
			}
		}
		bool Value(const double *buffer, double *out) const {
			if (invalid || !imbalances.Full()) {
				return false;
			}
			out[0] = imbalances.Sum(buffer) / (static_cast<double>(buckets) * bucket_volume);
			return true;
		}
	};
};

static void RegisterTechnicalVolumeIndicators(ExtensionLoader &loader) {
	RegisterTechnicalIndicator<TechTrueRangeOp>(loader);
	RegisterTechnicalIndicator<TechAtrIndicatorOp>(loader);
	RegisterTechnicalIndicator<TechNatrOp>(loader);
	RegisterTechnicalIndicator<TechPlusDmOp>(loader);
	RegisterTechnicalIndicator<TechMinusDmOp>(loader);
	RegisterTechnicalIndicator<TechPlusDiOp>(loader);
	RegisterTechnicalIndicator<TechMinusDiOp>(loader);
	RegisterTechnicalIndicator<TechDxOp>(loader);
	RegisterTechnicalIndicator<TechAdxIndicatorOp>(loader);
	RegisterTechnicalIndicator<TechAdxrOp>(loader);
	RegisterTechnicalIndicator<TechMfiOp>(loader);
	RegisterTechnicalIndicator<TechUltoscOp>(loader);
	RegisterTechnicalIndicator<TechObvOp>(loader);
	RegisterTechnicalIndicator<TechAdoscOp>(loader);
	RegisterTechnicalIndicator<TechRollSpreadOp>(loader);
	RegisterTechnicalIndicator<TechVpinOp>(loader);
}
