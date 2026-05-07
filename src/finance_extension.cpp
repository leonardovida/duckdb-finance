#include "finance/finance_extension.hpp"

namespace duckdb {

static void LoadInternal(ExtensionLoader &loader) {
	loader.SetDescription("SQL-native quant finance functions for DuckDB");
	RegisterFinanceScalars(loader);
	RegisterFinanceMacros(loader);
	RegisterFinanceAggregates(loader);
	RegisterFinanceTableFunctions(loader);
}

void FinanceExtension::Load(ExtensionLoader &loader) {
	LoadInternal(loader);
}

std::string FinanceExtension::Name() {
	return "finance";
}

std::string FinanceExtension::Version() const {
#ifdef EXT_VERSION_FINANCE
	return EXT_VERSION_FINANCE;
#else
	return "";
#endif
}

} // namespace duckdb

extern "C" {

DUCKDB_CPP_EXTENSION_ENTRY(finance, loader) {
	duckdb::LoadInternal(loader);
}
}
