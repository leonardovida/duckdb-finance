#include "finance/finance_extension.hpp"

#include "duckdb/catalog/catalog.hpp"
#include "duckdb/catalog/catalog_entry/function_entry.hpp"
#include "duckdb/common/string_util.hpp"
#if __has_include("duckdb/common/identifier.hpp")
#define FINANCE_METADATA_HAS_DUCKDB_IDENTIFIER 1
#include "duckdb/common/identifier.hpp"
#else
#define FINANCE_METADATA_HAS_DUCKDB_IDENTIFIER 0
#endif

namespace duckdb {
namespace {

struct FinanceFunctionMetadata {
	const char *name;
	const char *category;
	const char *description;
	const char *example;
};

#include "function_metadata.inc"

#if FINANCE_METADATA_HAS_DUCKDB_IDENTIFIER
static Identifier FinanceCatalogName(const string &name) {
	return Identifier(name);
}

static const string &FinanceEntryName(CatalogEntry &entry) {
	return entry.name.GetIdentifierName();
}
#else
static string FinanceCatalogName(const string &name) {
	return name;
}

static const string &FinanceEntryName(CatalogEntry &entry) {
	return entry.name;
}
#endif

static const FinanceFunctionMetadata *FindFinanceFunctionMetadata(const string &name) {
	for (idx_t i = 0; FINANCE_FUNCTION_METADATA[i].name != nullptr; i++) {
		if (name == FINANCE_FUNCTION_METADATA[i].name) {
			return &FINANCE_FUNCTION_METADATA[i];
		}
	}
	return nullptr;
}

static void ApplyFinanceFunctionMetadata(CatalogEntry &entry) {
	auto &name = FinanceEntryName(entry);
	if (!StringUtil::StartsWith(name, "fin_")) {
		return;
	}
	auto metadata = FindFinanceFunctionMetadata(name);
	if (!metadata) {
		return;
	}
	FunctionDescription description;
	description.description = metadata->description;
	description.examples.push_back(metadata->example);
	description.categories.push_back(metadata->category);
	entry.Cast<FunctionEntry>().descriptions = {std::move(description)};
}

static void RegisterFinanceFunctionMetadata(ExtensionLoader &loader) {
	auto &db = loader.GetDatabaseInstance();
	auto &catalog = Catalog::GetSystemCatalog(db);
	auto transaction = CatalogTransaction::GetSystemTransaction(db);
	auto &schema = catalog.GetSchema(transaction, FinanceCatalogName(DEFAULT_SCHEMA));
	for (auto type : {CatalogType::SCALAR_FUNCTION_ENTRY, CatalogType::AGGREGATE_FUNCTION_ENTRY,
	                  CatalogType::TABLE_FUNCTION_ENTRY, CatalogType::MACRO_ENTRY}) {
		schema.Scan(type, ApplyFinanceFunctionMetadata);
	}
}

static void LoadInternal(ExtensionLoader &loader) {
	loader.SetDescription("SQL-native quant finance functions for DuckDB");
	RegisterFinanceScalars(loader);
	RegisterFinanceMacros(loader);
	RegisterFinanceAggregates(loader);
	RegisterFinanceTableFunctions(loader);
	RegisterFinanceFunctionMetadata(loader);
}

} // namespace

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
