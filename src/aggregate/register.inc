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
	ewma_variance_set.AddFunction(UnaryDoubleAggregate<EWMAState, EWMAOperation<false>>("fin_ewma_variance"));
	ewma_variance_set.AddFunction(
	    BinaryDoubleAggregate<EWMAState, double, EWMAWithLambdaOperation<false>>("fin_ewma_variance",
	                                                                            FinanceLogicalType(LogicalTypeId::DOUBLE)));
	ewma_variance_set.AddFunction(
	    TernaryDoubleAggregate<EWMAState, double, double, double, EWMAWithLambdaAnnualizationOperation<false>>(
	        "fin_ewma_variance", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)));
	loader.RegisterFunction(std::move(ewma_variance_set));

	AggregateFunctionSet ewma_vol_set(FinanceFunctionName("fin_ewma_vol"));
	ewma_vol_set.AddFunction(UnaryDoubleAggregate<EWMAState, EWMAOperation<true>>("fin_ewma_vol"));
	ewma_vol_set.AddFunction(
	    BinaryDoubleAggregate<EWMAState, double, EWMAWithLambdaOperation<true>>("fin_ewma_vol", FinanceLogicalType(LogicalTypeId::DOUBLE)));
	ewma_vol_set.AddFunction(
	    TernaryDoubleAggregate<EWMAState, double, double, double, EWMAWithLambdaAnnualizationOperation<true>>(
	        "fin_ewma_vol", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)));
	loader.RegisterFunction(std::move(ewma_vol_set));

	AggregateFunctionSet rsi_set(FinanceFunctionName("fin_rsi"));
	rsi_set.AddFunction(UnaryDoubleAggregate<RSIState, RSIOperation>("fin_rsi"));
	rsi_set.AddFunction(BinaryDoubleAggregate<RSIState, int32_t, RSIWithPeriodOperation>("fin_rsi",
	                                                                                    FinanceLogicalType(LogicalTypeId::INTEGER)));
	loader.RegisterFunction(std::move(rsi_set));

	AggregateFunctionSet current_drawdown_set(FinanceFunctionName("fin_drawdown"));
	current_drawdown_set.AddFunction(UnaryDoubleAggregate<DrawdownState, CurrentDrawdownOperation>("fin_drawdown"));
	current_drawdown_set.AddFunction(
	    BinaryAggregate<DrawdownState, double, double, DrawdownWithInitialNavOperation<CurrentDrawdownOperation>>(
	        "fin_drawdown", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)));
	loader.RegisterFunction(std::move(current_drawdown_set));

	AggregateFunctionSet max_drawdown_set(FinanceFunctionName("fin_max_drawdown"));
	max_drawdown_set.AddFunction(UnaryDoubleAggregate<DrawdownState, MaxDrawdownOperation>("fin_max_drawdown"));
	max_drawdown_set.AddFunction(
	    BinaryAggregate<DrawdownState, double, double, DrawdownWithInitialNavOperation<MaxDrawdownOperation>>(
	        "fin_max_drawdown", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)));
	loader.RegisterFunction(std::move(max_drawdown_set));

	AggregateFunctionSet avg_drawdown_set(FinanceFunctionName("fin_avg_drawdown"));
	avg_drawdown_set.AddFunction(UnaryDoubleAggregate<DrawdownState, AvgDrawdownOperation>("fin_avg_drawdown"));
	avg_drawdown_set.AddFunction(
	    BinaryAggregate<DrawdownState, double, double, DrawdownWithInitialNavOperation<AvgDrawdownOperation>>(
	        "fin_avg_drawdown", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)));
	loader.RegisterFunction(std::move(avg_drawdown_set));

	AggregateFunctionSet drawdown_duration_set(FinanceFunctionName("fin_drawdown_duration"));
	drawdown_duration_set.AddFunction(
	    UnaryBigintAggregate<DrawdownState, DrawdownDurationOperation>("fin_drawdown_duration"));
	drawdown_duration_set.AddFunction(
	    BinaryAggregate<DrawdownState, double, int64_t, DrawdownWithInitialNavOperation<DrawdownDurationOperation>>(
	        "fin_drawdown_duration", FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BIGINT)));
	loader.RegisterFunction(std::move(drawdown_duration_set));

	AggregateFunctionSet ulcer_index_set(FinanceFunctionName("fin_ulcer_index"));
	ulcer_index_set.AddFunction(UnaryDoubleAggregate<DrawdownState, UlcerIndexOperation>("fin_ulcer_index"));
	loader.RegisterFunction(std::move(ulcer_index_set));

	AggregateFunctionSet outlier_count_set(FinanceFunctionName("fin_outlier_count"));
	auto outlier_count =
	    AggregateFunction::UnaryAggregateDestructor<OutlierCountState, double, int64_t, OutlierCountOperation,
	                                                AggregateDestructorType::LEGACY>(FinanceLogicalType(LogicalTypeId::DOUBLE),
	                                                                                 FinanceLogicalType(LogicalTypeId::BIGINT));
	outlier_count.name = FinanceFunctionName("fin_outlier_count");
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
	    AggregateFunction::BinaryAggregate<QuantileSpreadState, double, double, double, QuantileSpreadOperation,
	                                       AggregateDestructorType::LEGACY>(FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                                                                        FinanceLogicalType(LogicalTypeId::DOUBLE));
	quantile_spread.name = FinanceFunctionName("fin_quantile_spread");
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

	auto iv_rank = UnaryDoubleAggregate<IVRangeState, IVRangeOperation<false>>("fin_iv_rank");
	iv_rank.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	loader.RegisterFunction(iv_rank);
	auto iv_percentile = UnaryDoubleAggregate<IVRangeState, IVRangeOperation<true>>("fin_iv_percentile");
	iv_percentile.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	loader.RegisterFunction(iv_percentile);
}
