#include "finance/finance_extension.hpp"

#include "duckdb/common/error_data.hpp"
#include "duckdb/common/exception.hpp"
#include "duckdb/common/operator/add.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/common/types/date.hpp"
#include "duckdb/common/types/time.hpp"
#include "duckdb/common/types/timestamp.hpp"
#include "duckdb/common/types/value.hpp"
#include "duckdb/common/vector_operations/binary_executor.hpp"
#include "duckdb/common/vector_operations/ternary_executor.hpp"
#include "duckdb/common/vector_operations/unary_executor.hpp"
#include "duckdb/function/cast/cast_function_set.hpp"
#include "duckdb/function/scalar_function.hpp"
#include "duckdb/execution/expression_executor.hpp"
#include "duckdb/planner/expression/bound_function_expression.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <functional>
#include <initializer_list>
#include <limits>
#include <numeric>

namespace duckdb {
namespace {

#include "scalar/common.inc"
#include "scalar/distributions.inc"
#include "scalar/rates.inc"
#include "scalar/options.inc"
#include "scalar/market_data.inc"
#include "portfolio_qp.inc"
#include "scalar/portfolio_optimizers.inc"

} // namespace

#include "scalar/register.inc"

void FinanceValidateCalendar(const string &function_name, const string &calendar) {
	try {
		ParseCalendar(calendar);
	} catch (InvalidInputException &ex) {
		ErrorData error(ex);
		throw InvalidInputException("%s: %s", function_name, error.RawMessage());
	}
}

} // namespace duckdb
