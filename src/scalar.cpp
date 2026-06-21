#include "finance/finance_extension.hpp"

#include "duckdb/common/exception.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/common/types/date.hpp"
#include "duckdb/common/types/time.hpp"
#include "duckdb/common/types/timestamp.hpp"
#include "duckdb/common/types/value.hpp"
#if __has_include("duckdb/common/identifier.hpp")
#define FINANCE_HAS_DUCKDB_IDENTIFIER 1
#include "duckdb/common/identifier.hpp"
#else
#define FINANCE_HAS_DUCKDB_IDENTIFIER 0
#endif
#if __has_include("duckdb/common/vector/flat_vector.hpp")
#define FINANCE_OLD_DUCKDB_VECTOR_API 0
#include "duckdb/common/vector/flat_vector.hpp"
#include "duckdb/common/vector/list_vector.hpp"
#include "duckdb/common/vector/string_vector.hpp"
#include "duckdb/common/vector/struct_vector.hpp"
#else
#define FINANCE_OLD_DUCKDB_VECTOR_API 1
#define CanHaveNull() AllValid() == false
#define GetChildMutable GetEntry
#define GetDataMutable GetData
#endif
#include "duckdb/common/vector_operations/binary_executor.hpp"
#include "duckdb/common/vector_operations/ternary_executor.hpp"
#include "duckdb/common/vector_operations/unary_executor.hpp"
#include "duckdb/function/scalar_function.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <functional>
#include <initializer_list>
#include <limits>
#include <numeric>

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

#if FINANCE_OLD_DUCKDB_VECTOR_API
#define FINANCE_STRUCT_CHILD(child) (*(child))
#else
#define FINANCE_STRUCT_CHILD(child) (child)
#endif

static void FinanceToUnifiedFormat(Vector &vector, idx_t count, UnifiedVectorFormat &format) {
#if FINANCE_OLD_DUCKDB_VECTOR_API
	vector.ToUnifiedFormat(count, format);
#else
	vector.ToUnifiedFormat(format);
#endif
}

static void FinanceFlatten(Vector &vector, idx_t count) {
#if FINANCE_OLD_DUCKDB_VECTOR_API
	vector.Flatten(count);
#else
	vector.Flatten();
#endif
}

#include "scalar/common.inc"
#include "scalar/distributions.inc"
#include "scalar/rates.inc"
#include "scalar/options.inc"
#include "scalar/market_data.inc"

} // namespace

#include "scalar/register.inc"

} // namespace duckdb
