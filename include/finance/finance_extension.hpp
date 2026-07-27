#pragma once

#include "duckdb.hpp"
#if __has_include("duckdb/common/identifier.hpp")
#define FINANCE_HAS_DUCKDB_IDENTIFIER 1
#include "duckdb/common/identifier.hpp"
#else
#define FINANCE_HAS_DUCKDB_IDENTIFIER 0
#endif
#if __has_include("duckdb/common/vector/flat_vector.hpp")
#define FINANCE_OLD_DUCKDB_VECTOR_API 0
#include "duckdb/common/vector/flat_vector.hpp"
#else
#define FINANCE_OLD_DUCKDB_VECTOR_API 1
#endif
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

#if FINANCE_HAS_DUCKDB_IDENTIFIER
inline Identifier FinanceFunctionName(const string &name) {
	return Identifier(name);
}
#else
inline string FinanceFunctionName(const string &name) {
	return name;
}
#endif

inline void FinanceToUnifiedFormat(Vector &vector, idx_t count, UnifiedVectorFormat &format) {
#if FINANCE_OLD_DUCKDB_VECTOR_API
	vector.ToUnifiedFormat(count, format);
#else
	vector.ToUnifiedFormat(format);
#endif
}

inline LogicalType FinanceLogicalType(LogicalTypeId id) {
	return LogicalType(id);
}

} // namespace duckdb
