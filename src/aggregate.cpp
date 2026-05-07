#include "finance/finance_extension.hpp"

#include "duckdb/common/exception.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/function/aggregate_function.hpp"

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

namespace duckdb {
namespace {

constexpr double DEFAULT_ANNUALIZATION = 252.0;
constexpr double DEFAULT_EWMA_LAMBDA = 0.94;

struct SortinoState {
	idx_t count;
	double sum_excess;
	double downside_sq;
	double annualization;
};

struct SortinoOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.count = 0;
		state.sum_excess = 0.0;
		state.downside_sq = 0.0;
		state.annualization = DEFAULT_ANNUALIZATION;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		state.count++;
		state.sum_excess += value;
		if (value < 0.0) {
			state.downside_sq += value * value;
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &, idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input));
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &) {
		UpdateValue(state, static_cast<double>(input));
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (source.count == 0) {
			return;
		}
		if (target.count == 0) {
			target.annualization = source.annualization;
		}
		target.count += source.count;
		target.sum_excess += source.sum_excess;
		target.downside_sq += source.downside_sq;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (state.count == 0 || state.downside_sq <= 0.0) {
			finalize_data.ReturnNull();
			return;
		}
		auto mean = state.sum_excess / static_cast<double>(state.count);
		auto downside = std::sqrt(state.downside_sq / static_cast<double>(state.count));
		target = mean / downside * std::sqrt(state.annualization);
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct SortinoWithMAROperation : public SortinoOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double mar) {
		SortinoOperation::UpdateValue(state, value - mar / DEFAULT_ANNUALIZATION);
	}

	template <class INPUT_TYPE, class MAR_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, const MAR_TYPE &mar, AggregateBinaryInput &,
	                              idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input), static_cast<double>(mar));
		}
	}

	template <class INPUT_TYPE, class MAR_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const MAR_TYPE &mar, AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(input), static_cast<double>(mar));
	}
};

struct SortinoWithMARAnnualizationOperation : public SortinoOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double mar, double annualization) {
		if (annualization <= 0.0 || !std::isfinite(annualization)) {
			throw InvalidInputException("Sortino annualization must be positive and finite");
		}
		state.annualization = annualization;
		SortinoOperation::UpdateValue(state, value - mar / annualization);
	}
};

struct EWMAState {
	bool isset;
	double variance;
	double lambda;
	double annualization;
};

template <bool RETURN_VOL>
struct EWMAOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.variance = 0.0;
		state.lambda = DEFAULT_EWMA_LAMBDA;
		state.annualization = DEFAULT_ANNUALIZATION;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		auto square = value * value;
		if (!state.isset) {
			state.variance = square;
			state.isset = true;
			return;
		}
		state.variance = state.lambda * state.variance + (1.0 - state.lambda) * square;
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &, idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input));
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &) {
		UpdateValue(state, static_cast<double>(input));
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset) {
			return;
		}
		if (!target.isset) {
			target = source;
			return;
		}
		target.variance = target.lambda * target.variance + (1.0 - target.lambda) * source.variance;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset) {
			finalize_data.ReturnNull();
			return;
		}
		auto annualized = state.variance * state.annualization;
		target = RETURN_VOL ? std::sqrt(annualized) : annualized;
	}

	static bool IgnoreNull() {
		return true;
	}
};

template <bool RETURN_VOL>
struct EWMAWithLambdaOperation : public EWMAOperation<RETURN_VOL> {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double lambda) {
		if (lambda <= 0.0 || lambda >= 1.0 || !std::isfinite(lambda)) {
			throw InvalidInputException("EWMA lambda must be finite and in (0, 1)");
		}
		state.lambda = lambda;
		EWMAOperation<RETURN_VOL>::UpdateValue(state, value);
	}

	template <class INPUT_TYPE, class LAMBDA_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, const LAMBDA_TYPE &lambda, AggregateBinaryInput &,
	                              idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input), static_cast<double>(lambda));
		}
	}

	template <class INPUT_TYPE, class LAMBDA_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const LAMBDA_TYPE &lambda, AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(input), static_cast<double>(lambda));
	}
};

