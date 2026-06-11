#include "finance/finance_extension.hpp"

#if __has_include("duckdb/common/identifier.hpp")
#define FINANCE_HAS_DUCKDB_IDENTIFIER 1
#include "duckdb/common/identifier.hpp"
#else
#define FINANCE_HAS_DUCKDB_IDENTIFIER 0
#endif
#include "duckdb/common/exception.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/function/aggregate_function.hpp"

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

namespace duckdb {
namespace {

#if FINANCE_HAS_DUCKDB_IDENTIFIER
static Identifier FinanceFunctionName(const string &name) {
	return Identifier(name);
}
#else
static string FinanceFunctionName(const string &name) {
	return name;
}
#endif

#if __has_include("duckdb/common/vector/flat_vector.hpp")
#define FINANCE_OLD_DUCKDB_VECTOR_API 0
#else
#define FINANCE_OLD_DUCKDB_VECTOR_API 1
#endif

static void FinanceToUnifiedFormat(Vector &vector, idx_t count, UnifiedVectorFormat &format) {
#if FINANCE_OLD_DUCKDB_VECTOR_API
	vector.ToUnifiedFormat(count, format);
#else
	vector.ToUnifiedFormat(format);
#endif
}

#include "aggregate/constants.inc"
#include "aggregate/sortino.inc"
#include "aggregate/ewma.inc"
#include "aggregate/rsi.inc"
#include "aggregate/drawdown.inc"
#include "aggregate/outliers.inc"
#include "aggregate/quantile_spread.inc"
#include "aggregate/iv_range.inc"
#include "aggregate/helpers.inc"

} // namespace

#include "aggregate/register.inc"

} // namespace duckdb
