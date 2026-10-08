static AggregateFunction WithNamedArgumentsBind(AggregateFunction function) {
	function.SetBindCallback(FinNamedArgumentsBind);
	return function;
}

template <class OP, class RESULT_TYPE = double>
static void RegisterDrawdownSet(ExtensionLoader &loader, const string &name, const LogicalType &return_type) {
	FinRegisterSet(loader, name,
	               {FinWindowAggregate<DrawdownState, OP, RESULT_TYPE>(name, FinDoubles(1), return_type),
	                FinWindowAggregate<DrawdownState, OP, RESULT_TYPE>(name, FinDoubles(2), return_type)});
}

static void RegisterReturnsRiskAggregates(ExtensionLoader &loader) {
	const auto DOUBLE = FinanceLogicalType(LogicalTypeId::DOUBLE);
	const auto BIGINT = FinanceLogicalType(LogicalTypeId::BIGINT);
	const auto VARCHAR = FinanceLogicalType(LogicalTypeId::VARCHAR);
	const auto BOOLEAN = FinanceLogicalType(LogicalTypeId::BOOLEAN);

	RegisterDrawdownSet<CurrentDrawdownOperation>(loader, "fin_drawdown", DOUBLE);
	RegisterDrawdownSet<MaxDrawdownOperation>(loader, "fin_max_drawdown", DOUBLE);
	RegisterDrawdownSet<AvgDrawdownOperation>(loader, "fin_avg_drawdown", DOUBLE);
	RegisterDrawdownSet<DrawdownDurationOperation, int64_t>(loader, "fin_drawdown_duration", BIGINT);
	FinRegisterSet(loader, "fin_ulcer_index",
	               {FinWindowAggregate<DrawdownState, UlcerIndexOperation>("fin_ulcer_index", FinDoubles(1))});
	FinRegisterSet(loader, "fin_drawdown_at_risk",
	               {FinWindowAggregate<DrawdownRiskState, DrawdownRiskOperation<false>>("fin_drawdown_at_risk",
	                                                                                    FinDoubles(1)),
	                FinWindowAggregate<DrawdownRiskState, DrawdownRiskOperation<false>>("fin_drawdown_at_risk",
	                                                                                    FinDoubles(2))});
	FinRegisterSet(loader, "fin_conditional_drawdown_at_risk",
	               {FinWindowAggregate<DrawdownRiskState, DrawdownRiskOperation<true>>(
	                    "fin_conditional_drawdown_at_risk", FinDoubles(1)),
	                FinWindowAggregate<DrawdownRiskState, DrawdownRiskOperation<true>>(
	                    "fin_conditional_drawdown_at_risk", FinDoubles(2))});

	using Volatility = RiskMomentsOperation<RiskMomentsKind::VOLATILITY>;
	using Sharpe = RiskMomentsOperation<RiskMomentsKind::SHARPE>;
	using DownsideDeviation = RiskMomentsOperation<RiskMomentsKind::DOWNSIDE_DEVIATION>;
	vector<AggregateFunction> volatility, sharpe, downside;
	for (idx_t n = 1; n <= 3; n++) {
		volatility.push_back(FinAggregate<RiskMomentsState, Volatility>("fin_volatility", FinDoubles(n)));
		sharpe.push_back(FinAggregate<RiskMomentsState, Sharpe>("fin_sharpe", FinDoubles(n)));
		downside.push_back(
		    FinAggregate<RiskMomentsState, DownsideDeviation>("fin_downside_deviation", FinDoubles(n)));
	}
	FinRegisterSet(loader, "fin_volatility", std::move(volatility));
	FinRegisterSet(loader, "fin_sharpe", std::move(sharpe));
	FinRegisterSet(loader, "fin_downside_deviation", std::move(downside));

	FinRegisterSet(loader, "fin_total_return",
	               {FinAggregate<TotalReturnState, TotalReturnOperation>("fin_total_return", {DOUBLE}),
	                FinAggregate<TotalReturnState, TotalReturnOperation>("fin_total_return", {DOUBLE, VARCHAR})});
	FinRegisterSet(loader, "fin_beta", {FinAggregate<BetaState, BetaOperation>("fin_beta", {DOUBLE, DOUBLE})});

	vector<AggregateFunction> value_at_risk, conditional_value_at_risk;
	vector<vector<LogicalType>> tail_signatures = {
	    {DOUBLE}, {DOUBLE, DOUBLE}, {DOUBLE, DOUBLE, VARCHAR}, {DOUBLE, DOUBLE, VARCHAR, BOOLEAN}};
	for (auto &signature : tail_signatures) {
		value_at_risk.push_back(FinWindowAggregate<HistoryState, TailRiskOperation<false>>("fin_var", signature));
		conditional_value_at_risk.push_back(
		    FinWindowAggregate<HistoryState, TailRiskOperation<true>>("fin_cvar", signature));
	}
	FinRegisterSet(loader, "fin_var", std::move(value_at_risk));
	FinRegisterSet(loader, "fin_cvar", std::move(conditional_value_at_risk));

	FinRegisterSet(loader, "fin_trimmed_mean",
	               {FinWindowAggregate<HistoryState, RobustMeanOperation<false>>("fin_trimmed_mean", FinDoubles(1)),
	                FinWindowAggregate<HistoryState, RobustMeanOperation<false>>("fin_trimmed_mean", FinDoubles(3))});
	FinRegisterSet(
	    loader, "fin_winsorized_mean",
	    {FinWindowAggregate<HistoryState, RobustMeanOperation<true>>("fin_winsorized_mean", FinDoubles(1)),
	     FinWindowAggregate<HistoryState, RobustMeanOperation<true>>("fin_winsorized_mean", FinDoubles(3))});
	FinRegisterSet(loader, "fin_weighted_quantile",
	               {FinWindowAggregate<WeightedQuantileState, WeightedQuantileOperation>("fin_weighted_quantile",
	                                                                                     FinDoubles(3)),
	                FinWindowAggregate<WeightedQuantileState, WeightedQuantileOperation>(
	                    "fin_weighted_quantile", {DOUBLE, DOUBLE, DOUBLE, VARCHAR})});

	FinRegisterSet(loader, "fin_garch11_forecast",
	               {FinAggregate<Garch11State, Garch11Operation>("fin_garch11_forecast", FinDoubles(4)),
	                FinAggregate<Garch11State, Garch11Operation>("fin_garch11_forecast", FinDoubles(5)),
	                FinAggregate<Garch11State, Garch11Operation>("fin_garch11_forecast", FinDoubles(6))});
	FinRegisterSet(loader, "fin_yang_zhang_vol",
	               {FinAggregate<YangZhangState, YangZhangOperation>("fin_yang_zhang_vol", FinDoubles(4)),
	                FinAggregate<YangZhangState, YangZhangOperation>("fin_yang_zhang_vol", FinDoubles(5))});

	// Outlier count keeps its bulk-append fast paths; windows rebuild one frame.
	AggregateFunctionSet outlier_count_set(FinanceFunctionName("fin_outlier_count"));
	auto outlier_count =
	    NamedAggregateFunction("fin_outlier_count",
	                           AggregateFunction::UnaryAggregate<OutlierCountState, double, int64_t, OutlierCountOperation,
	                                                              AggregateDestructorType::LEGACY>(DOUBLE, BIGINT));
	outlier_count.SetStateDestructorCallback(AggregateFunction::StateDestroy<OutlierCountState, OutlierCountOperation>);
	outlier_count.SetStateSimpleUpdateCallback(OutlierCountSimpleUpdate<false>);
	outlier_count.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	outlier_count.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	outlier_count.SetBindCallback(FinNamedArgumentsBind);
	outlier_count.SetWindowCallback(FinWindow<OutlierCountState, OutlierCountRowOperation, int64_t>);
	outlier_count_set.AddFunction(outlier_count);
	auto outlier_count_threshold =
	    BinaryAggregate<OutlierCountState, double, int64_t, OutlierCountWithThresholdOperation>("fin_outlier_count",
	                                                                                            DOUBLE, BIGINT);
	outlier_count_threshold.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<OutlierCountState, OutlierCountWithThresholdOperation>);
	outlier_count_threshold.SetStateSimpleUpdateCallback(OutlierCountSimpleUpdate<true>);
	outlier_count_threshold.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	outlier_count_threshold.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	outlier_count_threshold.SetBindCallback(FinNamedArgumentsBind);
	outlier_count_threshold.SetWindowCallback(FinWindow<OutlierCountState, OutlierCountRowOperation, int64_t>);
	outlier_count_set.AddFunction(outlier_count_threshold);
	auto outlier_count_method = FinWindowAggregate<OutlierCountState, OutlierCountRowOperation, int64_t>(
	    "fin_outlier_count", {DOUBLE, VARCHAR, DOUBLE}, BIGINT);
	outlier_count_method.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	outlier_count_set.AddFunction(outlier_count_method);
	loader.RegisterFunction(std::move(outlier_count_set));

	AggregateFunctionSet quantile_spread_set(FinanceFunctionName("fin_quantile_spread"));
	auto quantile_spread =
	    NamedAggregateFunction("fin_quantile_spread",
	                           AggregateFunction::BinaryAggregate<QuantileSpreadState, double, double, double, QuantileSpreadOperation,
	                                                               AggregateDestructorType::LEGACY>(DOUBLE, DOUBLE, DOUBLE));
	quantile_spread.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<QuantileSpreadState, QuantileSpreadOperation>);
	quantile_spread.SetBindCallback(FinNamedArgumentsBind);
	quantile_spread_set.AddFunction(quantile_spread);
	auto quantile_spread_buckets =
	    TernaryDoubleAggregate<QuantileSpreadState, double, double, int32_t, QuantileSpreadWithBucketsOperation>(
	        "fin_quantile_spread", DOUBLE, DOUBLE, FinanceLogicalType(LogicalTypeId::INTEGER));
	quantile_spread_buckets.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<QuantileSpreadState, QuantileSpreadWithBucketsOperation>);
	quantile_spread_buckets.SetBindCallback(FinNamedArgumentsBind);
	quantile_spread_set.AddFunction(quantile_spread_buckets);
	loader.RegisterFunction(std::move(quantile_spread_set));

	auto weighted_mean =
	    TernaryDoubleAggregate<WeightedMomentsState, double, double, double, WeightedMomentsOperation<true>>(
	        "finance_weighted_mean_internal", DOUBLE, DOUBLE, DOUBLE);
	weighted_mean.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	loader.RegisterFunction(weighted_mean);

	auto weighted_variance =
	    TernaryDoubleAggregate<WeightedMomentsState, double, double, double, WeightedMomentsOperation<false>>(
	        "finance_weighted_var_internal", DOUBLE, DOUBLE, DOUBLE);
	weighted_variance.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	loader.RegisterFunction(weighted_variance);

	auto iv_rank = UnaryDoubleAggregate<IVRangeState, IVRangeOperation>("fin_iv_rank");
	iv_rank.SetOrderDependent(AggregateOrderDependent::ORDER_DEPENDENT);
	iv_rank.SetBindCallback(FinNamedArgumentsBind);
	loader.RegisterFunction(iv_rank);
	loader.RegisterFunction(
	    FinWindowAggregate<IVPercentileState, IVPercentileOperation>("fin_iv_percentile", FinDoubles(1)));
}

