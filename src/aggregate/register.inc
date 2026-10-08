void RegisterFinanceAggregates(ExtensionLoader &loader) {
	RegisterValueAtKeyAggregates(loader);
	RegisterTechnicalAggregates(loader);
	AggregateFunctionSet sortino_set(FinanceFunctionName("fin_sortino"));
	auto sortino = UnaryDoubleAggregate<SortinoState, SortinoOperation>("fin_sortino");
	sortino.SetStateSimpleUpdateCallback(SortinoSimpleUpdate);
	sortino.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	sortino.SetBindCallback(FinNamedArgumentsBind);
	sortino_set.AddFunction(sortino);
	auto sortino_mar =
	    BinaryDoubleAggregate<SortinoState, double, SortinoWithMAROperation>("fin_sortino", FinanceLogicalType(LogicalTypeId::DOUBLE));
	sortino_mar.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	sortino_mar.SetBindCallback(FinNamedArgumentsBind);
	sortino_set.AddFunction(sortino_mar);
	auto sortino_mar_annualization =
	    TernaryDoubleAggregate<SortinoState, double, double, double, SortinoWithMARAnnualizationOperation>(
	        "fin_sortino", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE));
	sortino_mar_annualization.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	sortino_mar_annualization.SetBindCallback(FinNamedArgumentsBind);
	sortino_set.AddFunction(sortino_mar_annualization);
	loader.RegisterFunction(std::move(sortino_set));

	AggregateFunctionSet ewma_variance_set(FinanceFunctionName("fin_ewma_variance"));
	ewma_variance_set.AddFunction(WithNamedArgumentsBind(OrderDependent(
	    UnaryDoubleAggregate<EWMAState, EWMAOperation<false>>("fin_ewma_variance"))));
	ewma_variance_set.AddFunction(WithNamedArgumentsBind(OrderDependent(
	    BinaryDoubleAggregate<EWMAState, double, EWMAWithLambdaOperation<false>>("fin_ewma_variance",
	                                                                            FinanceLogicalType(LogicalTypeId::DOUBLE)))));
	ewma_variance_set.AddFunction(WithNamedArgumentsBind(OrderDependent(
	    TernaryDoubleAggregate<EWMAState, double, double, double, EWMAWithLambdaAnnualizationOperation<false>>(
	        "fin_ewma_variance", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)))));
	loader.RegisterFunction(std::move(ewma_variance_set));

	AggregateFunctionSet ewma_vol_set(FinanceFunctionName("fin_ewma_vol"));
	ewma_vol_set.AddFunction(WithNamedArgumentsBind(OrderDependent(
	    UnaryDoubleAggregate<EWMAState, EWMAOperation<true>>("fin_ewma_vol"))));
	ewma_vol_set.AddFunction(WithNamedArgumentsBind(OrderDependent(
	    BinaryDoubleAggregate<EWMAState, double, EWMAWithLambdaOperation<true>>("fin_ewma_vol", FinanceLogicalType(LogicalTypeId::DOUBLE)))));
	ewma_vol_set.AddFunction(WithNamedArgumentsBind(OrderDependent(
	    TernaryDoubleAggregate<EWMAState, double, double, double, EWMAWithLambdaAnnualizationOperation<true>>(
	        "fin_ewma_vol", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)))));
	loader.RegisterFunction(std::move(ewma_vol_set));

	AggregateFunctionSet bipower_variation_set(FinanceFunctionName("fin_bipower_variation"));
	bipower_variation_set.AddFunction(WithNamedArgumentsBind(OrderDependent(
	    UnaryDoubleAggregate<BipowerVariationState, BipowerVariationOperation>("fin_bipower_variation"))));
	bipower_variation_set.AddFunction(WithNamedArgumentsBind(OrderDependent(
	    BinaryDoubleAggregate<BipowerVariationState, double, BipowerVariationWithAnnualizationOperation>(
	        "fin_bipower_variation", FinanceLogicalType(LogicalTypeId::DOUBLE)))));
	loader.RegisterFunction(std::move(bipower_variation_set));


	RegisterReturnsRiskAggregates(loader);
	RegisterStatisticsAggregates(loader);
}
