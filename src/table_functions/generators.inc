struct SchemaRow {
	string schema_kind;
	string column_name;
	string logical_type;
	bool required;
	string description;
};

struct SchemaTemplateBindData : public FunctionData {
	explicit SchemaTemplateBindData(vector<SchemaRow> rows_p) : rows(std::move(rows_p)) {
	}

	vector<SchemaRow> rows;

	unique_ptr<FunctionData> Copy() const override {
		return make_uniq<SchemaTemplateBindData>(rows);
	}

	bool Equals(const FunctionData &other_p) const override {
		auto &other = other_p.Cast<SchemaTemplateBindData>();
		return rows.size() == other.rows.size();
	}
};

struct RowsGlobalState : public GlobalTableFunctionState {
	idx_t offset = 0;
};

static void SetOutputCardinality(DataChunk &output, idx_t count) {
#if FINANCE_HAS_FLAT_VECTOR_SET_SIZE
	for (auto &vector : output.data) {
		FlatVector::SetSize(vector, count);
	}
#endif
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#elif defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif
	output.SetCardinality(count);
#if defined(__clang__)
#pragma clang diagnostic pop
#elif defined(__GNUC__)
#pragma GCC diagnostic pop
#endif
}

static vector<SchemaRow> SchemaRows(const string &kind, const string &function_name) {
	auto normalized = StringUtil::Lower(kind);
	StringUtil::Trim(normalized);
	vector<SchemaRow> rows;
	auto add = [&](const string &name, const string &type, bool required, const string &description) {
		rows.push_back({normalized, name, type, required, description});
	};
	if (normalized == "returns") {
		add("date", "DATE", true, "Observation date");
		add("asset_id", "VARCHAR", true, "Asset identifier");
		add("return_decimal", "DOUBLE", true, "Decimal return");
		return rows;
	}
	if (normalized == "option_chain") {
		add("option_kind", "VARCHAR", true, "call or put");
		add("underlying_price", "DOUBLE", true, "Underlying price");
		add("strike_price", "DOUBLE", true, "Strike price");
		add("time_to_expiry_years", "DOUBLE", true, "Time to expiry in years");
		add("risk_free_rate", "DOUBLE", true, "Annualized decimal risk-free rate");
		add("implied_volatility", "DOUBLE", true, "Annualized decimal volatility");
		add("dividend_yield", "DOUBLE", false, "Continuous dividend yield");
		return rows;
	}
	if (normalized == "rates_curve") {
		add("instrument", "VARCHAR", false, "Instrument identifier");
		add("maturity", "DOUBLE", true, "Maturity in years");
		add("rate", "DOUBLE", true, "Annualized quoted rate");
		return rows;
	}
	if (normalized == "portfolio") {
		add("asset_id", "VARCHAR", true, "Asset identifier");
		add("weight", "DOUBLE", true, "Portfolio weight");
		add("expected_return", "DOUBLE", false, "Expected decimal return");
		add("base_currency", "VARCHAR", false, "Base currency");
		return rows;
	}
	if (normalized != "ohlcv") {
		throw InvalidInputException("%s: unknown schema kind '%s' (expected ohlcv, returns, option_chain, rates_curve, or "
		                            "portfolio)",
		                            function_name, kind);
	}
	add("ts", "TIMESTAMP", true, "Timestamp");
	add("asset_id", "VARCHAR", false, "Asset identifier");
	add("open", "DOUBLE", false, "Open price");
	add("high", "DOUBLE", false, "High price");
	add("low", "DOUBLE", false, "Low price");
	add("close", "DOUBLE", true, "Close price");
	add("volume", "DOUBLE", false, "Volume");
	return rows;
}

