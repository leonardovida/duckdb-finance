void RegisterFinanceAggregates(ExtensionLoader &loader) {
	RegisterValueAtKeyAggregates(loader);
	RegisterTechnicalAggregates(loader);
	RegisterTechnicalVolumeIndicators(loader);
	RegisterMarketVolumeAggregates(loader);
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

	FinRegisterSet(loader, "fin_ewma_variance",
	               {FinWindowAggregate<EWMAState, EWMAOperation<false>>("fin_ewma_variance", FinDoubles(1)),
	                FinWindowAggregate<EWMAState, EWMAOperation<false>>("fin_ewma_variance", FinDoubles(2)),
	                FinWindowAggregate<EWMAState, EWMAOperation<false>>("fin_ewma_variance", FinDoubles(3))});
	FinRegisterSet(loader, "fin_ewma_vol",
	               {FinWindowAggregate<EWMAState, EWMAOperation<true>>("fin_ewma_vol", FinDoubles(1)),
	                FinWindowAggregate<EWMAState, EWMAOperation<true>>("fin_ewma_vol", FinDoubles(2)),
	                FinWindowAggregate<EWMAState, EWMAOperation<true>>("fin_ewma_vol", FinDoubles(3))});
	FinRegisterSet(loader, "fin_bipower_variation",
	               {FinWindowAggregate<BipowerVariationState, BipowerVariationOperation>("fin_bipower_variation",
	                                                                                     FinDoubles(1)),
	                FinWindowAggregate<BipowerVariationState, BipowerVariationOperation>("fin_bipower_variation",
	                                                                                     FinDoubles(2))});

	RegisterReturnsRiskAggregates(loader);
	RegisterStatisticsAggregates(loader);
}
