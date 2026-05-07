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

static vector<SchemaRow> SchemaRows(const string &kind) {
	auto normalized = StringUtil::Lower(kind);
	vector<SchemaRow> rows;
	auto add = [&](const string &name, const string &type, bool required, const string &description) {
		rows.push_back({normalized, name, type, required, description});
	};
	if (normalized == "returns") {
		add("asset", "VARCHAR", true, "Asset identifier");
		add("date", "DATE", true, "Observation date");
		add("return", "DOUBLE", true, "Decimal return");
		return rows;
	}
	if (normalized == "option_chain") {
		add("kind", "VARCHAR", true, "call or put");
		add("spot", "DOUBLE", true, "Underlying spot price");
		add("strike", "DOUBLE", true, "Strike price");
		add("ttm", "DOUBLE", true, "Time to maturity in years");
		add("rate", "DOUBLE", true, "Annualized risk-free rate");
		add("vol", "DOUBLE", true, "Annualized volatility");
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
		add("asset", "VARCHAR", true, "Asset identifier");
		add("weight", "DOUBLE", true, "Portfolio weight");
		add("base_currency", "VARCHAR", false, "Base currency");
		return rows;
	}
	add("ts", "TIMESTAMP", true, "Timestamp");
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
	return_types = {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::BOOLEAN,
	                LogicalType::VARCHAR};
	auto kind = input.inputs.empty() || input.inputs[0].IsNull() ? "ohlcv" : input.inputs[0].GetValue<string>();
	return make_uniq<SchemaTemplateBindData>(SchemaRows(kind));
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
		output.data[0].Append(Value(row.schema_kind));
		output.data[1].Append(Value(row.column_name));
		output.data[2].Append(Value(row.logical_type));
		output.data[3].Append(Value::BOOLEAN(row.required));
		output.data[4].Append(Value(row.description));
		count++;
	}
	output.SetCardinality(count);
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
		return weights.size() == other.weights.size();
	}
};

static vector<double> EqualWeights(idx_t n) {
	vector<double> weights(n, n == 0 ? 0.0 : 1.0 / double(n));
	return weights;
}

static unique_ptr<FunctionData> PortfolioOptimizeBind(ClientContext &, TableFunctionBindInput &input,
                                                      vector<LogicalType> &return_types, vector<string> &names) {
	names = {"asset_idx", "weight"};
	return_types = {LogicalType::BIGINT, LogicalType::DOUBLE};
	if (input.inputs.empty() || input.inputs[0].IsNull()) {
		return make_uniq<PortfolioOptimizeBindData>(vector<double>());
	}
	auto &mu_children = ListValue::GetChildren(input.inputs[0]);
	return make_uniq<PortfolioOptimizeBindData>(EqualWeights(mu_children.size()));
}

static void PortfolioOptimizeFunction(ClientContext &, TableFunctionInput &data_p, DataChunk &output) {
	auto &bind_data = data_p.bind_data->Cast<PortfolioOptimizeBindData>();
	auto &state = data_p.global_state->Cast<RowsGlobalState>();
	idx_t count = 0;
	while (state.offset < bind_data.weights.size() && count < STANDARD_VECTOR_SIZE) {
		output.data[0].Append(Value::BIGINT(NumericCast<int64_t>(state.offset)));
		output.data[1].Append(Value::DOUBLE(bind_data.weights[state.offset]));
		state.offset++;
		count++;
	}
	output.SetCardinality(count);
}

struct FrontierRow {
	int64_t point_idx;
	double expected_return;
	double volatility;
};

struct FrontierBindData : public FunctionData {
	explicit FrontierBindData(vector<FrontierRow> rows_p) : rows(std::move(rows_p)) {
	}

	vector<FrontierRow> rows;

	unique_ptr<FunctionData> Copy() const override {
		return make_uniq<FrontierBindData>(rows);
	}

	bool Equals(const FunctionData &other_p) const override {
		auto &other = other_p.Cast<FrontierBindData>();
		return rows.size() == other.rows.size();
	}
};

static double ReadDoubleValue(const Value &value) {
	if (value.IsNull()) {
		throw BinderException("Finance list inputs must not contain NULL values");
	}
	return value.GetValue<double>();
}

