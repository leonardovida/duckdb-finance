// Single-curve yield-curve bootstrap (fin_bootstrap_curve / fin_curve_bootstrap).
//
// Instruments are processed in maturity order and each one adds a discount-factor
// node. Times are year fractions. Between nodes, and from the implicit node
// (0, 1.0), discount factors are interpolated log-linearly (piecewise-flat
// instantaneous forwards), as in QuantLib's PiecewiseLogLinearDiscount.
//   deposit  simple rate r to T:          DF(T) = 1 / (1 + r T)
//   fra      simple forward f, start s:   DF(T) = DF(s) / (1 + f (T - s)); s must be on the built curve
//   swap     par rate S, fixed frequency k: S * sum(tau_i DF(t_i)) + DF(T) = 1 with payments every 1/k
//            years back from T (a short first period when T*k is not an integer); payment dates past
//            the previous node are interpolated with the unknown DF(T), solved by bisection
//   zero     zero rate in the requested compounding

enum class CurveInstrument : uint8_t { DEPOSIT, FRA, SWAP, ZERO };

struct CurveInputRow {
	CurveInstrument type;
	string type_name;
	double maturity;
	double rate;
	double start;
	bool has_start;
	bool has_instrument;
	string instrument;
};

struct CurveBootstrapState {
	vector<CurveInputRow> *rows;
	int32_t compounding;
	int32_t frequency;
	string *function_name;
};

static constexpr int32_t FINANCE_COMPOUNDING_CONTINUOUS = 0;
static constexpr int32_t FINANCE_COMPOUNDING_SIMPLE = -1;

static int32_t CompoundingCode(const Value &value, const string &function_name) {
	auto compounding = StringUtil::Lower(RequireString(value, function_name, "compounding"));
	StringUtil::Trim(compounding);
	if (compounding == "continuous" || compounding == "cont" || compounding == "cc") {
		return FINANCE_COMPOUNDING_CONTINUOUS;
	}
	if (compounding == "simple") {
		return FINANCE_COMPOUNDING_SIMPLE;
	}
	if (compounding == "periodic" || compounding == "annual" || compounding == "annually") {
		return 1;
	}
	if (compounding == "semiannual" || compounding == "semi-annually" || compounding == "semi") {
		return 2;
	}
	if (compounding == "quarterly" || compounding == "quarter") {
		return 4;
	}
	if (compounding == "monthly" || compounding == "month") {
		return 12;
	}
	if (compounding == "daily" || compounding == "day") {
		return 365;
	}
	throw InvalidInputException("%s: unknown compounding '%s' (expected continuous, simple, periodic, semiannual, "
	                            "quarterly, monthly, or daily)",
	                            function_name, compounding);
}

// Discount factor for a rate quoted with the given compounding over t years.
static double DiscountFromRate(double rate, double t, int32_t compounding) {
	if (compounding == FINANCE_COMPOUNDING_CONTINUOUS) {
		return std::exp(-rate * t);
	}
	if (compounding == FINANCE_COMPOUNDING_SIMPLE) {
		return 1.0 / (1.0 + rate * t);
	}
	auto k = double(compounding);
	auto base = 1.0 + rate / k;
	if (!(base > 0.0)) {
		return std::numeric_limits<double>::quiet_NaN();
	}
	return std::pow(base, -k * t);
}

// Rate with the given compounding implied by a growth factor (1 / discount) over t years.
static double RateFromGrowth(double growth, double t, int32_t compounding) {
	if (compounding == FINANCE_COMPOUNDING_CONTINUOUS) {
		return std::log(growth) / t;
	}
	if (compounding == FINANCE_COMPOUNDING_SIMPLE) {
		return (growth - 1.0) / t;
	}
	auto k = double(compounding);
	return k * (std::pow(growth, 1.0 / (k * t)) - 1.0);
}

struct CurveNodes {
	vector<double> times = {0.0};
	vector<double> discounts = {1.0};

	// Log-linear interpolation; t must not exceed the last node.
	double Discount(double t) const {
		D_ASSERT(t <= times.back());
		auto upper = std::lower_bound(times.begin(), times.end(), t) - times.begin();
		if (times[upper] == t) {
			return discounts[upper];
		}
		auto lower = upper - 1;
		auto w = (t - times[lower]) / (times[upper] - times[lower]);
		return std::exp((1.0 - w) * std::log(discounts[lower]) + w * std::log(discounts[upper]));
	}
};

