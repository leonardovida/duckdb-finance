static AggregateFunction NamedAggregateFunction(const string &name, AggregateFunction function) {
	function.name = FinanceFunctionName(name);
	return function;
}

template <class STATE, class OP>
static AggregateFunction WithStateDestructor(AggregateFunction function) {
	function.SetStateDestructorCallback(AggregateFunction::StateDestroy<STATE, OP>);
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

template <class STATE, class A_TYPE, class B_TYPE, class C_TYPE, class UPDATE>
static void TernaryScatterUpdateValues(Vector inputs[], idx_t input_count, Vector &states, idx_t count,
                                       UPDATE update) {
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
		update(*state_values[sidx], a_values[aidx], b_values[bidx], c_values[cidx]);
	}
}

template <class STATE, class A_TYPE, class B_TYPE, class C_TYPE, class OP>
static void TernaryScatterUpdate(Vector inputs[], AggregateInputData &, idx_t input_count, Vector &states,
                                 idx_t count) {
	TernaryScatterUpdateValues<STATE, A_TYPE, B_TYPE, C_TYPE>(
	    inputs, input_count, states, count, [](STATE &state, A_TYPE a, B_TYPE b, C_TYPE c) {
		    OP::UpdateValue(state, static_cast<double>(a), static_cast<double>(b), static_cast<double>(c));
	    });
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