template <bool RETURN_VOL>
struct EWMAWithLambdaAnnualizationOperation : public EWMAOperation<RETURN_VOL> {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double lambda, double annualization) {
		if (lambda <= 0.0 || lambda >= 1.0 || !std::isfinite(lambda)) {
			throw InvalidInputException("EWMA lambda must be finite and in (0, 1)");
		}
		if (annualization <= 0.0 || !std::isfinite(annualization)) {
			throw InvalidInputException("EWMA annualization must be positive and finite");
		}
		state.lambda = lambda;
		state.annualization = annualization;
		EWMAOperation<RETURN_VOL>::UpdateValue(state, value);
	}
};

struct RSIState {
	bool isset;
	double first;
	double last;
	double gain_sum;
	double loss_sum;
	idx_t changes;
};

struct RSIOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.first = 0.0;
		state.last = 0.0;
		state.gain_sum = 0.0;
		state.loss_sum = 0.0;
		state.changes = 0;
	}

	static void AddDiff(RSIState &state, double diff) {
		if (diff > 0.0) {
			state.gain_sum += diff;
		} else {
			state.loss_sum -= diff;
		}
		state.changes++;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (!state.isset) {
			state.isset = true;
			state.first = value;
			state.last = value;
			return;
		}
		AddDiff(state, value - state.last);
		state.last = value;
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &, idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input));
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &) {
		UpdateValue(state, static_cast<double>(input));
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset) {
			return;
		}
		if (!target.isset) {
			target = source;
			return;
		}
		AddDiff(target, source.first - target.last);
		target.gain_sum += source.gain_sum;
		target.loss_sum += source.loss_sum;
		target.changes += source.changes;
		target.last = source.last;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.changes == 0) {
			finalize_data.ReturnNull();
			return;
		}
		if (state.loss_sum == 0.0) {
			target = 100.0;
			return;
		}
		auto avg_gain = state.gain_sum / static_cast<double>(state.changes);
		auto avg_loss = state.loss_sum / static_cast<double>(state.changes);
		auto rs = avg_gain / avg_loss;
		target = 100.0 - 100.0 / (1.0 + rs);
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct RSIWithPeriodOperation : public RSIOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, int32_t period) {
		if (period <= 0) {
			throw InvalidInputException("RSI period must be positive");
		}
		RSIOperation::UpdateValue(state, value);
	}

	template <class INPUT_TYPE, class PERIOD_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, const PERIOD_TYPE &period, AggregateBinaryInput &,
	                              idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input), static_cast<int32_t>(period));
		}
	}

	template <class INPUT_TYPE, class PERIOD_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const PERIOD_TYPE &period, AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(input), static_cast<int32_t>(period));
	}
};

struct DrawdownState {
	bool isset;
	double nav;
	double peak;
	double current_drawdown;
	double min_drawdown;
	double sum_drawdown;
	double sum_drawdown_sq;
	idx_t count;
	idx_t current_duration;
	idx_t max_duration;
};

struct DrawdownOperationBase {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.nav = 1.0;
		state.peak = 1.0;
		state.current_drawdown = 0.0;
		state.min_drawdown = 0.0;
		state.sum_drawdown = 0.0;
		state.sum_drawdown_sq = 0.0;
		state.count = 0;
		state.current_duration = 0;
		state.max_duration = 0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value, double initial_nav = 1.0) {
		if (!std::isfinite(value) || value < -1.0) {
			throw InvalidInputException("Drawdown returns must be finite and greater than or equal to -1");
		}
		if (initial_nav <= 0.0 || !std::isfinite(initial_nav)) {
			throw InvalidInputException("Initial NAV must be positive and finite");
		}
		if (!state.isset) {
			state.isset = true;
			state.nav = initial_nav;
			state.peak = initial_nav;
		}
		state.nav *= 1.0 + value;
		state.peak = std::max(state.peak, state.nav);
		state.current_drawdown = state.peak == 0.0 ? 0.0 : state.nav / state.peak - 1.0;
		state.min_drawdown = std::min(state.min_drawdown, state.current_drawdown);
		state.sum_drawdown += state.current_drawdown;
		state.sum_drawdown_sq += state.current_drawdown * state.current_drawdown;
		state.count++;
		if (state.current_drawdown < 0.0) {
			state.current_duration++;
			state.max_duration = std::max(state.max_duration, state.current_duration);
		} else {
			state.current_duration = 0;
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &, idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input));
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &) {
		UpdateValue(state, static_cast<double>(input));
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset) {
			return;
		}
		if (!target.isset) {
			target = source;
			return;
		}
		target.min_drawdown = std::min(target.min_drawdown, source.min_drawdown);
		target.sum_drawdown += source.sum_drawdown;
		target.sum_drawdown_sq += source.sum_drawdown_sq;
		target.count += source.count;
		target.max_duration = std::max(target.max_duration, source.max_duration);
		target.current_duration = source.current_duration;
		target.nav = source.nav;
		target.peak = std::max(target.peak, source.peak);
		target.current_drawdown = source.current_drawdown;
	}

	static bool IgnoreNull() {
		return true;
	}
};