void RegisterFinanceAggregates(ExtensionLoader &loader) {
	AggregateFunctionSet ema_set(FinanceFunctionName("fin_ema"));
	ema_set.AddFunction(OrderDependent(UnaryDoubleAggregate<EMAState, EMAUnaryOperation>("fin_ema")));
	ema_set.AddFunction(OrderDependent(BinaryDoubleAggregate<EMAState, double, EMAOperation>(
	    "fin_ema", FinanceLogicalType(LogicalTypeId::DOUBLE))));
	loader.RegisterFunction(std::move(ema_set));
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

	AggregateFunctionSet rsi_set(FinanceFunctionName("fin_rsi"));
	rsi_set.AddFunction(OrderDependent(WithStateDestructor<RSIState, RSIOperation>(
	    UnaryDoubleAggregate<RSIState, RSIOperation>("fin_rsi"))));
	rsi_set.AddFunction(OrderDependent(WithStateDestructor<RSIState, RSIWithPeriodOperation>(
	    BinaryDoubleAggregate<RSIState, int32_t, RSIWithPeriodOperation>("fin_rsi",
	                                                                    FinanceLogicalType(LogicalTypeId::INTEGER)))));
	loader.RegisterFunction(std::move(rsi_set));

	RegisterReturnsRiskAggregates(loader);
}
