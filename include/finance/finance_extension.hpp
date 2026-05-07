#pragma once

#include "duckdb.hpp"
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

} // namespace duckdb