template <class FINALIZE_OPERATION>
struct DrawdownWithInitialNavOperation : public FINALIZE_OPERATION {
	template <class INPUT_TYPE, class NAV_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const NAV_TYPE &initial_nav, AggregateBinaryInput &) {
		DrawdownOperationBase::UpdateValue(state, static_cast<double>(input), static_cast<double>(initial_nav));
	}
};

struct CurrentDrawdownOperation : public DrawdownOperationBase {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.current_drawdown;
	}
};

struct MaxDrawdownOperation : public DrawdownOperationBase {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.min_drawdown;
	}
};

struct AvgDrawdownOperation : public DrawdownOperationBase {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.sum_drawdown / static_cast<double>(state.count);
	}
};

struct UlcerIndexOperation : public DrawdownOperationBase {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = std::sqrt(state.sum_drawdown_sq / static_cast<double>(state.count));
	}
};

struct DrawdownDurationOperation : public DrawdownOperationBase {
	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0) {
			finalize_data.ReturnNull();
			return;
		}
		target = static_cast<int64_t>(state.max_duration);
	}
};

struct OutlierCountState {
	vector<double> *values;
	double threshold;
};

struct OutlierCountOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<double>();
		state.threshold = 3.0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (std::isfinite(value)) {
			state.values->push_back(value);
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &, idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input));
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &) {
		UpdateValue(state, static_cast<double>(input));
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.values || source.values->empty()) {
			return;
		}
		target.threshold = source.threshold;
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &) {
		auto n = state.values ? NumericCast<idx_t>(state.values->size()) : idx_t(0);
		if (n < 2) {
			target = 0;
			return;
		}
		double sum = 0.0;
		for (auto value : *state.values) {
			sum += value;
		}
		auto mean = sum / static_cast<double>(n);
		double sum_sq = 0.0;
		for (auto value : *state.values) {
			auto diff = value - mean;
			sum_sq += diff * diff;
		}
		auto variance = sum_sq / static_cast<double>(n - 1);
		if (variance <= 0.0) {
			target = 0;
			return;
		}
		auto stddev = std::sqrt(variance);
		int64_t outliers = 0;
		for (auto value : *state.values) {
			if (std::abs(value - mean) / stddev > state.threshold) {
				outliers++;
			}
		}
		target = outliers;
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.values;
		state.values = nullptr;
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct OutlierCountWithThresholdOperation : public OutlierCountOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, double threshold) {
		if (threshold <= 0.0 || !std::isfinite(threshold)) {
			throw InvalidInputException("Outlier threshold must be positive and finite");
		}
		state.threshold = threshold;
		OutlierCountOperation::UpdateValue(state, value);
	}

	template <class INPUT_TYPE, class THRESHOLD_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, const THRESHOLD_TYPE &threshold,
	                      AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(input), static_cast<double>(threshold));
	}
};

struct OutlierCountWithMethodOperation : public OutlierCountOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double value, const string &method, double threshold) {
		if (StringUtil::Lower(method) != "zscore") {
			throw InvalidInputException("fin_outlier_count currently supports method='zscore'");
		}
		OutlierCountWithThresholdOperation::UpdateValue(state, value, threshold);
	}
};

struct QuantileSpreadState {
	vector<std::pair<double, double>> *values;
	int32_t buckets;
};

