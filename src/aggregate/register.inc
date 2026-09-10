void RegisterFinanceAggregates(ExtensionLoader &loader) {
	AggregateFunctionSet sortino_set(FinanceFunctionName("fin_sortino"));
	auto sortino = UnaryDoubleAggregate<SortinoState, SortinoOperation>("fin_sortino");
	sortino.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	sortino_set.AddFunction(sortino);
	auto sortino_mar =
	    BinaryDoubleAggregate<SortinoState, double, SortinoWithMAROperation>("fin_sortino", FinanceLogicalType(LogicalTypeId::DOUBLE));
	sortino_mar.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	sortino_set.AddFunction(sortino_mar);
	auto sortino_mar_annualization =
	    TernaryDoubleAggregate<SortinoState, double, double, double, SortinoWithMARAnnualizationOperation>(
	        "fin_sortino", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE));
	sortino_mar_annualization.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	sortino_set.AddFunction(sortino_mar_annualization);
	loader.RegisterFunction(std::move(sortino_set));

	AggregateFunctionSet ewma_variance_set(FinanceFunctionName("fin_ewma_variance"));
	ewma_variance_set.AddFunction(OrderDependent(
	    UnaryDoubleAggregate<EWMAState, EWMAOperation<false>>("fin_ewma_variance")));
	ewma_variance_set.AddFunction(OrderDependent(
	    BinaryDoubleAggregate<EWMAState, double, EWMAWithLambdaOperation<false>>("fin_ewma_variance",
	                                                                            FinanceLogicalType(LogicalTypeId::DOUBLE))));
	ewma_variance_set.AddFunction(OrderDependent(
	    TernaryDoubleAggregate<EWMAState, double, double, double, EWMAWithLambdaAnnualizationOperation<false>>(
	        "fin_ewma_variance", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE))));
	loader.RegisterFunction(std::move(ewma_variance_set));

	AggregateFunctionSet ewma_vol_set(FinanceFunctionName("fin_ewma_vol"));
	ewma_vol_set.AddFunction(OrderDependent(
	    UnaryDoubleAggregate<EWMAState, EWMAOperation<true>>("fin_ewma_vol")));
	ewma_vol_set.AddFunction(OrderDependent(
	    BinaryDoubleAggregate<EWMAState, double, EWMAWithLambdaOperation<true>>("fin_ewma_vol", FinanceLogicalType(LogicalTypeId::DOUBLE))));
	ewma_vol_set.AddFunction(OrderDependent(
	    TernaryDoubleAggregate<EWMAState, double, double, double, EWMAWithLambdaAnnualizationOperation<true>>(
	        "fin_ewma_vol", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE))));
	loader.RegisterFunction(std::move(ewma_vol_set));

	AggregateFunctionSet bipower_variation_set(FinanceFunctionName("fin_bipower_variation"));
	bipower_variation_set.AddFunction(OrderDependent(
	    UnaryDoubleAggregate<BipowerVariationState, BipowerVariationOperation>("fin_bipower_variation")));
	bipower_variation_set.AddFunction(OrderDependent(
	    BinaryDoubleAggregate<BipowerVariationState, double, BipowerVariationWithAnnualizationOperation>(
	        "fin_bipower_variation", FinanceLogicalType(LogicalTypeId::DOUBLE))));
	loader.RegisterFunction(std::move(bipower_variation_set));

	AggregateFunctionSet rsi_set(FinanceFunctionName("fin_rsi"));
	rsi_set.AddFunction(OrderDependent(WithStateDestructor<RSIState, RSIOperation>(
	    UnaryDoubleAggregate<RSIState, RSIOperation>("fin_rsi"))));
	rsi_set.AddFunction(OrderDependent(WithStateDestructor<RSIState, RSIWithPeriodOperation>(
	    BinaryDoubleAggregate<RSIState, int32_t, RSIWithPeriodOperation>("fin_rsi",
	                                                                    FinanceLogicalType(LogicalTypeId::INTEGER)))));
	loader.RegisterFunction(std::move(rsi_set));

	RegisterDrawdownAggregate<double, CurrentDrawdownOperation>(
	    loader, "fin_drawdown", FinanceLogicalType(LogicalTypeId::DOUBLE));
	RegisterDrawdownAggregate<double, MaxDrawdownOperation>(
	    loader, "fin_max_drawdown", FinanceLogicalType(LogicalTypeId::DOUBLE));
	RegisterDrawdownAggregate<double, AvgDrawdownOperation>(
	    loader, "fin_avg_drawdown", FinanceLogicalType(LogicalTypeId::DOUBLE));
	RegisterDrawdownAggregate<int64_t, DrawdownDurationOperation>(
	    loader, "fin_drawdown_duration", FinanceLogicalType(LogicalTypeId::BIGINT));

	AggregateFunctionSet ulcer_index_set(FinanceFunctionName("fin_ulcer_index"));
	ulcer_index_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, UlcerIndexOperation>(
	    UnaryDoubleAggregate<DrawdownState, UlcerIndexOperation>("fin_ulcer_index"))));
	loader.RegisterFunction(std::move(ulcer_index_set));

	AggregateFunctionSet outlier_count_set(FinanceFunctionName("fin_outlier_count"));
	auto outlier_count =
	    NamedAggregateFunction("fin_outlier_count",
	                           AggregateFunction::UnaryAggregate<OutlierCountState, double, int64_t, OutlierCountOperation,
	                                                              AggregateDestructorType::LEGACY>(
	                               FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BIGINT)));
	outlier_count.SetStateDestructorCallback(AggregateFunction::StateDestroy<OutlierCountState, OutlierCountOperation>);
	outlier_count_set.AddFunction(outlier_count);
	auto outlier_count_threshold =
	    BinaryAggregate<OutlierCountState, double, int64_t, OutlierCountWithThresholdOperation>(
	        "fin_outlier_count", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BIGINT));
	outlier_count_threshold.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<OutlierCountState, OutlierCountWithThresholdOperation>);
	outlier_count_set.AddFunction(outlier_count_threshold);
	outlier_count_set.AddFunction(
	    TernaryDoubleVarcharDoubleBigintAggregate<OutlierCountState, OutlierCountWithMethodOperation>(
	        "fin_outlier_count"));
	loader.RegisterFunction(std::move(outlier_count_set));

	AggregateFunctionSet quantile_spread_set(FinanceFunctionName("fin_quantile_spread"));
	auto quantile_spread =
	    NamedAggregateFunction("fin_quantile_spread",
	                           AggregateFunction::BinaryAggregate<QuantileSpreadState, double, double, double, QuantileSpreadOperation,
	                                                               AggregateDestructorType::LEGACY>(
	                               FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                               FinanceLogicalType(LogicalTypeId::DOUBLE)));
	quantile_spread.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<QuantileSpreadState, QuantileSpreadOperation>);
	quantile_spread_set.AddFunction(quantile_spread);
	auto quantile_spread_buckets =
	    TernaryDoubleAggregate<QuantileSpreadState, double, double, int32_t, QuantileSpreadWithBucketsOperation>(
	        "fin_quantile_spread", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER));
	quantile_spread_buckets.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<QuantileSpreadState, QuantileSpreadWithBucketsOperation>);
	quantile_spread_set.AddFunction(quantile_spread_buckets);
	loader.RegisterFunction(std::move(quantile_spread_set));

	auto weighted_quantile =
	    WeightedQuantileAggregate<WeightedQuantileState, WeightedQuantileOperation>("finance_weighted_quantile_internal");
	weighted_quantile.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	loader.RegisterFunction(weighted_quantile);

	RegisterRobustStatisticsAggregate<RobustMeanOperation<true>>(loader, "finance_winsorized_mean_internal");
	RegisterRobustStatisticsAggregate<RobustMeanOperation<false>>(loader, "finance_trimmed_mean_internal");
	RegisterRobustStatisticsAggregate<HistoricalCvarOperation>(loader, "finance_cvar_internal");

	auto weighted_mean =
	    TernaryDoubleAggregate<WeightedMomentsState, double, double, double, WeightedMomentsOperation<true>>(
	        "finance_weighted_mean_internal", FinanceLogicalType(LogicalTypeId::DOUBLE),
	        FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE));
	weighted_mean.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	loader.RegisterFunction(weighted_mean);

	auto weighted_variance =
	    TernaryDoubleAggregate<WeightedMomentsState, double, double, double, WeightedMomentsOperation<false>>(
	        "finance_weighted_var_internal", FinanceLogicalType(LogicalTypeId::DOUBLE),
	        FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE));
	weighted_variance.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	loader.RegisterFunction(weighted_variance);

	auto iv_rank = UnaryDoubleAggregate<IVRangeState, IVRangeOperation<false>>("fin_iv_rank");
	iv_rank.SetOrderDependent(AggregateOrderDependent::ORDER_DEPENDENT);
	loader.RegisterFunction(iv_rank);
	auto iv_percentile = UnaryDoubleAggregate<IVRangeState, IVRangeOperation<true>>("fin_iv_percentile");
	iv_percentile.SetOrderDependent(AggregateOrderDependent::ORDER_DEPENDENT);
	loader.RegisterFunction(iv_percentile);
}
