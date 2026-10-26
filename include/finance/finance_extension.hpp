#pragma once

#include "duckdb.hpp"
#include "duckdb/common/identifier.hpp"
#include "duckdb/common/vector/flat_vector.hpp"
#include "duckdb/common/vector/list_vector.hpp"
#include "duckdb/common/vector/string_vector.hpp"
#include "duckdb/common/vector/struct_vector.hpp"
#include "duckdb/function/function_set.hpp"
#include "duckdb/main/extension/extension_loader.hpp"

namespace duckdb {

class FinanceExtension : public Extension {
public:
	void Load(ExtensionLoader &loader) override;
	std::string Name() override;
	std::string Version() const override;
};

void RegisterFinanceScalars(ExtensionLoader &loader);
void RegisterFinanceMacros(ExtensionLoader &loader);
void RegisterFinanceAggregates(ExtensionLoader &loader);
void RegisterFinanceTableFunctions(ExtensionLoader &loader);
//! Throws InvalidInputException "<function_name>: unknown calendar ..." for a calendar name the scalar
//! calendar functions do not support.
void FinanceValidateCalendar(const string &function_name, const string &calendar);

//! Names the positional parameters of a documented fin_* overload after its documented signature (see
//! docs/function_examples.sql), so duckdb_functions() reports them and callers can pass `name := value`.
//! Overloads without a documented signature keep DuckDB's positional-only `col<N>` parameters.
void FinanceNameParameters(const string &function_name, FunctionSignature &signature);

//! Register a native fin_* function: name its parameters and mark it fallible. DuckDB 2.0 turns an execution error
//! thrown by a function that is not marked fallible into an internal error, and finance functions reject invalid
//! input at execution time.
void FinanceRegisterFunction(ExtensionLoader &loader, ScalarFunction function);
void FinanceRegisterFunction(ExtensionLoader &loader, ScalarFunctionSet function);
void FinanceRegisterFunction(ExtensionLoader &loader, AggregateFunction function);
void FinanceRegisterFunction(ExtensionLoader &loader, AggregateFunctionSet function);
void FinanceRegisterFunction(ExtensionLoader &loader, TableFunction function);
void FinanceRegisterFunction(ExtensionLoader &loader, TableFunctionSet function);

inline Identifier FinanceFunctionName(const string &name) {
	return Identifier(name);
}

inline void FinanceToUnifiedFormat(Vector &vector, idx_t, UnifiedVectorFormat &format) {
	vector.ToUnifiedFormat(format);
}

inline LogicalType FinanceLogicalType(LogicalTypeId id) {
	return LogicalType(id);
}

} // namespace duckdb
