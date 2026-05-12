#include "finance/finance_extension.hpp"

#include "duckdb/common/exception.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/common/types/date.hpp"
#include "duckdb/common/types/time.hpp"
#include "duckdb/common/types/timestamp.hpp"
#include "duckdb/common/types/value.hpp"
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
#include <cmath>
#include <functional>
#include <limits>
#include <numeric>

namespace duckdb {
namespace {

#if FINANCE_OLD_DUCKDB_VECTOR_API
#define FINANCE_STRUCT_CHILD(child) (*(child))
#else
#define FINANCE_STRUCT_CHILD(child) (child)
#endif

#include "scalar/common.inc"
#include "scalar/distributions.inc"
#include "scalar/rates.inc"
#include "scalar/options.inc"
#include "scalar/market_data.inc"

} // namespace

#include "scalar/register.inc"

} // namespace duckdb