struct QuantileSpreadOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.values = new vector<std::pair<double, double>>();
		state.buckets = 5;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double factor, double forward_return, double buckets = 5.0) {
		if (!std::isfinite(factor) || !std::isfinite(forward_return)) {
			return;
		}
		auto bucket_count = static_cast<int32_t>(std::llround(buckets));
		if (bucket_count <= 1) {
			throw InvalidInputException("Quantile spread buckets must be greater than 1");
		}
		state.buckets = bucket_count;
		state.values->push_back({factor, forward_return});
	}

	template <class INPUT_TYPE, class RETURN_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &factor, const RETURN_TYPE &forward_return,
	                      AggregateBinaryInput &) {
		UpdateValue(state, static_cast<double>(factor), static_cast<double>(forward_return));
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.values || source.values->empty()) {
			return;
		}
		target.buckets = source.buckets;
		target.values->insert(target.values->end(), source.values->begin(), source.values->end());
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		auto n = state.values ? NumericCast<idx_t>(state.values->size()) : idx_t(0);
		if (n == 0) {
			finalize_data.ReturnNull();
			return;
		}
		std::sort(state.values->begin(), state.values->end(),
		          [](const auto &lhs, const auto &rhs) { return lhs.first < rhs.first; });
		auto bucket_size = std::max<idx_t>(1, (n + NumericCast<idx_t>(state.buckets) - 1) /
		                                          NumericCast<idx_t>(state.buckets));
		bucket_size = std::min(bucket_size, n);
		double bottom_sum = 0.0;
		double top_sum = 0.0;
		for (idx_t i = 0; i < bucket_size; i++) {
			bottom_sum += (*state.values)[i].second;
			top_sum += (*state.values)[n - bucket_size + i].second;
		}
		target = top_sum / static_cast<double>(bucket_size) - bottom_sum / static_cast<double>(bucket_size);
	}

	template <class STATE>
	static void Destroy(STATE &state, AggregateInputData &) {
		delete state.values;
		state.values = nullptr;
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct QuantileSpreadWithBucketsOperation : public QuantileSpreadOperation {
	template <class STATE>
	static void UpdateValue(STATE &state, double factor, double forward_return, double buckets) {
		QuantileSpreadOperation::UpdateValue(state, factor, forward_return, buckets);
	}
};

struct IVRangeState {
	bool isset;
	double min_iv;
	double max_iv;
	double last_iv;
	idx_t count;
};

template <bool PERCENTILE>
struct IVRangeOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.isset = false;
		state.min_iv = 0.0;
		state.max_iv = 0.0;
		state.last_iv = 0.0;
		state.count = 0;
	}

	template <class STATE>
	static void UpdateValue(STATE &state, double value) {
		if (!state.isset) {
			state.isset = true;
			state.min_iv = value;
			state.max_iv = value;
		}
		state.min_iv = std::min(state.min_iv, value);
		state.max_iv = std::max(state.max_iv, value);
		state.last_iv = value;
		state.count++;
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &, idx_t count) {
		for (idx_t i = 0; i < count; i++) {
			UpdateValue(state, static_cast<double>(input));
		}
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &input, AggregateUnaryInput &) {
		UpdateValue(state, static_cast<double>(input));
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset) {
			return;
		}
		if (!target.isset) {
			target = source;
			return;
		}
		target.min_iv = std::min(target.min_iv, source.min_iv);
		target.max_iv = std::max(target.max_iv, source.max_iv);
		target.last_iv = source.last_iv;
		target.count += source.count;
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset || state.count == 0 || state.max_iv == state.min_iv) {
			finalize_data.ReturnNull();
			return;
		}
		auto rank = (state.last_iv - state.min_iv) / (state.max_iv - state.min_iv);
		target = PERCENTILE ? std::min(1.0, std::max(0.0, rank)) : rank;
	}

	static bool IgnoreNull() {
		return true;
	}
};

template <class STATE, class OP>
static AggregateFunction UnaryDoubleAggregate(const string &name) {
	auto result = AggregateFunction::UnaryAggregate<STATE, double, double, OP>(LogicalType::DOUBLE, LogicalType::DOUBLE);
	result.name = name;
	return result;
}

template <class STATE, class B_TYPE, class OP>
static AggregateFunction BinaryDoubleAggregate(const string &name, const LogicalType &b_type) {
	auto result =
	    AggregateFunction::BinaryAggregate<STATE, double, B_TYPE, double, OP>(LogicalType::DOUBLE, b_type,
	                                                                         LogicalType::DOUBLE);
	result.name = name;
	return result;
}

