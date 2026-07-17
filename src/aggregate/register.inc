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

	AggregateFunctionSet rsi_set(FinanceFunctionName("fin_rsi"));
	rsi_set.AddFunction(OrderDependent(WithStateDestructor<RSIState, RSIOperation>(
	    UnaryDoubleAggregate<RSIState, RSIOperation>("fin_rsi"))));
	rsi_set.AddFunction(OrderDependent(WithStateDestructor<RSIState, RSIWithPeriodOperation>(
	    BinaryDoubleAggregate<RSIState, int32_t, RSIWithPeriodOperation>("fin_rsi",
	                                                                    FinanceLogicalType(LogicalTypeId::INTEGER)))));
	loader.RegisterFunction(std::move(rsi_set));

	AggregateFunctionSet current_drawdown_set(FinanceFunctionName("fin_drawdown"));
	current_drawdown_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, CurrentDrawdownOperation>(
	    UnaryDoubleAggregate<DrawdownState, CurrentDrawdownOperation>("fin_drawdown"))));
	current_drawdown_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, DrawdownWithInitialNavOperation<CurrentDrawdownOperation>>(
	    BinaryAggregate<DrawdownState, double, double, DrawdownWithInitialNavOperation<CurrentDrawdownOperation>>(
	        "fin_drawdown", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)))));
	loader.RegisterFunction(std::move(current_drawdown_set));

	AggregateFunctionSet max_drawdown_set(FinanceFunctionName("fin_max_drawdown"));
	max_drawdown_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, MaxDrawdownOperation>(
	    UnaryDoubleAggregate<DrawdownState, MaxDrawdownOperation>("fin_max_drawdown"))));
	max_drawdown_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, DrawdownWithInitialNavOperation<MaxDrawdownOperation>>(
	    BinaryAggregate<DrawdownState, double, double, DrawdownWithInitialNavOperation<MaxDrawdownOperation>>(
	        "fin_max_drawdown", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)))));
	loader.RegisterFunction(std::move(max_drawdown_set));

	AggregateFunctionSet avg_drawdown_set(FinanceFunctionName("fin_avg_drawdown"));
	avg_drawdown_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, AvgDrawdownOperation>(
	    UnaryDoubleAggregate<DrawdownState, AvgDrawdownOperation>("fin_avg_drawdown"))));
	avg_drawdown_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, DrawdownWithInitialNavOperation<AvgDrawdownOperation>>(
	    BinaryAggregate<DrawdownState, double, double, DrawdownWithInitialNavOperation<AvgDrawdownOperation>>(
	        "fin_avg_drawdown", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)))));
	loader.RegisterFunction(std::move(avg_drawdown_set));

	AggregateFunctionSet drawdown_duration_set(FinanceFunctionName("fin_drawdown_duration"));
	drawdown_duration_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, DrawdownDurationOperation>(
	    UnaryBigintAggregate<DrawdownState, DrawdownDurationOperation>("fin_drawdown_duration"))));
	drawdown_duration_set.AddFunction(OrderDependent(WithStateDestructor<DrawdownState, DrawdownWithInitialNavOperation<DrawdownDurationOperation>>(
	    BinaryAggregate<DrawdownState, double, int64_t, DrawdownWithInitialNavOperation<DrawdownDurationOperation>>(
	        "fin_drawdown_duration", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BIGINT)))));
	loader.RegisterFunction(std::move(drawdown_duration_set));

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

	auto winsorized_mean =
	    TernaryDoubleAggregate<RobustStatisticsState, double, double, double, RobustMeanOperation<true>>(
	        "finance_winsorized_mean_internal", FinanceLogicalType(LogicalTypeId::DOUBLE),
	        FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE));
	winsorized_mean.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	winsorized_mean.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<RobustStatisticsState, RobustMeanOperation<true>>);
	loader.RegisterFunction(winsorized_mean);

	auto trimmed_mean = TernaryDoubleAggregate<RobustStatisticsState, double, double, double, RobustMeanOperation<false>>(
	    "finance_trimmed_mean_internal", FinanceLogicalType(LogicalTypeId::DOUBLE),
	    FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE));
	trimmed_mean.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	trimmed_mean.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<RobustStatisticsState, RobustMeanOperation<false>>);
	loader.RegisterFunction(trimmed_mean);

	auto historical_cvar =
	    TernaryDoubleAggregate<RobustStatisticsState, double, double, double, HistoricalCvarOperation>(
	        "finance_cvar_internal", FinanceLogicalType(LogicalTypeId::DOUBLE),
	        FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE));
	historical_cvar.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	historical_cvar.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<RobustStatisticsState, HistoricalCvarOperation>);
	loader.RegisterFunction(historical_cvar);

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
