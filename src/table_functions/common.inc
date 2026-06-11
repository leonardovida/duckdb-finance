static string SqlIdentifier(const string &name) {
	return "\"" + StringUtil::Replace(name, "\"", "\"\"") + "\"";
}

#if __has_include("duckdb/common/identifier.hpp")
static Identifier FinanceFunctionName(const string &name) {
	return Identifier(name);
}
#else
static const string &FinanceFunctionName(const string &name) {
	return name;
}
#endif

static string SqlTableName(const Value &value) {
	if (value.IsNull()) {
		throw BinderException("Table name cannot be NULL");
	}
	return QualifiedName::Parse(value.GetValue<string>()).ToString();
}

static string SqlColumn(const Value &value) {
	if (value.IsNull()) {
		throw BinderException("Column name cannot be NULL");
	}
	return SqlIdentifier(value.GetValue<string>());
}

static string SqlLiteral(const Value &value) {
	if (value.IsNull()) {
		return "NULL";
	}
	return value.ToSQLString();
}

static string CurrentDateLiteral() {
	auto now = std::time(nullptr);
	std::tm tm_value;
#if defined(_WIN32)
	localtime_s(&tm_value, &now);
#else
	localtime_r(&now, &tm_value);
#endif
	char buffer[sizeof("YYYY-MM-DD")];
	if (std::strftime(buffer, sizeof(buffer), "%Y-%m-%d", &tm_value) == 0) {
		throw InternalException("Failed to format current local date");
	}
	return "DATE '" + string(buffer) + "'";
}

static unique_ptr<TableRef> ParseSubquery(ClientContext &context, const string &query) {
	Parser parser(context.GetParserOptions());
	parser.ParseQuery(query);
	if (parser.statements.size() != 1 || parser.statements[0]->type != StatementType::SELECT_STATEMENT) {
		throw ParserException("Finance table function generated an invalid SELECT statement");
	}
	auto select_stmt = unique_ptr_cast<SQLStatement, SelectStatement>(std::move(parser.statements[0]));
	return make_uniq<SubqueryRef>(std::move(select_stmt));
}

static void RegisterBindReplace(ExtensionLoader &loader, const string &name, vector<LogicalType> args,
                                table_function_bind_replace_t bind_replace) {
	TableFunction function(FinanceFunctionName(name), std::move(args), nullptr, nullptr);
	function.bind_replace = bind_replace;
	loader.RegisterFunction(std::move(function));
}

static void RegisterBindReplacePrefixes(ExtensionLoader &loader, const string &name, vector<LogicalType> required_args,
                                        const vector<LogicalType> &optional_args,
                                        table_function_bind_replace_t bind_replace) {
	for (idx_t optional_count = 0; optional_count <= optional_args.size(); optional_count++) {
		auto args = required_args;
		args.insert(args.end(), optional_args.begin(), optional_args.begin() + optional_count);
		RegisterBindReplace(loader, name, std::move(args), bind_replace);
	}
}

static void RegisterTableFunctionPrefixes(ExtensionLoader &loader, const string &name, vector<LogicalType> required_args,
                                          const vector<LogicalType> &optional_args,
                                          table_function_t function, table_function_bind_t bind,
                                          table_function_init_global_t init) {
	for (idx_t optional_count = 0; optional_count <= optional_args.size(); optional_count++) {
		auto args = required_args;
		args.insert(args.end(), optional_args.begin(), optional_args.begin() + optional_count);
		loader.RegisterFunction(TableFunction(FinanceFunctionName(name), std::move(args), function, bind, init));
	}
}

static void RegisterGridFunction(ExtensionLoader &loader, const string &name, table_function_bind_replace_t bind_replace) {
	RegisterBindReplacePrefixes(loader, name,
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                             FinanceLogicalType(LogicalTypeId::TIMESTAMP), FinanceLogicalType(LogicalTypeId::TIMESTAMP), FinanceLogicalType(LogicalTypeId::INTERVAL)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::INTERVAL)}, bind_replace);
}
