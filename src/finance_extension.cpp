#include "finance/finance_extension.hpp"

#include "duckdb/catalog/catalog.hpp"
#include "duckdb/catalog/catalog_entry/aggregate_function_catalog_entry.hpp"
#include "duckdb/catalog/catalog_entry/function_entry.hpp"
#include "duckdb/catalog/catalog_entry/scalar_function_catalog_entry.hpp"
#include "duckdb/catalog/catalog_entry/table_function_catalog_entry.hpp"
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
	//! Documented parameter names, `name[:TYPE],...` per signature, signatures separated by ';'.
	const char *signatures;
};

struct FinanceParameter {
	string name;
	string type_hint;
};

using FinanceSignature = vector<FinanceParameter>;

#include "function_metadata.inc"

// DuckDB v1.5.6 ships identifier.hpp as a 2.0 backport while catalog entry names
// remain strings, so resolve the name type by overload instead of by header.
static const string &FinanceNameString(const string &name) {
	return name;
}

#if FINANCE_METADATA_HAS_DUCKDB_IDENTIFIER
static Identifier FinanceCatalogName(const string &name) {
	return Identifier(name);
}

static const string &FinanceNameString(const Identifier &name) {
	return name.GetIdentifierName();
}
#else
static string FinanceCatalogName(const string &name) {
	return name;
}
#endif

static const string &FinanceEntryName(CatalogEntry &entry) {
	return FinanceNameString(entry.name);
}

static const FinanceFunctionMetadata *FindFinanceFunctionMetadata(const string &name) {
	for (idx_t i = 0; FINANCE_FUNCTION_METADATA[i].name != nullptr; i++) {
		if (name == FINANCE_FUNCTION_METADATA[i].name) {
			return &FINANCE_FUNCTION_METADATA[i];
		}
	}
	return nullptr;
}

static vector<FinanceSignature> ParseFinanceSignatures(const char *text) {
	vector<FinanceSignature> signatures;
	if (!text || !*text) {
		return signatures;
	}
	for (auto &signature_text : StringUtil::Split(string(text), ';')) {
		FinanceSignature signature;
		for (auto &parameter_text : StringUtil::Split(signature_text, ',')) {
			FinanceParameter parameter;
			auto colon = parameter_text.find(':');
			parameter.name = parameter_text.substr(0, colon);
			if (colon != string::npos) {
				parameter.type_hint = parameter_text.substr(colon + 1);
			}
			signature.push_back(std::move(parameter));
		}
		signatures.push_back(std::move(signature));
	}
	return signatures;
}

// An overload with N positional arguments takes the first N names of the first documented signature that has at
// least N names and whose type hints match its argument types (see docs/function_examples.sql).
static bool MatchFinanceSignature(const vector<FinanceSignature> &signatures, const vector<LogicalType> &arguments,
                                  vector<string> &names) {
	for (auto &signature : signatures) {
		if (signature.size() < arguments.size()) {
			continue;
		}
		bool matches = true;
		for (idx_t i = 0; i < arguments.size() && matches; i++) {
			auto &hint = signature[i].type_hint;
			matches = hint.empty() || arguments[i].id() == LogicalTypeId::ANY ||
			          StringUtil::CIEquals(arguments[i].ToString(), hint);
		}
		if (!matches) {
			continue;
		}
		names.clear();
		for (idx_t i = 0; i < arguments.size(); i++) {
			names.push_back(signature[i].name);
		}
		return true;
	}
	return false;
}

// duckdb_functions() picks the description whose parameter_types equal the overload's arguments, so every overload
// gets its own description; table functions list their named parameters after the positional ones.
static FunctionDescription DescribeFinanceOverload(const FunctionDescription &base,
                                                   const vector<FinanceSignature> &signatures,
                                                   const vector<LogicalType> &arguments,
                                                   const vector<string> &named_parameters) {
	FunctionDescription description = base;
	description.parameter_types = arguments;
	if (MatchFinanceSignature(signatures, arguments, description.parameter_names)) {
		for (auto &name : named_parameters) {
			description.parameter_names.push_back(name);
		}
	}
	return description;
}

template <class ENTRY>
static vector<FunctionDescription> DescribeFinanceOverloads(CatalogEntry &entry, const FunctionDescription &base,
                                                            const vector<FinanceSignature> &signatures) {
	vector<FunctionDescription> descriptions;
	auto &functions = entry.Cast<ENTRY>().functions;
	for (idx_t i = 0; i < functions.Size(); i++) {
		auto function = functions.GetFunctionByOffset(i);
		descriptions.push_back(DescribeFinanceOverload(base, signatures, function.arguments, {}));
	}
	return descriptions;
}

static vector<FunctionDescription> DescribeFinanceTableOverloads(CatalogEntry &entry, const FunctionDescription &base,
                                                                 const vector<FinanceSignature> &signatures) {
	vector<FunctionDescription> descriptions;
	auto &functions = entry.Cast<TableFunctionCatalogEntry>().functions;
	for (idx_t i = 0; i < functions.Size(); i++) {
		// duckdb_functions() also lists named parameters from a copy of the overload; iterate a copy the same way
		// so the order matches.
		auto function = functions.GetFunctionByOffset(i);
		vector<string> named_parameters;
		for (auto &parameter : function.named_parameters) {
			named_parameters.push_back(parameter.first);
		}
		descriptions.push_back(DescribeFinanceOverload(base, signatures, function.arguments, named_parameters));
	}
	return descriptions;
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
	auto signatures = ParseFinanceSignatures(metadata->signatures);
	vector<FunctionDescription> descriptions;
	if (!signatures.empty()) {
		switch (entry.type) {
		case CatalogType::SCALAR_FUNCTION_ENTRY:
			descriptions = DescribeFinanceOverloads<ScalarFunctionCatalogEntry>(entry, description, signatures);
			break;
		case CatalogType::AGGREGATE_FUNCTION_ENTRY:
			descriptions = DescribeFinanceOverloads<AggregateFunctionCatalogEntry>(entry, description, signatures);
			break;
		case CatalogType::TABLE_FUNCTION_ENTRY:
			descriptions = DescribeFinanceTableOverloads(entry, description, signatures);
			break;
		default:
			// Macros report their own parameter names.
			break;
		}
	}
	if (descriptions.empty()) {
		descriptions.push_back(std::move(description));
	}
	entry.Cast<FunctionEntry>().descriptions = std::move(descriptions);
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