static unique_ptr<FunctionData> SchemaTemplateBind(ClientContext &, TableFunctionBindInput &input,
                                                   vector<LogicalType> &return_types, vector<string> &names) {
	names = {"schema_kind", "column_name", "logical_type", "required", "description"};
	return_types = {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::BOOLEAN),
	                FinanceLogicalType(LogicalTypeId::VARCHAR)};
	auto kind = RequireString(RequireArgument(input, 0, "fin_schema_template", "kind"), "fin_schema_template", "kind");
	return make_uniq<SchemaTemplateBindData>(SchemaRows(kind, "fin_schema_template"));
}

// Compare a table's columns (DESCRIBE) with a schema template. Column names match
// case-insensitively; compatible means the source type can be read as the
// template type without changing meaning (any numeric for DOUBLE, DATE or
// TIMESTAMP variants for temporal columns, character data for VARCHAR).
static unique_ptr<TableRef> ValidateSchemaBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	const string function_name = "fin_validate_schema";
	auto table = SqlSourceArg(input, 0, function_name);
	auto kind = RequireString(RequireArgument(input, 1, function_name, "kind"), function_name, "kind");
	auto rows = SchemaRows(kind, function_name);
	vector<string> values;
	for (idx_t i = 0; i < rows.size(); i++) {
		auto &row = rows[i];
		values.push_back(StringUtil::Format("(%llu, %s, %s, %s, %s)", static_cast<unsigned long long>(i),
		                                    SqlStringLiteral(row.schema_kind), SqlStringLiteral(row.column_name),
		                                    SqlStringLiteral(row.logical_type), row.required ? "true" : "false"));
	}
	auto source = StringUtil::StartsWith(table, "(") ? "SELECT * FROM " + table : table;
	auto query = StringUtil::Format(
	    "WITH __finance_template(__finance_pos, schema_kind, column_name, expected_type, required) AS (VALUES %s), "
	    "__finance_actual AS (SELECT column_name AS __finance_name, column_type AS actual_type FROM (DESCRIBE %s)), "
	    "__finance_matched AS ("
	    "  SELECT t.*, a.actual_type, a.actual_type IS NOT NULL AS present, "
	    "    CASE "
	    "      WHEN a.actual_type IS NULL THEN NULL "
	    "      WHEN t.expected_type = 'DOUBLE' THEN a.actual_type IN ('TINYINT', 'SMALLINT', 'INTEGER', 'BIGINT', "
	    "        'HUGEINT', 'UTINYINT', 'USMALLINT', 'UINTEGER', 'UBIGINT', 'UHUGEINT', 'FLOAT', 'DOUBLE') "
	    "        OR a.actual_type LIKE 'DECIMAL(%%' "
	    "      WHEN t.expected_type IN ('DATE', 'TIMESTAMP') THEN a.actual_type IN ('DATE', 'TIMESTAMP', "
	    "        'TIMESTAMP_S', 'TIMESTAMP_MS', 'TIMESTAMP_NS', 'TIMESTAMP WITH TIME ZONE') "
	    "      WHEN t.expected_type = 'VARCHAR' THEN a.actual_type = 'VARCHAR' "
	    "      ELSE a.actual_type = t.expected_type END AS compatible "
	    "  FROM __finance_template t LEFT JOIN __finance_actual a ON lower(a.__finance_name) = lower(t.column_name)"
	    ") "
	    "SELECT schema_kind, column_name, expected_type, required, present, actual_type, compatible, "
	    "CASE WHEN NOT present AND required THEN 'missing' WHEN NOT present THEN 'missing_optional' "
	    "WHEN NOT compatible THEN 'type_mismatch' ELSE 'ok' END AS status, "
	    "(present AND compatible) OR (NOT present AND NOT required) AS valid "
	    "FROM __finance_matched ORDER BY __finance_pos",
	    StringUtil::Join(values, ", "), source);
	return ParseSubquery(context, query);
}

static unique_ptr<GlobalTableFunctionState> RowsInit(ClientContext &, TableFunctionInitInput &) {
	return make_uniq<RowsGlobalState>();
}