template <class STATE, class OP>
static AggregateFunction UnaryBigintAggregate(const string &name) {
	auto result = AggregateFunction::UnaryAggregate<STATE, double, int64_t, OP>(LogicalType::DOUBLE, LogicalType::BIGINT);
	result.name = name;
	return result;
}

template <class STATE, class B_TYPE, class RESULT_TYPE, class OP>
static AggregateFunction BinaryAggregate(const string &name, const LogicalType &b_type, const LogicalType &return_type) {
	auto result =
	    AggregateFunction::BinaryAggregate<STATE, double, B_TYPE, RESULT_TYPE, OP>(LogicalType::DOUBLE, b_type,
	                                                                              return_type);
	result.name = name;
	return result;
}

template <class STATE, class A_TYPE, class B_TYPE, class C_TYPE, class OP>
static void TernaryScatterUpdate(Vector inputs[], AggregateInputData &, idx_t input_count, Vector &states,
                                 idx_t count) {
	D_ASSERT(input_count == 3);
	UnifiedVectorFormat adata;
	UnifiedVectorFormat bdata;
	UnifiedVectorFormat cdata;
	UnifiedVectorFormat sdata;
	inputs[0].ToUnifiedFormat(count, adata);
	inputs[1].ToUnifiedFormat(count, bdata);
	inputs[2].ToUnifiedFormat(count, cdata);
	states.ToUnifiedFormat(count, sdata);

	auto a_values = UnifiedVectorFormat::GetData<A_TYPE>(adata);
	auto b_values = UnifiedVectorFormat::GetData<B_TYPE>(bdata);
	auto c_values = UnifiedVectorFormat::GetData<C_TYPE>(cdata);
	auto state_values = UnifiedVectorFormat::GetData<STATE *>(sdata);
	for (idx_t i = 0; i < count; i++) {
		auto aidx = adata.sel->get_index(i);
		auto bidx = bdata.sel->get_index(i);
		auto cidx = cdata.sel->get_index(i);
		if (!adata.validity.RowIsValid(aidx) || !bdata.validity.RowIsValid(bidx) || !cdata.validity.RowIsValid(cidx)) {
			continue;
		}
		auto sidx = sdata.sel->get_index(i);
		OP::UpdateValue(*state_values[sidx], static_cast<double>(a_values[aidx]), static_cast<double>(b_values[bidx]),
		                static_cast<double>(c_values[cidx]));
	}
}

template <class STATE, class A_TYPE, class B_TYPE, class C_TYPE, class OP>
static void TernarySimpleUpdate(Vector inputs[], AggregateInputData &, idx_t input_count, data_ptr_t state,
                                idx_t count) {
	D_ASSERT(input_count == 3);
	UnifiedVectorFormat adata;
	UnifiedVectorFormat bdata;
	UnifiedVectorFormat cdata;
	inputs[0].ToUnifiedFormat(count, adata);
	inputs[1].ToUnifiedFormat(count, bdata);
	inputs[2].ToUnifiedFormat(count, cdata);

	auto a_values = UnifiedVectorFormat::GetData<A_TYPE>(adata);
	auto b_values = UnifiedVectorFormat::GetData<B_TYPE>(bdata);
	auto c_values = UnifiedVectorFormat::GetData<C_TYPE>(cdata);
	auto state_value = reinterpret_cast<STATE *>(state);
	for (idx_t i = 0; i < count; i++) {
		auto aidx = adata.sel->get_index(i);
		auto bidx = bdata.sel->get_index(i);
		auto cidx = cdata.sel->get_index(i);
		if (!adata.validity.RowIsValid(aidx) || !bdata.validity.RowIsValid(bidx) || !cdata.validity.RowIsValid(cidx)) {
			continue;
		}
		OP::UpdateValue(*state_value, static_cast<double>(a_values[aidx]), static_cast<double>(b_values[bidx]),
		                static_cast<double>(c_values[cidx]));
	}
}

