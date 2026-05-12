template <class STATE, class OP>
static AggregateFunction UnaryDoubleAggregate(const string &name) {
	auto result = AggregateFunction::UnaryAggregate<STATE, double, double, OP>(FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE));
	result.name = name;
	return result;
}

template <class STATE, class B_TYPE, class OP>
static AggregateFunction BinaryDoubleAggregate(const string &name, const LogicalType &b_type) {
	auto result =
	    AggregateFunction::BinaryAggregate<STATE, double, B_TYPE, double, OP>(FinanceLogicalType(LogicalTypeId::DOUBLE), b_type,
	                                                                         FinanceLogicalType(LogicalTypeId::DOUBLE));
	result.name = name;
	return result;
}

template <class STATE, class OP>
static AggregateFunction UnaryBigintAggregate(const string &name) {
	auto result = AggregateFunction::UnaryAggregate<STATE, double, int64_t, OP>(FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BIGINT));
	result.name = name;
	return result;
}

template <class STATE, class B_TYPE, class RESULT_TYPE, class OP>
static AggregateFunction BinaryAggregate(const string &name, const LogicalType &b_type, const LogicalType &return_type) {
	auto result =
	    AggregateFunction::BinaryAggregate<STATE, double, B_TYPE, RESULT_TYPE, OP>(FinanceLogicalType(LogicalTypeId::DOUBLE), b_type,
	                                                                              return_type);
	result.name = name;
	return result;
}

template <class STATE, class A_TYPE, class B_TYPE, class C_TYPE, class OP>
static void TernaryScatterUpdate(Vector inputs[], AggregateInputData &, idx_t input_count, Vector &states,
                                 idx_t count) {
	D_ASSERT(input_count == 3);
	UnifiedVectorFormat adata;
	UnifiedVectorFormat bdata;
	UnifiedVectorFormat cdata;
	UnifiedVectorFormat sdata;
	inputs[0].ToUnifiedFormat(count, adata);
	inputs[1].ToUnifiedFormat(count, bdata);
	inputs[2].ToUnifiedFormat(count, cdata);
	states.ToUnifiedFormat(count, sdata);

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
static void TernarySimpleUpdate(Vector inputs[], AggregateInputData &, idx_t input_count, data_ptr_t state,
                                idx_t count) {
	D_ASSERT(input_count == 3);
	UnifiedVectorFormat adata;
	UnifiedVectorFormat bdata;
	UnifiedVectorFormat cdata;
	inputs[0].ToUnifiedFormat(count, adata);
	inputs[1].ToUnifiedFormat(count, bdata);
	inputs[2].ToUnifiedFormat(count, cdata);

	auto a_values = UnifiedVectorFormat::GetData<A_TYPE>(adata);
	auto b_values = UnifiedVectorFormat::GetData<B_TYPE>(bdata);
	auto c_values = UnifiedVectorFormat::GetData<C_TYPE>(cdata);
	auto state_value = reinterpret_cast<STATE *>(state);
	for (idx_t i = 0; i < count; i++) {
		auto aidx = adata.sel->get_index(i);
		auto bidx = bdata.sel->get_index(i);
		auto cidx = cdata.sel->get_index(i);
		if (!adata.validity.RowIsValid(aidx) || !bdata.validity.RowIsValid(bidx) || !cdata.validity.RowIsValid(cidx)) {
			continue;
		}
		OP::UpdateValue(*state_value, static_cast<double>(a_values[aidx]), static_cast<double>(b_values[bidx]),
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
	                         TernarySimpleUpdate<STATE, A_TYPE, B_TYPE, C_TYPE, OP>);
	result.name = name;
	return result;
}

template <class STATE, class OP>
static void TernaryDoubleVarcharDoubleScatterUpdate(Vector inputs[], AggregateInputData &, idx_t input_count,
                                                    Vector &states, idx_t count) {
	D_ASSERT(input_count == 3);
	UnifiedVectorFormat xdata;
	UnifiedVectorFormat method_data;
	UnifiedVectorFormat threshold_data;
	UnifiedVectorFormat sdata;
	inputs[0].ToUnifiedFormat(count, xdata);
	inputs[1].ToUnifiedFormat(count, method_data);
	inputs[2].ToUnifiedFormat(count, threshold_data);
	states.ToUnifiedFormat(count, sdata);

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
static void TernaryDoubleVarcharDoubleSimpleUpdate(Vector inputs[], AggregateInputData &, idx_t input_count,
                                                   data_ptr_t state, idx_t count) {
	D_ASSERT(input_count == 3);
	UnifiedVectorFormat xdata;
	UnifiedVectorFormat method_data;
	UnifiedVectorFormat threshold_data;
	inputs[0].ToUnifiedFormat(count, xdata);
	inputs[1].ToUnifiedFormat(count, method_data);
	inputs[2].ToUnifiedFormat(count, threshold_data);

	auto x_values = UnifiedVectorFormat::GetData<double>(xdata);
	auto method_values = UnifiedVectorFormat::GetData<string_t>(method_data);
	auto threshold_values = UnifiedVectorFormat::GetData<double>(threshold_data);
	auto state_value = reinterpret_cast<STATE *>(state);
	for (idx_t i = 0; i < count; i++) {
		auto xidx = xdata.sel->get_index(i);
		auto midx = method_data.sel->get_index(i);
		auto tidx = threshold_data.sel->get_index(i);
		if (!xdata.validity.RowIsValid(xidx) || !method_data.validity.RowIsValid(midx) ||
		    !threshold_data.validity.RowIsValid(tidx)) {
			continue;
		}
		OP::UpdateValue(*state_value, x_values[xidx], method_values[midx].GetString(), threshold_values[tidx]);
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
	                         TernaryDoubleVarcharDoubleSimpleUpdate<STATE, OP>, nullptr,
	                         AggregateFunction::StateDestroy<STATE, OP>);
	result.name = name;
	return result;
}
