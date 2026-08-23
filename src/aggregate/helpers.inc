static AggregateFunction NamedAggregateFunction(const string &name, AggregateFunction function) {
	function.name = FinanceFunctionName(name);
	return function;
}

template <class STATE, class OP>
static AggregateFunction WithStateDestructor(AggregateFunction function) {
	function.SetStateDestructorCallback(AggregateFunction::StateDestroy<STATE, OP>);
	return function;
}

static AggregateFunction OrderDependent(AggregateFunction function) {
	function.SetOrderDependent(AggregateOrderDependent::ORDER_DEPENDENT);
	return function;
}

template <class STATE, class OP>
static AggregateFunction UnaryDoubleAggregate(const string &name) {
	auto result = AggregateFunction::UnaryAggregate<STATE, double, double, OP>(FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE));
	return NamedAggregateFunction(name, std::move(result));
}

template <class STATE, class B_TYPE, class OP>
static AggregateFunction BinaryDoubleAggregate(const string &name, const LogicalType &b_type) {
	auto result =
	    AggregateFunction::BinaryAggregate<STATE, double, B_TYPE, double, OP>(FinanceLogicalType(LogicalTypeId::DOUBLE), b_type,
	                                                                         FinanceLogicalType(LogicalTypeId::DOUBLE));
	return NamedAggregateFunction(name, std::move(result));
}

template <class STATE, class B_TYPE, class RESULT_TYPE, class OP>
static AggregateFunction BinaryAggregate(const string &name, const LogicalType &b_type, const LogicalType &return_type) {
	auto result =
	    AggregateFunction::BinaryAggregate<STATE, double, B_TYPE, RESULT_TYPE, OP>(FinanceLogicalType(LogicalTypeId::DOUBLE), b_type,
	                                                                              return_type);
	return NamedAggregateFunction(name, std::move(result));
}

template <class RESULT_TYPE, class OP>
static void RegisterDrawdownAggregate(ExtensionLoader &loader, const string &name,
                                      const LogicalType &return_type) {
	using InitialNavOperation = DrawdownWithInitialNavOperation<OP>;
	AggregateFunctionSet function_set(FinanceFunctionName(name));
	auto unary = AggregateFunction::UnaryAggregate<DrawdownState, double, RESULT_TYPE, OP>(
	    FinanceLogicalType(LogicalTypeId::DOUBLE), return_type);
	function_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, OP>(
	    NamedAggregateFunction(name, std::move(unary)))));
	function_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, InitialNavOperation>(
	    BinaryAggregate<DrawdownState, double, RESULT_TYPE, InitialNavOperation>(
	        name, FinanceLogicalType(LogicalTypeId::DOUBLE), return_type))));
	loader.RegisterFunction(std::move(function_set));
}

template <class STATE, class A_TYPE, class B_TYPE, class C_TYPE, class OP>
static void TernaryScatterUpdate(Vector inputs[], AggregateInputData &, idx_t input_count, Vector &states,
                                 idx_t count) {
	D_ASSERT(input_count == 3);
	UnifiedVectorFormat adata;
	UnifiedVectorFormat bdata;
	UnifiedVectorFormat cdata;
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(inputs[0], count, adata);
	FinanceToUnifiedFormat(inputs[1], count, bdata);
	FinanceToUnifiedFormat(inputs[2], count, cdata);
	FinanceToUnifiedFormat(states, count, sdata);

	auto a_values = UnifiedVectorFormat::GetData<A_TYPE>(adata);
	auto b_values = UnifiedVectorFormat::GetData<B_TYPE>(bdata);
	auto c_values = UnifiedVectorFormat::GetData<C_TYPE>(cdata);
	auto state_values = UnifiedVectorFormat::GetData<STATE *>(sdata);
	for (idx_t i = 0; i < count; i++) {
		auto aidx = adata.sel->get_index(i);
		auto bidx = bdata.sel->get_index(i);
		auto cidx = cdata.sel->get_index(i);
		if (!adata.validity.RowIsValid(aidx) || !bdata.validity.RowIsValid(bidx) || !cdata.validity.RowIsValid(cidx)) {
			continue;
		}
		auto sidx = sdata.sel->get_index(i);
		OP::UpdateValue(*state_values[sidx], static_cast<double>(a_values[aidx]), static_cast<double>(b_values[bidx]),
		                static_cast<double>(c_values[cidx]));
	}
}

template <class STATE, class A_TYPE, class B_TYPE, class C_TYPE, class OP>
static AggregateFunction TernaryDoubleAggregate(const string &name, const LogicalType &a_type,
                                                const LogicalType &b_type, const LogicalType &c_type) {
	AggregateFunction result({a_type, b_type, c_type}, FinanceLogicalType(LogicalTypeId::DOUBLE), AggregateFunction::StateSize<STATE>,
	                         AggregateFunction::StateInitialize<STATE, OP>,
	                         TernaryScatterUpdate<STATE, A_TYPE, B_TYPE, C_TYPE, OP>,
	                         AggregateFunction::StateCombine<STATE, OP>,
	                         AggregateFunction::StateFinalize<STATE, double, OP>,
	                         FunctionNullHandling::DEFAULT_NULL_HANDLING);
	return NamedAggregateFunction(name, std::move(result));
}