template <class STATE, class A_TYPE, class B_TYPE, class C_TYPE, class OP>
static AggregateFunction TernaryDoubleAggregate(const string &name, const LogicalType &a_type,
                                                const LogicalType &b_type, const LogicalType &c_type) {
	AggregateFunction result({a_type, b_type, c_type}, LogicalType::DOUBLE, AggregateFunction::StateSize<STATE>,
	                         AggregateFunction::StateInitialize<STATE, OP>,
	                         TernaryScatterUpdate<STATE, A_TYPE, B_TYPE, C_TYPE, OP>,
	                         AggregateFunction::StateCombine<STATE, OP>,
	                         AggregateFunction::StateFinalize<STATE, double, OP>,
	                         TernarySimpleUpdate<STATE, A_TYPE, B_TYPE, C_TYPE, OP>);
	result.name = name;
	return result;
}

template <class STATE, class OP>
static void TernaryDoubleVarcharDoubleScatterUpdate(Vector inputs[], AggregateInputData &, idx_t input_count,
                                                    Vector &states, idx_t count) {
	D_ASSERT(input_count == 3);
	UnifiedVectorFormat xdata;
	UnifiedVectorFormat method_data;
	UnifiedVectorFormat threshold_data;
	UnifiedVectorFormat sdata;
	inputs[0].ToUnifiedFormat(count, xdata);
	inputs[1].ToUnifiedFormat(count, method_data);
	inputs[2].ToUnifiedFormat(count, threshold_data);
	states.ToUnifiedFormat(count, sdata);

	auto x_values = UnifiedVectorFormat::GetData<double>(xdata);
	auto method_values = UnifiedVectorFormat::GetData<string_t>(method_data);
	auto threshold_values = UnifiedVectorFormat::GetData<double>(threshold_data);
	auto state_values = UnifiedVectorFormat::GetData<STATE *>(sdata);
	for (idx_t i = 0; i < count; i++) {
		auto xidx = xdata.sel->get_index(i);
		auto midx = method_data.sel->get_index(i);
		auto tidx = threshold_data.sel->get_index(i);
		if (!xdata.validity.RowIsValid(xidx) || !method_data.validity.RowIsValid(midx) ||
		    !threshold_data.validity.RowIsValid(tidx)) {
			continue;
		}
		auto sidx = sdata.sel->get_index(i);
		OP::UpdateValue(*state_values[sidx], x_values[xidx], method_values[midx].GetString(), threshold_values[tidx]);
	}
}

template <class STATE, class OP>
static void TernaryDoubleVarcharDoubleSimpleUpdate(Vector inputs[], AggregateInputData &, idx_t input_count,
                                                   data_ptr_t state, idx_t count) {
	D_ASSERT(input_count == 3);
	UnifiedVectorFormat xdata;
	UnifiedVectorFormat method_data;
	UnifiedVectorFormat threshold_data;
	inputs[0].ToUnifiedFormat(count, xdata);
	inputs[1].ToUnifiedFormat(count, method_data);
	inputs[2].ToUnifiedFormat(count, threshold_data);

	auto x_values = UnifiedVectorFormat::GetData<double>(xdata);
	auto method_values = UnifiedVectorFormat::GetData<string_t>(method_data);
	auto threshold_values = UnifiedVectorFormat::GetData<double>(threshold_data);
	auto state_value = reinterpret_cast<STATE *>(state);
	for (idx_t i = 0; i < count; i++) {
		auto xidx = xdata.sel->get_index(i);
		auto midx = method_data.sel->get_index(i);
		auto tidx = threshold_data.sel->get_index(i);
		if (!xdata.validity.RowIsValid(xidx) || !method_data.validity.RowIsValid(midx) ||
		    !threshold_data.validity.RowIsValid(tidx)) {
			continue;
		}
		OP::UpdateValue(*state_value, x_values[xidx], method_values[midx].GetString(), threshold_values[tidx]);
	}
}

template <class STATE, class OP>
static AggregateFunction TernaryDoubleVarcharDoubleBigintAggregate(const string &name) {
	AggregateFunction result({LogicalType::DOUBLE, LogicalType::VARCHAR, LogicalType::DOUBLE}, LogicalType::BIGINT,
	                         AggregateFunction::StateSize<STATE>,
	                         AggregateFunction::StateInitialize<STATE, OP, AggregateDestructorType::LEGACY>,
	                         TernaryDoubleVarcharDoubleScatterUpdate<STATE, OP>,
	                         AggregateFunction::StateCombine<STATE, OP>,
	                         AggregateFunction::StateFinalize<STATE, int64_t, OP>,
	                         TernaryDoubleVarcharDoubleSimpleUpdate<STATE, OP>, nullptr,
	                         AggregateFunction::StateDestroy<STATE, OP>);
	result.name = name;
	return result;
}

} // namespace