static void SchemaTemplateFunction(ClientContext &, TableFunctionInput &data_p, DataChunk &output) {
	auto &bind_data = data_p.bind_data->Cast<SchemaTemplateBindData>();
	auto &state = data_p.global_state->Cast<RowsGlobalState>();
	idx_t count = 0;
	while (state.offset < bind_data.rows.size() && count < STANDARD_VECTOR_SIZE) {
		auto &row = bind_data.rows[state.offset++];
		output.data[0].SetValue(count, Value(row.schema_kind));
		output.data[1].SetValue(count, Value(row.column_name));
		output.data[2].SetValue(count, Value(row.logical_type));
		output.data[3].SetValue(count, Value::BOOLEAN(row.required));
		output.data[4].SetValue(count, Value(row.description));
		count++;
	}
	SetOutputCardinality(output, count);
}

static double ReadDoubleValue(const Value &value, const string &function_name, const string &parameter) {
	if (value.IsNull()) {
		throw BinderException("%s: %s must not contain NULL values", function_name, parameter);
	}
	auto result = value.GetValue<double>();
	if (!std::isfinite(result)) {
		throw InvalidInputException("%s: %s must contain finite values", function_name, parameter);
	}
	return result;
}

static vector<double> ReadDoubleListValue(const Value &value, const string &function_name, const string &parameter) {
	if (value.IsNull()) {
		throw BinderException("%s: %s cannot be NULL", function_name, parameter);
	}
	vector<double> result;
	for (auto &child : ListValue::GetChildren(value)) {
		result.push_back(ReadDoubleValue(child, function_name, parameter));
	}
	return result;
}

static vector<vector<double>> ReadDoubleMatrixValue(const Value &value, const string &function_name,
                                                    const string &parameter) {
	if (value.IsNull()) {
		throw BinderException("%s: %s cannot be NULL", function_name, parameter);
	}
	vector<vector<double>> matrix;
	for (auto &row_value : ListValue::GetChildren(value)) {
		matrix.push_back(ReadDoubleListValue(row_value, function_name, parameter + " row"));
	}
	return matrix;
}

static void ValidateCovarianceShape(const vector<vector<double>> &cov, idx_t n, const string &function_name) {
	if (n == 0) {
		throw InvalidInputException("%s: at least one asset is required", function_name);
	}
	if (cov.size() != n) {
		throw InvalidInputException("%s: covariance matrix must be %llu x %llu", function_name,
		                            static_cast<unsigned long long>(n), static_cast<unsigned long long>(n));
	}
	for (auto &row : cov) {
		if (row.size() != n) {
			throw InvalidInputException("%s: covariance matrix must be %llu x %llu", function_name,
			                            static_cast<unsigned long long>(n), static_cast<unsigned long long>(n));
		}
	}
}

static void RequireNonNullArguments(const TableFunctionBindInput &input, idx_t first, const string &function_name) {
	for (idx_t i = first; i < input.inputs.size(); i++) {
		if (input.inputs[i].IsNull()) {
			throw BinderException("%s: argument %llu cannot be NULL", function_name,
			                      static_cast<unsigned long long>(i + 1));
		}
	}
}

static double DotValues(const vector<double> &x, const vector<double> &y) {
	D_ASSERT(x.size() == y.size());
	double result = 0.0;
	for (idx_t i = 0; i < x.size(); i++) {
		result += x[i] * y[i];
	}
	return result;
}

static double PortfolioVarianceValue(const vector<double> &weights, const vector<vector<double>> &cov) {
	vector<double> sigma_w(weights.size(), 0.0);
	for (idx_t r = 0; r < cov.size(); r++) {
		sigma_w[r] = DotValues(cov[r], weights);
	}
	return DotValues(weights, sigma_w);
}

struct PortfolioOptimizeBindData : public FunctionData {
	explicit PortfolioOptimizeBindData(vector<double> weights_p) : weights(std::move(weights_p)) {
	}

	vector<double> weights;

	unique_ptr<FunctionData> Copy() const override {
		return make_uniq<PortfolioOptimizeBindData>(weights);
	}

