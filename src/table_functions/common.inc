static string SqlIdentifier(const string &name) {
	return "\"" + StringUtil::Replace(name, "\"", "\"\"") + "\"";
}

static string SqlStringLiteral(const string &value) {
	return "'" + StringUtil::Replace(value, "'", "''") + "'";
}

static const Value &RequireArgument(const TableFunctionBindInput &input, idx_t index, const string &function_name,
                                    const string &parameter) {
	if (index >= input.inputs.size()) {
		throw BinderException("%s: missing %s argument", function_name, parameter);
	}
	auto &value = input.inputs[index];
	if (value.IsNull()) {
		throw BinderException("%s: %s cannot be NULL", function_name, parameter);
	}
	return value;
}

static string RequireString(const Value &value, const string &function_name, const string &parameter) {
	if (value.IsNull()) {
		throw BinderException("%s: %s cannot be NULL", function_name, parameter);
	}
	auto result = value.ToString();
	if (StringUtil::Replace(result, " ", "").empty()) {
		throw BinderException("%s: %s cannot be empty", function_name, parameter);
	}
	return result;
}

// A table source is either a (possibly qualified) table, view, or CTE name, or a
// parenthesized SELECT query such as '(FROM read_parquet(''trades.parquet''))'.
static string SqlSource(const Value &value, const string &function_name, const string &parameter = "table_name") {
	auto text = RequireString(value, function_name, parameter);
	auto trimmed = text;
	StringUtil::Trim(trimmed);
	if (!trimmed.empty() && trimmed.front() == '(') {
		if (trimmed.back() != ')') {
			throw BinderException("%s: %s query must be wrapped in parentheses", function_name, parameter);
		}
		auto query = trimmed.substr(1, trimmed.size() - 2);
		Parser parser;
		try {
			parser.ParseQuery(query);
		} catch (std::exception &ex) {
			ErrorData error(ex);
			throw BinderException("%s: %s is not a valid SELECT query: %s", function_name, parameter,
			                      error.RawMessage());
		}
		if (parser.statements.size() != 1 || parser.statements[0]->type != StatementType::SELECT_STATEMENT) {
			throw BinderException("%s: %s must contain exactly one SELECT query", function_name, parameter);
		}
		// Keep the user's SQL text; the newline terminates a trailing line comment.
		return "(" + query + "\n)";
	}
	return QualifiedName::Parse(text).ToString();
}

static string SqlColumn(const Value &value, const string &function_name, const string &parameter) {
	return SqlIdentifier(RequireString(value, function_name, parameter));
}

static string SqlColumnArg(const TableFunctionBindInput &input, idx_t index, const string &function_name,
                           const string &parameter) {
	return SqlColumn(RequireArgument(input, index, function_name, parameter), function_name, parameter);
}

static string SqlSourceArg(const TableFunctionBindInput &input, idx_t index, const string &function_name,
                           const string &parameter = "table_name") {
	return SqlSource(RequireArgument(input, index, function_name, parameter), function_name, parameter);
}

static optional_ptr<const Value> NamedArgument(const TableFunctionBindInput &input, const string &name) {
	for (auto &entry : input.named_parameters) {
		if (StringUtil::CIEquals(entry.first, name)) {
			return &entry.second;
		}
	}
	return nullptr;
}

// Optional named column argument; returns an empty string when omitted or NULL.
static string OptionalNamedColumn(const TableFunctionBindInput &input, const string &name,
                                  const string &function_name) {
	auto value = NamedArgument(input, name);
	if (!value || value->IsNull()) {
		return string();
	}
	return SqlColumn(*value, function_name, name);
}

static double RequireFiniteDouble(const Value &value, const string &function_name, const string &parameter) {
	if (value.IsNull()) {
		throw BinderException("%s: %s cannot be NULL", function_name, parameter);
	}
	Value double_value;
	string error;
	if (!value.DefaultTryCastAs(LogicalType::DOUBLE, double_value, &error)) {
		throw InvalidInputException("%s: %s must be numeric: %s", function_name, parameter, error);
	}
	auto result = double_value.GetValue<double>();
	if (!std::isfinite(result)) {
		throw InvalidInputException("%s: %s must be finite", function_name, parameter);
	}
	return result;
}

static int64_t RequireInteger(const Value &value, const string &function_name, const string &parameter) {
	if (value.IsNull()) {
		throw BinderException("%s: %s cannot be NULL", function_name, parameter);
	}
	Value integer_value;
	string error;
	if (!value.DefaultTryCastAs(LogicalType::BIGINT, integer_value, &error)) {
		throw InvalidInputException("%s: %s must be an integer: %s", function_name, parameter, error);
	}
	return integer_value.GetValue<int64_t>();
}

static string DoubleLiteral(double value) {
	return "CAST(" + Value::DOUBLE(value).ToSQLString() + " AS DOUBLE)";
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

static void RequireInputCountExactly(const TableFunctionBindInput &input, idx_t expected_count, const string &message) {
	if (input.inputs.size() != expected_count) {
		throw BinderException(message);
	}
}

static void RequireInputCountBetween(const TableFunctionBindInput &input, idx_t min_count, idx_t max_count,
                                     const string &message) {
	auto count = input.inputs.size();
	if (count < min_count || count > max_count) {
		throw BinderException(message);
	}
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
                                table_function_bind_replace_t bind_replace,
                                const vector<string> &named_varchar_parameters = {}) {
	TableFunction function(FinanceFunctionName(name), std::move(args), nullptr, nullptr);
	function.bind_replace = bind_replace;
	for (auto &parameter : named_varchar_parameters) {
		function.named_parameters[parameter] = LogicalType::VARCHAR;
	}
	loader.RegisterFunction(std::move(function));
}

static void RegisterBindReplacePrefixes(ExtensionLoader &loader, const string &name, vector<LogicalType> required_args,
                                        const vector<LogicalType> &optional_args,
                                        table_function_bind_replace_t bind_replace,
                                        const vector<string> &named_varchar_parameters = {}) {
	for (idx_t optional_count = 0; optional_count <= optional_args.size(); optional_count++) {
		auto args = required_args;
		args.insert(args.end(), optional_args.begin(), optional_args.begin() + optional_count);
		RegisterBindReplace(loader, name, std::move(args), bind_replace, named_varchar_parameters);
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
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::INTERVAL)}, bind_replace,
	                            {"asset_col", "seq_col"});
}
