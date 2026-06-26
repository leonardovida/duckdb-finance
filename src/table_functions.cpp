#include "finance/finance_extension.hpp"

#include "duckdb/common/exception.hpp"
#if __has_include("duckdb/common/identifier.hpp")
#define FINANCE_HAS_DUCKDB_IDENTIFIER 1
#include "duckdb/common/identifier.hpp"
#else
#define FINANCE_HAS_DUCKDB_IDENTIFIER 0
#endif
#include "duckdb/common/string_util.hpp"
#include "duckdb/common/types/value.hpp"
#include "duckdb/common/types/value_map.hpp"
#include "duckdb/function/function_set.hpp"
#include "duckdb/function/table_function.hpp"
#include "duckdb/parser/parser.hpp"
#include "duckdb/parser/qualified_name.hpp"
#include "duckdb/parser/statement/select_statement.hpp"
#include "duckdb/parser/tableref/subqueryref.hpp"

#if __has_include("duckdb/common/vector/flat_vector.hpp")
#include "duckdb/common/vector/flat_vector.hpp"
#define FINANCE_HAS_FLAT_VECTOR_SET_SIZE 1
#else
#define FINANCE_HAS_FLAT_VECTOR_SET_SIZE 0
#endif

#include <algorithm>
#include <cmath>
#include <ctime>
#include <type_traits>
#include <utility>

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

#include "table_functions/common.inc"
#include "table_functions/option_chain.inc"
#include "table_functions/grid.inc"
#include "table_functions/normalization.inc"
#include "table_functions/analytics.inc"
#include "table_functions/bars.inc"
#include "table_functions/generators.inc"

} // namespace

#include "table_functions/register.inc"

} // namespace duckdb