	bool Equals(const FunctionData &other_p) const override {
		auto &other = other_p.Cast<PortfolioOptimizeBindData>();
		return weights == other.weights;
	}
};

static vector<double> EqualWeights(idx_t n) {
	vector<double> weights(n, n == 0 ? 0.0 : 1.0 / double(n));
	return weights;
}

static unique_ptr<FunctionData> PortfolioOptimizeBind(ClientContext &, TableFunctionBindInput &input,
                                                      vector<LogicalType> &return_types, vector<string> &names) {
	names = {"asset_idx", "weight"};
	return_types = {FinanceLogicalType(LogicalTypeId::BIGINT), FinanceLogicalType(LogicalTypeId::DOUBLE)};
	const string function_name = "fin_portfolio_optimize";
	auto mu = ReadDoubleListValue(RequireArgument(input, 0, function_name, "mu"), function_name, "mu");
	auto cov = ReadDoubleMatrixValue(RequireArgument(input, 1, function_name, "cov"), function_name, "cov");
	ValidateCovarianceShape(cov, mu.size(), function_name);
	RequireNonNullArguments(input, 2, function_name);
	return make_uniq<PortfolioOptimizeBindData>(EqualWeights(mu.size()));
}

static void PortfolioOptimizeFunction(ClientContext &, TableFunctionInput &data_p, DataChunk &output) {
	auto &bind_data = data_p.bind_data->Cast<PortfolioOptimizeBindData>();
	auto &state = data_p.global_state->Cast<RowsGlobalState>();
	idx_t count = 0;
	auto asset_idx = FlatVector::GetData<int64_t>(output.data[0]);
	auto weights = FlatVector::GetData<double>(output.data[1]);
	while (state.offset < bind_data.weights.size() && count < STANDARD_VECTOR_SIZE) {
		asset_idx[count] = NumericCast<int64_t>(state.offset);
		weights[count] = bind_data.weights[state.offset];
		state.offset++;
		count++;
	}
	SetOutputCardinality(output, count);
}

struct HRPBindData : public FunctionData {
	HRPBindData(vector<double> weights_p, vector<string> labels_p)
	    : weights(std::move(weights_p)), labels(std::move(labels_p)) {
	}

	vector<double> weights;
	vector<string> labels;

	unique_ptr<FunctionData> Copy() const override {
		return make_uniq<HRPBindData>(weights, labels);
	}

	bool Equals(const FunctionData &other_p) const override {
		auto &other = other_p.Cast<HRPBindData>();
		return weights == other.weights && labels == other.labels;
	}
};

static unique_ptr<FunctionData> HRPWeightsBind(ClientContext &, TableFunctionBindInput &input,
                                               vector<LogicalType> &return_types, vector<string> &names) {
	names = {"asset_idx", "asset", "weight"};
	return_types = {FinanceLogicalType(LogicalTypeId::BIGINT), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                FinanceLogicalType(LogicalTypeId::DOUBLE)};
	const string function_name = "fin_hrp_weights";
	auto cov = ReadDoubleMatrixValue(RequireArgument(input, 0, function_name, "cov"), function_name, "cov");
	ValidateCovarianceShape(cov, cov.size(), function_name);
	ValidateSymmetric(cov, function_name);
	RequireNonNullArguments(input, 1, function_name);
	vector<string> labels;
	if (input.inputs.size() >= 2) {
		for (auto &label : ListValue::GetChildren(input.inputs[1])) {
			labels.push_back(RequireString(label, function_name, "labels element"));
		}
		if (labels.size() != cov.size()) {
			throw InvalidInputException("%s: labels must have one entry per covariance row", function_name);
		}
	}
	auto linkage = string("single");
	if (input.inputs.size() >= 3) {
		linkage = StringUtil::Lower(RequireString(input.inputs[2], function_name, "linkage"));
		StringUtil::Trim(linkage);
		if (linkage != "single" && linkage != "complete" && linkage != "average" && linkage != "ward") {
			throw InvalidInputException("%s: unknown linkage '%s' (expected single, complete, average, or ward)",
			                            function_name, linkage);
		}
	}
	return make_uniq<HRPBindData>(HierarchicalRiskParityWeights(cov, linkage, function_name), std::move(labels));
}