void RegisterFinanceAggregates(ExtensionLoader &loader) {
	AggregateFunctionSet sortino_set("fin_sortino");
	auto sortino = UnaryDoubleAggregate<SortinoState, SortinoOperation>("fin_sortino");
	sortino.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	sortino_set.AddFunction(sortino);
	auto sortino_mar =
	    BinaryDoubleAggregate<SortinoState, double, SortinoWithMAROperation>("fin_sortino", LogicalType::DOUBLE);
	sortino_mar.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	sortino_set.AddFunction(sortino_mar);
	auto sortino_mar_annualization =
	    TernaryDoubleAggregate<SortinoState, double, double, double, SortinoWithMARAnnualizationOperation>(
	        "fin_sortino", LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE);
	sortino_mar_annualization.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	sortino_set.AddFunction(sortino_mar_annualization);
	loader.RegisterFunction(std::move(sortino_set));

	AggregateFunctionSet ewma_variance_set("fin_ewma_variance");
	ewma_variance_set.AddFunction(UnaryDoubleAggregate<EWMAState, EWMAOperation<false>>("fin_ewma_variance"));
	ewma_variance_set.AddFunction(
	    BinaryDoubleAggregate<EWMAState, double, EWMAWithLambdaOperation<false>>("fin_ewma_variance",
	                                                                            LogicalType::DOUBLE));
	ewma_variance_set.AddFunction(
	    TernaryDoubleAggregate<EWMAState, double, double, double, EWMAWithLambdaAnnualizationOperation<false>>(
	        "fin_ewma_variance", LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE));
	loader.RegisterFunction(std::move(ewma_variance_set));

	AggregateFunctionSet ewma_vol_set("fin_ewma_vol");
	ewma_vol_set.AddFunction(UnaryDoubleAggregate<EWMAState, EWMAOperation<true>>("fin_ewma_vol"));
	ewma_vol_set.AddFunction(
	    BinaryDoubleAggregate<EWMAState, double, EWMAWithLambdaOperation<true>>("fin_ewma_vol", LogicalType::DOUBLE));
	ewma_vol_set.AddFunction(
	    TernaryDoubleAggregate<EWMAState, double, double, double, EWMAWithLambdaAnnualizationOperation<true>>(
	        "fin_ewma_vol", LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE));
	loader.RegisterFunction(std::move(ewma_vol_set));

	AggregateFunctionSet rsi_set("fin_rsi");
	rsi_set.AddFunction(UnaryDoubleAggregate<RSIState, RSIOperation>("fin_rsi"));
	rsi_set.AddFunction(BinaryDoubleAggregate<RSIState, int32_t, RSIWithPeriodOperation>("fin_rsi",
	                                                                                    LogicalType::INTEGER));
	loader.RegisterFunction(std::move(rsi_set));

	AggregateFunctionSet current_drawdown_set("fin_drawdown");
	current_drawdown_set.AddFunction(UnaryDoubleAggregate<DrawdownState, CurrentDrawdownOperation>("fin_drawdown"));
	current_drawdown_set.AddFunction(
	    BinaryAggregate<DrawdownState, double, double, DrawdownWithInitialNavOperation<CurrentDrawdownOperation>>(
	        "fin_drawdown", LogicalType::DOUBLE, LogicalType::DOUBLE));
	loader.RegisterFunction(std::move(current_drawdown_set));

	AggregateFunctionSet max_drawdown_set("fin_max_drawdown");
	max_drawdown_set.AddFunction(UnaryDoubleAggregate<DrawdownState, MaxDrawdownOperation>("fin_max_drawdown"));
	max_drawdown_set.AddFunction(
	    BinaryAggregate<DrawdownState, double, double, DrawdownWithInitialNavOperation<MaxDrawdownOperation>>(
	        "fin_max_drawdown", LogicalType::DOUBLE, LogicalType::DOUBLE));
	loader.RegisterFunction(std::move(max_drawdown_set));

	AggregateFunctionSet avg_drawdown_set("fin_avg_drawdown");
	avg_drawdown_set.AddFunction(UnaryDoubleAggregate<DrawdownState, AvgDrawdownOperation>("fin_avg_drawdown"));
	avg_drawdown_set.AddFunction(
	    BinaryAggregate<DrawdownState, double, double, DrawdownWithInitialNavOperation<AvgDrawdownOperation>>(
	        "fin_avg_drawdown", LogicalType::DOUBLE, LogicalType::DOUBLE));
	loader.RegisterFunction(std::move(avg_drawdown_set));

	AggregateFunctionSet drawdown_duration_set("fin_drawdown_duration");
	drawdown_duration_set.AddFunction(
	    UnaryBigintAggregate<DrawdownState, DrawdownDurationOperation>("fin_drawdown_duration"));
	drawdown_duration_set.AddFunction(
	    BinaryAggregate<DrawdownState, double, int64_t, DrawdownWithInitialNavOperation<DrawdownDurationOperation>>(
	        "fin_drawdown_duration", LogicalType::DOUBLE, LogicalType::BIGINT));
	loader.RegisterFunction(std::move(drawdown_duration_set));

	AggregateFunctionSet ulcer_index_set("fin_ulcer_index");
	ulcer_index_set.AddFunction(UnaryDoubleAggregate<DrawdownState, UlcerIndexOperation>("fin_ulcer_index"));
	loader.RegisterFunction(std::move(ulcer_index_set));

	AggregateFunctionSet outlier_count_set("fin_outlier_count");
	auto outlier_count =
	    AggregateFunction::UnaryAggregateDestructor<OutlierCountState, double, int64_t, OutlierCountOperation,
	                                                AggregateDestructorType::LEGACY>(LogicalType::DOUBLE,
	                                                                                 LogicalType::BIGINT);
	outlier_count.name = "fin_outlier_count";
	outlier_count_set.AddFunction(outlier_count);
	auto outlier_count_threshold =
	    BinaryAggregate<OutlierCountState, double, int64_t, OutlierCountWithThresholdOperation>(
	        "fin_outlier_count", LogicalType::DOUBLE, LogicalType::BIGINT);
	outlier_count_threshold.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<OutlierCountState, OutlierCountWithThresholdOperation>);
	outlier_count_set.AddFunction(outlier_count_threshold);
	outlier_count_set.AddFunction(
	    TernaryDoubleVarcharDoubleBigintAggregate<OutlierCountState, OutlierCountWithMethodOperation>(
	        "fin_outlier_count"));
	loader.RegisterFunction(std::move(outlier_count_set));

	AggregateFunctionSet quantile_spread_set("fin_quantile_spread");
	auto quantile_spread =
	    AggregateFunction::BinaryAggregate<QuantileSpreadState, double, double, double, QuantileSpreadOperation,
	                                       AggregateDestructorType::LEGACY>(LogicalType::DOUBLE, LogicalType::DOUBLE,
	                                                                        LogicalType::DOUBLE);
	quantile_spread.name = "fin_quantile_spread";
	quantile_spread.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<QuantileSpreadState, QuantileSpreadOperation>);
	quantile_spread_set.AddFunction(quantile_spread);
	auto quantile_spread_buckets =
	    TernaryDoubleAggregate<QuantileSpreadState, double, double, int32_t, QuantileSpreadWithBucketsOperation>(
	        "fin_quantile_spread", LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER);
	quantile_spread_buckets.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<QuantileSpreadState, QuantileSpreadWithBucketsOperation>);
	quantile_spread_set.AddFunction(quantile_spread_buckets);
	loader.RegisterFunction(std::move(quantile_spread_set));

	auto iv_rank = UnaryDoubleAggregate<IVRangeState, IVRangeOperation<false>>("fin_iv_rank");
	iv_rank.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	loader.RegisterFunction(iv_rank);
	auto iv_percentile = UnaryDoubleAggregate<IVRangeState, IVRangeOperation<true>>("fin_iv_percentile");
	iv_percentile.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	loader.RegisterFunction(iv_percentile);
}

} // namespace duckdb