static vector<double> ReadDoubleListValue(const Value &value) {
	vector<double> result;
	for (auto &child : ListValue::GetChildren(value)) {
		result.push_back(ReadDoubleValue(child));
	}
	return result;
}

static vector<vector<double>> ReadDoubleMatrixValue(const Value &value) {
	vector<vector<double>> matrix;
	for (auto &row_value : ListValue::GetChildren(value)) {
		matrix.push_back(ReadDoubleListValue(row_value));
	}
	return matrix;
}

static double DotValues(const vector<double> &x, const vector<double> &y) {
	if (x.size() != y.size()) {
		throw BinderException("Vector lengths must match");
	}
	double result = 0.0;
	for (idx_t i = 0; i < x.size(); i++) {
		result += x[i] * y[i];
	}
	return result;
}

static double PortfolioVarianceValue(const vector<double> &weights, const vector<vector<double>> &cov) {
	if (cov.size() != weights.size()) {
		throw BinderException("Covariance matrix dimensions do not match weights");
	}
	vector<double> sigma_w(weights.size(), 0.0);
	for (idx_t r = 0; r < cov.size(); r++) {
		if (cov[r].size() != weights.size()) {
			throw BinderException("Covariance matrix rows must match weights");
		}
		sigma_w[r] = DotValues(cov[r], weights);
	}
	return DotValues(weights, sigma_w);
}

static unique_ptr<FunctionData> HRPWeightsBind(ClientContext &, TableFunctionBindInput &input,
                                               vector<LogicalType> &return_types, vector<string> &names) {
	names = {"asset_idx", "weight"};
	return_types = {LogicalType::BIGINT, LogicalType::DOUBLE};
	if (input.inputs.empty() || input.inputs[0].IsNull()) {
		return make_uniq<PortfolioOptimizeBindData>(vector<double>());
	}
	auto matrix = ReadDoubleMatrixValue(input.inputs[0]);
	return make_uniq<PortfolioOptimizeBindData>(EqualWeights(matrix.size()));
}

static unique_ptr<FunctionData> EfficientFrontierBind(ClientContext &, TableFunctionBindInput &input,
                                                      vector<LogicalType> &return_types, vector<string> &names) {
	names = {"point_idx", "expected_return", "volatility"};
	return_types = {LogicalType::BIGINT, LogicalType::DOUBLE, LogicalType::DOUBLE};
	auto mu = ReadDoubleListValue(input.inputs[0]);
	auto cov = ReadDoubleMatrixValue(input.inputs[1]);
	auto points = input.inputs.size() >= 3 ? input.inputs[2].GetValue<int32_t>() : 25;
	if (points <= 0 || mu.empty()) {
		throw BinderException("fin_efficient_frontier requires positive points and non-empty mu");
	}
	auto weights = EqualWeights(mu.size());
	auto base_return = DotValues(weights, mu);
	auto base_vol = std::sqrt(std::max(0.0, PortfolioVarianceValue(weights, cov)));
	auto minmax = std::minmax_element(mu.begin(), mu.end());
	vector<FrontierRow> rows;
	rows.reserve(NumericCast<idx_t>(points));
	for (int32_t i = 0; i < points; i++) {
		auto t = points == 1 ? 0.0 : static_cast<double>(i) / static_cast<double>(points - 1);
		auto target = *minmax.first + t * (*minmax.second - *minmax.first);
		rows.push_back({i, std::isfinite(target) ? target : base_return, base_vol});
	}
	return make_uniq<FrontierBindData>(std::move(rows));
}

static void EfficientFrontierFunction(ClientContext &, TableFunctionInput &data_p, DataChunk &output) {
	auto &bind_data = data_p.bind_data->Cast<FrontierBindData>();
	auto &state = data_p.global_state->Cast<RowsGlobalState>();
	idx_t count = 0;
	while (state.offset < bind_data.rows.size() && count < STANDARD_VECTOR_SIZE) {
		auto &row = bind_data.rows[state.offset++];
		output.data[0].Append(Value::BIGINT(row.point_idx));
		output.data[1].Append(Value::DOUBLE(row.expected_return));
		output.data[2].Append(Value::DOUBLE(row.volatility));
		count++;
	}
	output.SetCardinality(count);
}