static void HRPWeightsFunction(ClientContext &, TableFunctionInput &data_p, DataChunk &output) {
	auto &bind_data = data_p.bind_data->Cast<HRPBindData>();
	auto &state = data_p.global_state->Cast<RowsGlobalState>();
	idx_t count = 0;
	auto asset_idx = FlatVector::GetData<int64_t>(output.data[0]);
	auto weights = FlatVector::GetData<double>(output.data[2]);
	while (state.offset < bind_data.weights.size() && count < STANDARD_VECTOR_SIZE) {
		asset_idx[count] = NumericCast<int64_t>(state.offset);
		if (bind_data.labels.empty()) {
			FlatVector::SetNull(output.data[1], count, true);
		} else {
			FlatVector::GetData<string_t>(output.data[1])[count] =
			    StringVector::AddString(output.data[1], bind_data.labels[state.offset]);
		}
		weights[count] = bind_data.weights[state.offset];
		state.offset++;
		count++;
	}
	SetOutputCardinality(output, count);
}

// The frontier is generated lazily: each output chunk solves only its own points.
static constexpr int64_t FINANCE_MAX_FRONTIER_POINTS = 100000;

struct FrontierBindData : public FunctionData {
	FrontierBindData(vector<double> mu_p, FinanceMatrix cov_p, bool allow_short_p, int64_t points_p,
	                 double min_return_p, double max_return_p)
	    : mu(std::move(mu_p)), cov(std::move(cov_p)), allow_short(allow_short_p), points(points_p),
	      min_return(min_return_p), max_return(max_return_p) {
	}

	vector<double> mu;
	FinanceMatrix cov;
	bool allow_short;
	int64_t points;
	double min_return;
	double max_return;

	unique_ptr<FunctionData> Copy() const override {
		return make_uniq<FrontierBindData>(mu, cov, allow_short, points, min_return, max_return);
	}

	bool Equals(const FunctionData &other_p) const override {
		auto &other = other_p.Cast<FrontierBindData>();
		return mu == other.mu && cov == other.cov && allow_short == other.allow_short && points == other.points;
	}
};

static unique_ptr<FunctionData> EfficientFrontierBind(ClientContext &, TableFunctionBindInput &input,
                                                      vector<LogicalType> &return_types, vector<string> &names) {
	names = {"point_idx", "expected_return", "volatility", "weights"};
	return_types = {FinanceLogicalType(LogicalTypeId::BIGINT), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                FinanceLogicalType(LogicalTypeId::DOUBLE),
	                LogicalType::LIST(FinanceLogicalType(LogicalTypeId::DOUBLE))};
	const string function_name = "fin_efficient_frontier";
	auto mu = ReadDoubleListValue(RequireArgument(input, 0, function_name, "mu"), function_name, "mu");
	auto cov = ReadDoubleMatrixValue(RequireArgument(input, 1, function_name, "cov"), function_name, "cov");
	ValidateCovarianceShape(cov, mu.size(), function_name);
	ValidateSymmetric(cov, function_name);
	RequireNonNullArguments(input, 2, function_name);
	int64_t points = 25;
	if (input.inputs.size() >= 3) {
		points = RequireInteger(input.inputs[2], function_name, "points");
	}
	if (points <= 0 || points > FINANCE_MAX_FRONTIER_POINTS) {
		throw InvalidInputException("%s: points must be between 1 and %lld", function_name,
		                            static_cast<long long>(FINANCE_MAX_FRONTIER_POINTS));
	}
	auto allow_short = input.inputs.size() >= 4 && input.inputs[3].GetValue<bool>();
	if (!IsPositiveDefinite(cov)) {
		throw InvalidInputException("%s: covariance matrix must be positive definite", function_name);
	}
	// The efficient branch runs from the global minimum-variance portfolio to the
	// highest expected return (the best single asset when long-only).
	vector<double> gmv;
	if (!FrontierWeights(mu, cov, allow_short, 0.0, false, gmv)) {
		throw InvalidInputException("%s: could not solve the minimum-variance portfolio", function_name);
	}
	auto min_return = DotValues(gmv, mu);
	auto max_return = *std::max_element(mu.begin(), mu.end());
	if (max_return < min_return) {
		max_return = min_return;
	}
	return make_uniq<FrontierBindData>(std::move(mu), std::move(cov), allow_short, points, min_return, max_return);
}