template <class STATE, class OP>
static void TernaryDoubleVarcharDoubleScatterUpdate(Vector inputs[], AggregateInputData &, idx_t input_count,
                                                    Vector &states, idx_t count) {
	D_ASSERT(input_count == 3);
	UnifiedVectorFormat xdata;
	UnifiedVectorFormat method_data;
	UnifiedVectorFormat threshold_data;
	UnifiedVectorFormat sdata;
	FinanceToUnifiedFormat(inputs[0], count, xdata);
	FinanceToUnifiedFormat(inputs[1], count, method_data);
	FinanceToUnifiedFormat(inputs[2], count, threshold_data);
	FinanceToUnifiedFormat(states, count, sdata);

	auto x_values = UnifiedVectorFormat::GetData<double>(xdata);
	auto method_values = UnifiedVectorFormat::GetData<string_t>(method_data);
	auto threshold_values = UnifiedVectorFormat::GetData<double>(threshold_data);
	auto state_values = UnifiedVectorFormat::GetData<STATE *>(sdata);
	for (idx_t i = 0; i < count; i++) {
		auto xidx = xdata.sel->get_index(i);
		auto midx = method_data.sel->get_index(i);
		auto tidx = threshold_data.sel->get_index(i);
		if (!xdata.validity.RowIsValid(xidx) || !method_data.validity.RowIsValid(midx) ||
		    !threshold_data.validity.RowIsValid(tidx)) {
			continue;
		}
		auto sidx = sdata.sel->get_index(i);
		OP::UpdateValue(*state_values[sidx], x_values[xidx], method_values[midx].GetString(), threshold_values[tidx]);
	}
}

template <class STATE, class OP>
static AggregateFunction TernaryDoubleVarcharDoubleBigintAggregate(const string &name) {
	AggregateFunction result({FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::BIGINT),
	                         AggregateFunction::StateSize<STATE>,
	                         AggregateFunction::StateInitialize<STATE, OP, AggregateDestructorType::LEGACY>,
	                         TernaryDoubleVarcharDoubleScatterUpdate<STATE, OP>,
	                         AggregateFunction::StateCombine<STATE, OP>,
	                         AggregateFunction::StateFinalize<STATE, int64_t, OP>,
	                         FunctionNullHandling::DEFAULT_NULL_HANDLING, nullptr, nullptr,
	                         AggregateFunction::StateDestroy<STATE, OP>);
	return NamedAggregateFunction(name, std::move(result));
}

template <class STATE, class OP>
static void WeightedQuantileScatterUpdate(Vector inputs[], AggregateInputData &, idx_t input_count, Vector &states,
                                          idx_t count) {
	D_ASSERT(input_count == 4);
	UnifiedVectorFormat value_data;
	UnifiedVectorFormat weight_data;
	UnifiedVectorFormat quantile_data;
	UnifiedVectorFormat method_data;
	UnifiedVectorFormat state_data;
	FinanceToUnifiedFormat(inputs[0], count, value_data);
	FinanceToUnifiedFormat(inputs[1], count, weight_data);
	FinanceToUnifiedFormat(inputs[2], count, quantile_data);
	FinanceToUnifiedFormat(inputs[3], count, method_data);
	FinanceToUnifiedFormat(states, count, state_data);

	auto values = UnifiedVectorFormat::GetData<double>(value_data);
	auto weights = UnifiedVectorFormat::GetData<double>(weight_data);
	auto quantiles = UnifiedVectorFormat::GetData<double>(quantile_data);
	auto methods = UnifiedVectorFormat::GetData<string_t>(method_data);
	auto states_ptr = UnifiedVectorFormat::GetData<STATE *>(state_data);
	for (idx_t i = 0; i < count; i++) {
		auto value_idx = value_data.sel->get_index(i);
		auto weight_idx = weight_data.sel->get_index(i);
		auto quantile_idx = quantile_data.sel->get_index(i);
		auto method_idx = method_data.sel->get_index(i);
		if (!value_data.validity.RowIsValid(value_idx) || !weight_data.validity.RowIsValid(weight_idx) ||
		    !quantile_data.validity.RowIsValid(quantile_idx) || !method_data.validity.RowIsValid(method_idx)) {
			continue;
		}
		auto state_idx = state_data.sel->get_index(i);
		OP::UpdateValue(*states_ptr[state_idx], values[value_idx], weights[weight_idx], quantiles[quantile_idx],
		                methods[method_idx].GetString());
	}
}

template <class STATE, class OP>
static AggregateFunction WeightedQuantileAggregate(const string &name) {
	AggregateFunction result(
	    {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	     FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	    FinanceLogicalType(LogicalTypeId::DOUBLE), AggregateFunction::StateSize<STATE>,
	    AggregateFunction::StateInitialize<STATE, OP, AggregateDestructorType::LEGACY>,
	    WeightedQuantileScatterUpdate<STATE, OP>, AggregateFunction::StateCombine<STATE, OP>,
	    AggregateFunction::StateFinalize<STATE, double, OP>, FunctionNullHandling::DEFAULT_NULL_HANDLING, nullptr,
	    nullptr, AggregateFunction::StateDestroy<STATE, OP>);
	return NamedAggregateFunction(name, std::move(result));
}
