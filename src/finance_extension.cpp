#include "finance/finance_extension.hpp"

#include "duckdb/catalog/catalog.hpp"
#include "duckdb/catalog/catalog_entry/aggregate_function_catalog_entry.hpp"
#include "duckdb/catalog/catalog_entry/function_entry.hpp"
#include "duckdb/catalog/catalog_entry/scalar_function_catalog_entry.hpp"
#include "duckdb/catalog/catalog_entry/table_function_catalog_entry.hpp"
#include "duckdb/common/string_util.hpp"

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

//! The types of the parameters a caller passes by position; duckdb_functions() matches descriptions on these.
static vector<LogicalType> PositionalParameterTypes(const FunctionSignature &signature) {
	vector<LogicalType> types;
	for (idx_t i = 0; i < signature.GetPositionalParameterCount(); i++) {
		types.push_back(signature.GetParameter(i).GetType());
	}
	return types;
}

// duckdb_functions() picks the description whose parameter_types equal the overload's positional parameter types,
// so every overload gets its own description. Parameter names come from the function signature.
template <class ENTRY>
static vector<FunctionDescription> DescribeFinanceOverloads(CatalogEntry &entry, const FunctionDescription &base) {
	vector<FunctionDescription> descriptions;
	auto &functions = entry.Cast<ENTRY>().functions;
	for (idx_t i = 0; i < functions.Size(); i++) {
		FunctionDescription description = base;
		description.parameter_types = PositionalParameterTypes(functions.GetFunctionByOffset(i)->GetSignature());
		descriptions.push_back(std::move(description));
	}
	return descriptions;
}

static void ApplyFinanceFunctionMetadata(CatalogEntry &entry) {
	auto &name = entry.name.GetIdentifierName();
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
	vector<FunctionDescription> descriptions;
	switch (entry.type) {
	case CatalogType::SCALAR_FUNCTION_ENTRY:
		descriptions = DescribeFinanceOverloads<ScalarFunctionCatalogEntry>(entry, description);
		break;
	case CatalogType::AGGREGATE_FUNCTION_ENTRY:
		descriptions = DescribeFinanceOverloads<AggregateFunctionCatalogEntry>(entry, description);
		break;
	case CatalogType::TABLE_FUNCTION_ENTRY:
		descriptions = DescribeFinanceOverloads<TableFunctionCatalogEntry>(entry, description);
		break;
	default:
		// Macros report their own parameter names.
		break;
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
	auto &schema = catalog.GetSchema(transaction, Identifier(DEFAULT_SCHEMA));
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

template <class FUNCTION>
static void PrepareFinanceFunction(FUNCTION &function, const string &name) {
	FinanceNameParameters(name, function.GetSignature());
	function.SetFallible();
}

static void PrepareFinanceFunction(TableFunction &function, const string &name) {
	FinanceNameParameters(name, function.GetSignature());
}

template <class SET>
static void PrepareFinanceFunctionSet(SET &set) {
	auto name = set.name.GetIdentifierName();
	set.ApplyToFunctions([&](auto &function) { PrepareFinanceFunction(function, name); });
}

} // namespace

void FinanceNameParameters(const string &function_name, FunctionSignature &signature) {
	auto metadata = FindFinanceFunctionMetadata(function_name);
	if (!metadata) {
		return;
	}
	auto positional_count = signature.GetPositionalParameterCount();
	vector<LogicalType> arguments;
	for (idx_t i = 0; i < positional_count; i++) {
		arguments.push_back(signature.GetParameter(i).GetType());
	}
	vector<string> names;
	if (!MatchFinanceSignature(ParseFinanceSignatures(metadata->signatures), arguments, names)) {
		return;
	}
	// A name can only be passed once; keep positional-only parameters if the documentation repeats one.
	for (idx_t i = 0; i < names.size(); i++) {
		for (idx_t j = 0; j < i; j++) {
			if (StringUtil::CIEquals(names[i], names[j])) {
				return;
			}
		}
	}
	for (idx_t i = 0; i < positional_count; i++) {
		auto &parameter = signature.GetParameter(i);
		parameter = FunctionParameter(Identifier(names[i]), parameter.GetType());
	}
}

void FinanceRegisterFunction(ExtensionLoader &loader, ScalarFunction function) {
	PrepareFinanceFunction(function, function.name.GetIdentifierName());
	loader.RegisterFunction(std::move(function));
}

void FinanceRegisterFunction(ExtensionLoader &loader, ScalarFunctionSet function) {
	PrepareFinanceFunctionSet(function);
	loader.RegisterFunction(std::move(function));
}

void FinanceRegisterFunction(ExtensionLoader &loader, AggregateFunction function) {
	PrepareFinanceFunction(function, function.name.GetIdentifierName());
	loader.RegisterFunction(std::move(function));
}

void FinanceRegisterFunction(ExtensionLoader &loader, AggregateFunctionSet function) {
	PrepareFinanceFunctionSet(function);
	loader.RegisterFunction(std::move(function));
}

void FinanceRegisterFunction(ExtensionLoader &loader, TableFunction function) {
	PrepareFinanceFunction(function, function.name.GetIdentifierName());
	loader.RegisterFunction(std::move(function));
}

void FinanceRegisterFunction(ExtensionLoader &loader, TableFunctionSet function) {
	PrepareFinanceFunctionSet(function);
	loader.RegisterFunction(std::move(function));
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