static void EfficientFrontierFunction(ClientContext &, TableFunctionInput &data_p, DataChunk &output) {
	auto &bind_data = data_p.bind_data->Cast<FrontierBindData>();
	auto &state = data_p.global_state->Cast<RowsGlobalState>();
	auto point_idx = FlatVector::GetData<int64_t>(output.data[0]);
	auto expected_return = FlatVector::GetData<double>(output.data[1]);
	auto volatility = FlatVector::GetData<double>(output.data[2]);
	auto &weights_vector = output.data[3];
	auto n = bind_data.mu.size();
	idx_t count = 0;
	auto points = NumericCast<idx_t>(bind_data.points);
	auto list_entries = FlatVector::GetData<list_entry_t>(weights_vector);
	ListVector::Reserve(weights_vector, MinValue<idx_t>(points - MinValue(points, state.offset), STANDARD_VECTOR_SIZE) * n);
	idx_t list_offset = 0;
	while (state.offset < points && count < STANDARD_VECTOR_SIZE) {
		auto i = state.offset++;
		auto t = points == 1 ? 0.0 : static_cast<double>(i) / static_cast<double>(points - 1);
		auto target = bind_data.min_return + t * (bind_data.max_return - bind_data.min_return);
		vector<double> weights;
		bool solved;
		if (t == 0.0) {
			solved = FrontierWeights(bind_data.mu, bind_data.cov, bind_data.allow_short, 0.0, false, weights);
		} else if (!bind_data.allow_short && t == 1.0) {
			// Only assets with the maximum expected return can reach it.
			vector<idx_t> index;
			for (idx_t k = 0; k < n; k++) {
				if (bind_data.mu[k] >= bind_data.max_return) {
					index.push_back(k);
				}
			}
			FinanceMatrix cov_top(index.size(), vector<double>(index.size()));
			for (idx_t r = 0; r < index.size(); r++) {
				for (idx_t c = 0; c < index.size(); c++) {
					cov_top[r][c] = bind_data.cov[index[r]][index[c]];
				}
			}
			vector<double> top_weights;
			solved = FrontierWeights(vector<double>(index.size(), bind_data.max_return), cov_top, false, 0.0, false,
			                         top_weights);
			weights.assign(n, 0.0);
			for (idx_t r = 0; solved && r < index.size(); r++) {
				weights[index[r]] = top_weights[r];
			}
		} else {
			solved = FrontierWeights(bind_data.mu, bind_data.cov, bind_data.allow_short, target, true, weights);
		}
		point_idx[count] = NumericCast<int64_t>(i);
		list_entries[count].offset = list_offset;
		list_entries[count].length = solved ? n : 0;
		if (!solved) {
			FlatVector::SetNull(output.data[1], count, true);
			FlatVector::SetNull(output.data[2], count, true);
			FlatVector::SetNull(weights_vector, count, true);
		} else {
			expected_return[count] = DotValues(weights, bind_data.mu);
			volatility[count] = std::sqrt(std::max(0.0, PortfolioVarianceValue(weights, bind_data.cov)));
			auto child = FlatVector::GetData<double>(ListVector::GetEntry(weights_vector));
			for (idx_t k = 0; k < n; k++) {
				child[list_offset + k] = weights[k];
			}
			list_offset += n;
		}
		count++;
	}
	ListVector::SetListSize(weights_vector, list_offset);
	SetOutputCardinality(output, count);
}
