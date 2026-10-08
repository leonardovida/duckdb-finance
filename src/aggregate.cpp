#include "finance/finance_extension.hpp"

#include "duckdb/common/exception.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/function/aggregate_function.hpp"
#include "duckdb/common/types/column/column_data_collection.hpp"
#include "duckdb/execution/expression_executor.hpp"
#include "duckdb/planner/expression.hpp"
#include "duckdb/common/serializer/serializer.hpp"
#include "duckdb/common/serializer/deserializer.hpp"

#include <algorithm>
#include <cmath>
#include <deque>
#include <unordered_map>
#include <cstring>
#include <cctype>
#include <limits>
#include <utility>
#include <vector>

namespace duckdb {
namespace {

#include "aggregate/constants.inc"
#include "aggregate/update_helpers.inc"
#include "aggregate/numeric_helpers.inc"
#include "aggregate/risk_common.inc"
#include "aggregate/sortino.inc"
#include "aggregate/ewma.inc"
#include "aggregate/bipower_variation.inc"
#include "aggregate/drawdown.inc"
#include "aggregate/outliers.inc"
#include "aggregate/quantile_spread.inc"
#include "aggregate/weighted_quantile.inc"
#include "aggregate/robust_statistics.inc"
#include "aggregate/iv_range.inc"
#include "aggregate/risk_metrics.inc"
#include "aggregate/helpers.inc"
#include "aggregate/value_at_key.inc"
#include "aggregate/technical.inc"
#include "aggregate/technical_volume.inc"
#include "aggregate/market_volume.inc"

} // namespace

#include "aggregate/register_returns_risk.inc"
#include "aggregate/register.inc"

} // namespace duckdb