static double SolveSwapDiscount(const CurveNodes &nodes, double maturity, double rate, int32_t frequency,
                                const string &function_name) {
	// Fixed-leg payment times, backward from maturity.
	vector<double> payments;
	auto period = 1.0 / double(frequency);
	auto periods = maturity * double(frequency);
	if (periods > 100000.0) {
		throw InvalidInputException("%s: swap at maturity %g has more than 100000 fixed-leg payments", function_name,
		                            maturity);
	}
	auto whole = std::round(periods);
	idx_t count = std::fabs(periods - whole) <= 1e-9 * std::max(1.0, periods) ? idx_t(whole) : idx_t(std::ceil(periods));
	if (count == 0) {
		count = 1;
	}
	for (idx_t i = count; i >= 1; i--) {
		payments.push_back(std::max(0.0, maturity - double(i - 1) * period));
	}
	// payments[0] is the first (possibly short) payment, payments.back() == maturity.
	payments.back() = maturity;
	auto last_time = nodes.times.back();
	auto last_discount = nodes.discounts.back();
	auto known_sum = 0.0;
	vector<std::pair<double, double>> pending; // (accrual, interpolation weight on DF(T))
	double previous = 0.0;
	for (auto t : payments) {
		auto accrual = t - previous;
		previous = t;
		if (t <= last_time) {
			known_sum += accrual * nodes.Discount(t);
		} else {
			pending.emplace_back(accrual, (t - last_time) / (maturity - last_time));
		}
	}
	// g(D) = rate * (known_sum + sum accrual * DF_L^(1-w) D^w) + D - 1, increasing in D for rate >= 0.
	auto g = [&](double d) {
		double total = known_sum;
		for (auto &entry : pending) {
			total += entry.first * std::exp((1.0 - entry.second) * std::log(last_discount) + entry.second * std::log(d));
		}
		return rate * total + d - 1.0;
	};
	double lo = 0.0;
	double hi = 1.0;
	if (!(rate * known_sum - 1.0 < 0.0)) {
		throw InvalidInputException("%s: swap at maturity %g implies a non-positive discount factor", function_name,
		                            maturity);
	}
	while (g(hi) < 0.0) {
		hi *= 2.0;
		if (hi > 1e12) {
			throw InvalidInputException("%s: swap at maturity %g has no positive discount-factor solution",
			                            function_name, maturity);
		}
	}
	for (idx_t iteration = 0; iteration < 2000 && hi - lo > 1e-17 * hi; iteration++) {
		auto mid = 0.5 * (lo + hi);
		if (mid <= lo || mid >= hi) {
			break;
		}
		if (g(mid) < 0.0) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	return 0.5 * (lo + hi);
}

static LogicalType CurveBootstrapNodeType() {
	child_list_t<LogicalType> fields = {{"instrument", FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                                    {"instrument_type", FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                                    {"maturity", FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                                    {"rate", FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                                    {"discount_factor", FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                                    {"zero_rate", FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                                    {"forward_rate", FinanceLogicalType(LogicalTypeId::DOUBLE)}};
	return LogicalType::STRUCT(fields);
}

struct CurveOutputNode {
	double discount_factor;
	double zero_rate;
	double forward_rate;
};

// Sorts rows by maturity and returns one output node per row, in that order.
static vector<CurveOutputNode> BootstrapCurveRows(vector<CurveInputRow> &rows, int32_t compounding,
                                                  int32_t frequency, const string &function_name) {
	std::sort(rows.begin(), rows.end(),
	          [](const CurveInputRow &a, const CurveInputRow &b) { return a.maturity < b.maturity; });
	vector<CurveOutputNode> result;
	result.reserve(rows.size());
	CurveNodes nodes;
	for (idx_t i = 0; i < rows.size(); i++) {
		auto &row = rows[i];
		if (i > 0 && rows[i - 1].maturity == row.maturity) {
			throw InvalidInputException("%s: duplicate maturity %g", function_name, row.maturity);
		}
		double discount = 0.0;
		switch (row.type) {
		case CurveInstrument::DEPOSIT:
			discount = 1.0 / (1.0 + row.rate * row.maturity);
			break;
		case CurveInstrument::FRA: {
			if (!row.has_start) {
				throw InvalidInputException("%s: fra at maturity %g needs a start time (start_col)", function_name,
				                            row.maturity);
			}
			if (!(row.start >= 0.0) || !(row.start < row.maturity)) {
				throw InvalidInputException("%s: fra start %g must be in [0, maturity %g)", function_name, row.start,
				                            row.maturity);
			}
			if (row.start > nodes.times.back()) {
				throw InvalidInputException("%s: fra start %g is beyond the bootstrapped curve (last node %g)",
				                            function_name, row.start, nodes.times.back());
			}
			discount = nodes.Discount(row.start) / (1.0 + row.rate * (row.maturity - row.start));
			break;
		}
		case CurveInstrument::SWAP:
			discount = SolveSwapDiscount(nodes, row.maturity, row.rate, frequency, function_name);
			break;
		case CurveInstrument::ZERO:
			discount = DiscountFromRate(row.rate, row.maturity, compounding);
			break;
		}
		if (!(discount > 0.0) || !std::isfinite(discount)) {
			throw InvalidInputException("%s: %s at maturity %g implies a non-positive discount factor", function_name,
			                            row.type_name, row.maturity);
		}
		auto previous_time = nodes.times.back();
		auto previous_discount = nodes.discounts.back();
		nodes.times.push_back(row.maturity);
		nodes.discounts.push_back(discount);
		CurveOutputNode node;
		node.discount_factor = discount;
		node.zero_rate = RateFromGrowth(1.0 / discount, row.maturity, compounding);
		node.forward_rate = RateFromGrowth(previous_discount / discount, row.maturity - previous_time, compounding);
		result.push_back(node);
	}
	return result;
}

static void CurveBootstrapInitialize(const AggregateFunction &, data_ptr_t state_p) {
	auto &state = *reinterpret_cast<CurveBootstrapState *>(state_p);
	state.rows = nullptr;
	state.compounding = FINANCE_COMPOUNDING_CONTINUOUS;
	state.frequency = 1;
	state.function_name = nullptr;
}

static void CurveBootstrapUpdate(Vector inputs[], AggregateInputData &, idx_t, Vector &states, idx_t count) {
	UnifiedVectorFormat formats[8];
	for (idx_t c = 0; c < 8; c++) {
		FinanceToUnifiedFormat(inputs[c], count, formats[c]);
	}
	UnifiedVectorFormat state_format;
	FinanceToUnifiedFormat(states, count, state_format);
	auto state_ptrs = UnifiedVectorFormat::GetData<CurveBootstrapState *>(state_format);
	auto types = UnifiedVectorFormat::GetData<string_t>(formats[0]);
	auto maturities = UnifiedVectorFormat::GetData<double>(formats[1]);
	auto rates = UnifiedVectorFormat::GetData<double>(formats[2]);
	auto starts = UnifiedVectorFormat::GetData<double>(formats[3]);
	auto instruments = UnifiedVectorFormat::GetData<string_t>(formats[4]);
	auto compoundings = UnifiedVectorFormat::GetData<int32_t>(formats[5]);
	auto frequencies = UnifiedVectorFormat::GetData<int32_t>(formats[6]);
	auto names = UnifiedVectorFormat::GetData<string_t>(formats[7]);
	for (idx_t i = 0; i < count; i++) {
		auto &state = *state_ptrs[state_format.sel->get_index(i)];
		auto name_idx = formats[7].sel->get_index(i);
		if (!state.function_name) {
			state.function_name = new string(names[name_idx].GetString());
			state.compounding = compoundings[formats[5].sel->get_index(i)];
			state.frequency = frequencies[formats[6].sel->get_index(i)];
		}
		auto &function_name = *state.function_name;
		auto type_idx = formats[0].sel->get_index(i);
		auto maturity_idx = formats[1].sel->get_index(i);
		auto rate_idx = formats[2].sel->get_index(i);
		auto start_idx = formats[3].sel->get_index(i);
		auto instrument_idx = formats[4].sel->get_index(i);
		if (!formats[0].validity.RowIsValid(type_idx) || !formats[1].validity.RowIsValid(maturity_idx) ||
		    !formats[2].validity.RowIsValid(rate_idx)) {
			throw InvalidInputException("%s: instrument type, maturity, and rate must not be NULL", function_name);
		}
		CurveInputRow row;
		row.type_name = StringUtil::Lower(types[type_idx].GetString());
		StringUtil::Trim(row.type_name);
		if (row.type_name == "deposit") {
			row.type = CurveInstrument::DEPOSIT;
		} else if (row.type_name == "fra") {
			row.type = CurveInstrument::FRA;
		} else if (row.type_name == "swap") {
			row.type = CurveInstrument::SWAP;
		} else if (row.type_name == "zero") {
			row.type = CurveInstrument::ZERO;
		} else {
			throw InvalidInputException("%s: unknown instrument type '%s' (expected deposit, fra, swap, or zero)",
			                            function_name, row.type_name);
		}
		row.maturity = maturities[maturity_idx];
		row.rate = rates[rate_idx];
		if (!(row.maturity > 0.0) || !std::isfinite(row.maturity)) {
			throw InvalidInputException("%s: maturity must be positive and finite", function_name);
		}
		if (!std::isfinite(row.rate)) {
			throw InvalidInputException("%s: rate must be finite", function_name);
		}
		row.has_start = formats[3].validity.RowIsValid(start_idx);
		row.start = row.has_start ? starts[start_idx] : 0.0;
		row.has_instrument = formats[4].validity.RowIsValid(instrument_idx);
		if (row.has_instrument) {
			row.instrument = instruments[instrument_idx].GetString();
		}
		if (!state.rows) {
			state.rows = new vector<CurveInputRow>();
		}
		state.rows->push_back(std::move(row));
	}
}

static void CurveBootstrapCombine(Vector &source, Vector &target, AggregateInputData &, idx_t count) {
	auto sources = FlatVector::GetData<CurveBootstrapState *>(source);
	auto targets = FlatVector::GetData<CurveBootstrapState *>(target);
	for (idx_t i = 0; i < count; i++) {
		auto &src = *sources[i];
		auto &tgt = *targets[i];
		if (src.function_name && !tgt.function_name) {
			tgt.function_name = new string(*src.function_name);
			tgt.compounding = src.compounding;
			tgt.frequency = src.frequency;
		}
		if (!src.rows) {
			continue;
		}
		if (!tgt.rows) {
			tgt.rows = new vector<CurveInputRow>();
		}
		for (auto &row : *src.rows) {
			tgt.rows->push_back(row);
		}
	}
}

static void CurveBootstrapFinalize(Vector &states, AggregateInputData &, Vector &result, idx_t count, idx_t offset) {
	UnifiedVectorFormat state_format;
	FinanceToUnifiedFormat(states, count, state_format);
	auto state_ptrs = UnifiedVectorFormat::GetData<CurveBootstrapState *>(state_format);
	auto list_entries = FlatVector::GetData<list_entry_t>(result);
	for (idx_t i = 0; i < count; i++) {
		auto &state = *state_ptrs[state_format.sel->get_index(i)];
		vector<CurveInputRow> empty;
		auto &rows = state.rows ? *state.rows : empty;
		auto function_name = state.function_name ? *state.function_name : string("fin_bootstrap_curve");
		auto nodes = BootstrapCurveRows(rows, state.compounding, state.frequency, function_name);

		auto list_offset = ListVector::GetListSize(result);
		ListVector::Reserve(result, list_offset + nodes.size());
		auto &child = ListVector::GetEntry(result);
		auto &fields = StructVector::GetEntries(child);
		auto &instrument_vector = *fields[0];
		auto &type_vector = *fields[1];
		auto instruments = FlatVector::GetData<string_t>(instrument_vector);
		auto types = FlatVector::GetData<string_t>(type_vector);
		auto maturities = FlatVector::GetData<double>(*fields[2]);
		auto rates = FlatVector::GetData<double>(*fields[3]);
		auto discounts = FlatVector::GetData<double>(*fields[4]);
		auto zero_rates = FlatVector::GetData<double>(*fields[5]);
		auto forward_rates = FlatVector::GetData<double>(*fields[6]);
		for (idx_t n = 0; n < nodes.size(); n++) {
			auto target = list_offset + n;
			auto &row = rows[n];
			if (row.has_instrument) {
				instruments[target] = StringVector::AddString(instrument_vector, row.instrument);
			} else {
				FlatVector::SetNull(instrument_vector, target, true);
			}
			types[target] = StringVector::AddString(type_vector, row.type_name);
			maturities[target] = row.maturity;
			rates[target] = row.rate;
			discounts[target] = nodes[n].discount_factor;
			zero_rates[target] = nodes[n].zero_rate;
			forward_rates[target] = nodes[n].forward_rate;
		}
		list_entries[i + offset] = list_entry_t(list_offset, nodes.size());
		ListVector::SetListSize(result, list_offset + nodes.size());
	}
}

static void CurveBootstrapDestroy(Vector &states, AggregateInputData &, idx_t count) {
	auto state_ptrs = FlatVector::GetData<CurveBootstrapState *>(states);
	for (idx_t i = 0; i < count; i++) {
		delete state_ptrs[i]->rows;
		delete state_ptrs[i]->function_name;
		state_ptrs[i]->rows = nullptr;
		state_ptrs[i]->function_name = nullptr;
	}
}

static AggregateFunction CurveBootstrapAggregate() {
	AggregateFunction function(
	    "__finance_bootstrap_curve",
	    {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR,
	     LogicalType::INTEGER, LogicalType::INTEGER, LogicalType::VARCHAR},
	    LogicalType::LIST(CurveBootstrapNodeType()), AggregateFunction::StateSize<CurveBootstrapState>,
	    CurveBootstrapInitialize, CurveBootstrapUpdate, CurveBootstrapCombine, CurveBootstrapFinalize,
	    FunctionNullHandling::SPECIAL_HANDLING);
	function.SetStateDestructorCallback(CurveBootstrapDestroy);
	// Rows are sorted by maturity in finalize and duplicate maturities are rejected,
	// so the result does not depend on input order.
	function.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	return function;
}

static unique_ptr<TableRef> BootstrapCurveSubquery(ClientContext &context, TableFunctionBindInput &input,
                                                   const string &function_name) {
	auto table = SqlSourceArg(input, 0, function_name);
	auto type = SqlColumnArg(input, 1, function_name, "type_col");
	auto maturity = SqlColumnArg(input, 2, function_name, "maturity_col");
	auto rate = SqlColumnArg(input, 3, function_name, "rate_col");
	auto compounding =
	    input.inputs.size() >= 5 ? CompoundingCode(input.inputs[4], function_name) : FINANCE_COMPOUNDING_CONTINUOUS;
	auto instrument = OptionalNamedColumn(input, "instrument_col", function_name);
	auto start = OptionalNamedColumn(input, "start_col", function_name);
	int64_t frequency = 1;
	auto frequency_value = NamedArgument(input, "fixed_frequency");
	if (frequency_value) {
		frequency = RequireInteger(*frequency_value, function_name, "fixed_frequency");
		if (frequency < 1 || frequency > 365) {
			throw InvalidInputException("%s: fixed_frequency must be between 1 and 365 payments per year",
			                            function_name);
		}
	}
	auto query = StringUtil::Format(
	    "SELECT unnest(__finance_node) FROM ("
	    "  SELECT unnest(__finance_curve) AS __finance_node FROM ("
	    "    SELECT __finance_bootstrap_curve(%s::VARCHAR, %s::DOUBLE, %s::DOUBLE, %s, %s, %d, %lld, %s) "
	    "      AS __finance_curve FROM %s"
	    "  )"
	    ") ORDER BY __finance_node.maturity",
	    type, maturity, rate, start.empty() ? string("NULL::DOUBLE") : start + "::DOUBLE",
	    instrument.empty() ? string("NULL::VARCHAR") : instrument + "::VARCHAR", compounding,
	    static_cast<long long>(frequency), SqlStringLiteral(function_name), table);
	return ParseSubquery(context, query);
}

static unique_ptr<TableRef> BootstrapCurveBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return BootstrapCurveSubquery(context, input, "fin_bootstrap_curve");
}

static unique_ptr<TableRef> CurveBootstrapBindReplace(ClientContext &context, TableFunctionBindInput &input) {
	return BootstrapCurveSubquery(context, input, "fin_curve_bootstrap");
}

static void RegisterCurveBootstrap(ExtensionLoader &loader, const string &name,
                                   table_function_bind_replace_t bind_replace) {
	for (idx_t optional_count = 0; optional_count <= 1; optional_count++) {
		vector<LogicalType> args(4 + optional_count, LogicalType::VARCHAR);
		TableFunction function(FinanceFunctionName(name), std::move(args), nullptr, nullptr);
		function.bind_replace = bind_replace;
		function.named_parameters["instrument_col"] = LogicalType::VARCHAR;
		function.named_parameters["start_col"] = LogicalType::VARCHAR;
		function.named_parameters["fixed_frequency"] = LogicalType::BIGINT;
		loader.RegisterFunction(std::move(function));
	}
}
