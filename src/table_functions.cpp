#include "finance/finance_extension.hpp"

#include "duckdb/common/exception.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/common/types/value.hpp"
#include "duckdb/common/types/value_map.hpp"
#include "duckdb/function/function_set.hpp"
#include "duckdb/function/table_function.hpp"
#include "duckdb/parser/parser.hpp"
#include "duckdb/parser/qualified_name.hpp"
#include "duckdb/parser/statement/select_statement.hpp"
#include "duckdb/parser/tableref/subqueryref.hpp"

#include <algorithm>
#include <cmath>
#include <ctime>

namespace duckdb {
namespace {

#include "table_functions/common.inc"
#include "table_functions/option_chain.inc"
#include "table_functions/grid.inc"
#include "table_functions/analytics.inc"
#include "table_functions/bars.inc"
#include "table_functions/generators.inc"

} // namespace

#include "table_functions/register.inc"

} // namespace duckdb
