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
	               {FinRankWindowAggregate<DrawdownRiskState, DrawdownRiskOperation<false>>("fin_drawdown_at_risk",
	                                                                                    FinDoubles(1)),
	                FinRankWindowAggregate<DrawdownRiskState, DrawdownRiskOperation<false>>("fin_drawdown_at_risk",
	                                                                                    FinDoubles(2))});
	FinRegisterSet(loader, "fin_conditional_drawdown_at_risk",
	               {FinRankWindowAggregate<DrawdownRiskState, DrawdownRiskOperation<true>>(
	                    "fin_conditional_drawdown_at_risk", FinDoubles(1)),
	                FinRankWindowAggregate<DrawdownRiskState, DrawdownRiskOperation<true>>(
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
		value_at_risk.push_back(FinRankWindowAggregate<HistoryState, TailRiskOperation<false>>("fin_var", signature));
		conditional_value_at_risk.push_back(
		    FinRankWindowAggregate<HistoryState, TailRiskOperation<true>>("fin_cvar", signature));
	}
	FinRegisterSet(loader, "fin_var", std::move(value_at_risk));
	FinRegisterSet(loader, "fin_cvar", std::move(conditional_value_at_risk));

	FinRegisterSet(loader, "fin_trimmed_mean",
	               {FinRankWindowAggregate<HistoryState, RobustMeanOperation<false>>("fin_trimmed_mean", FinDoubles(1)),
	                FinRankWindowAggregate<HistoryState, RobustMeanOperation<false>>("fin_trimmed_mean", FinDoubles(3))});
	FinRegisterSet(
	    loader, "fin_winsorized_mean",
	    {FinRankWindowAggregate<HistoryState, RobustMeanOperation<true>>("fin_winsorized_mean", FinDoubles(1)),
	     FinRankWindowAggregate<HistoryState, RobustMeanOperation<true>>("fin_winsorized_mean", FinDoubles(3))});
	FinRegisterSet(loader, "fin_weighted_quantile",
	               {FinRankWindowAggregate<WeightedQuantileState, WeightedQuantileOperation>("fin_weighted_quantile",
	                                                                                     FinDoubles(3)),
	                FinRankWindowAggregate<WeightedQuantileState, WeightedQuantileOperation>(
	                    "fin_weighted_quantile", {DOUBLE, DOUBLE, DOUBLE, VARCHAR})});

	FinRegisterSet(loader, "fin_garch11_forecast",
	               {FinWindowAggregate<Garch11State, Garch11Operation>("fin_garch11_forecast", FinDoubles(4)),
	                FinWindowAggregate<Garch11State, Garch11Operation>("fin_garch11_forecast", FinDoubles(5)),
	                FinWindowAggregate<Garch11State, Garch11Operation>("fin_garch11_forecast", FinDoubles(6))});
	FinRegisterSet(loader, "fin_stability",
	               {FinWindowAggregate<StabilityState, StabilityOperation>("fin_stability", FinDoubles(1))});
	FinRegisterSet(loader, "fin_yang_zhang_vol",
	               {FinWindowAggregate<YangZhangState, YangZhangOperation>("fin_yang_zhang_vol", FinDoubles(4)),
	                FinWindowAggregate<YangZhangState, YangZhangOperation>("fin_yang_zhang_vol", FinDoubles(5))});

	// Outlier count keeps its bulk-append fast paths; windows rebuild one frame.
	AggregateFunctionSet outlier_count_set(FinanceFunctionName("fin_outlier_count"));
	auto outlier_count =
	    NamedAggregateFunction("fin_outlier_count",
	                           AggregateFunction::UnaryAggregate<OutlierCountState, double, int64_t, OutlierCountOperation,
	                                                              AggregateDestructorType::LEGACY>(DOUBLE, BIGINT));
	outlier_count.SetStateDestructorCallback(AggregateFunction::StateDestroy<OutlierCountState, OutlierCountOperation>);
	outlier_count.SetStateClusterUpdateCallback(
	    FinClusterUpdate<OutlierCountSimpleUpdate<false>,
	                     AggregateFunction::UnaryScatterUpdate<OutlierCountState, double, OutlierCountOperation>>);
	outlier_count.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	outlier_count.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	outlier_count.SetWindowCallback(FinWindow<OutlierCountState, OutlierCountRowOperation, int64_t>);
	outlier_count_set.AddFunction(outlier_count);
	auto outlier_count_threshold =
	    BinaryAggregate<OutlierCountState, double, int64_t, OutlierCountWithThresholdOperation>("fin_outlier_count",
	                                                                                            DOUBLE, BIGINT);
	outlier_count_threshold.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<OutlierCountState, OutlierCountWithThresholdOperation>);
	outlier_count_threshold.SetStateClusterUpdateCallback(
	    FinClusterUpdate<OutlierCountSimpleUpdate<true>,
	                     AggregateFunction::BinaryScatterUpdate<OutlierCountState, double, double,
	                                                            OutlierCountWithThresholdOperation>>);
	outlier_count_threshold.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	outlier_count_threshold.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	outlier_count_threshold.SetWindowCallback(FinWindow<OutlierCountState, OutlierCountRowOperation, int64_t>);
	outlier_count_set.AddFunction(outlier_count_threshold);
	auto outlier_count_method = FinWindowAggregate<OutlierCountState, OutlierCountRowOperation, int64_t>(
	    "fin_outlier_count", {DOUBLE, VARCHAR, DOUBLE}, BIGINT);
	outlier_count_method.SetNullHandling(FunctionNullHandling::SPECIAL_HANDLING);
	outlier_count_set.AddFunction(outlier_count_method);
	FinanceRegisterFunction(loader, std::move(outlier_count_set));

	AggregateFunctionSet quantile_spread_set(FinanceFunctionName("fin_quantile_spread"));
	auto quantile_spread =
	    NamedAggregateFunction("fin_quantile_spread",
	                           AggregateFunction::BinaryAggregate<QuantileSpreadState, double, double, double, QuantileSpreadOperation,
	                                                               AggregateDestructorType::LEGACY>(DOUBLE, DOUBLE, DOUBLE));
	quantile_spread.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<QuantileSpreadState, QuantileSpreadOperation>);
	quantile_spread_set.AddFunction(quantile_spread);
	auto quantile_spread_buckets =
	    TernaryDoubleAggregate<QuantileSpreadState, double, double, int32_t, QuantileSpreadWithBucketsOperation>(
	        "fin_quantile_spread", DOUBLE, DOUBLE, FinanceLogicalType(LogicalTypeId::INTEGER));
	quantile_spread_buckets.SetStateDestructorCallback(
	    AggregateFunction::StateDestroy<QuantileSpreadState, QuantileSpreadWithBucketsOperation>);
	quantile_spread_set.AddFunction(quantile_spread_buckets);
	FinanceRegisterFunction(loader, std::move(quantile_spread_set));

	auto weighted_mean =
	    TernaryDoubleAggregate<WeightedMomentsState, double, double, double, WeightedMomentsOperation<true>>(
	        "finance_weighted_mean_internal", DOUBLE, DOUBLE, DOUBLE);
	weighted_mean.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	FinanceRegisterFunction(loader, weighted_mean);

	auto weighted_variance =
	    TernaryDoubleAggregate<WeightedMomentsState, double, double, double, WeightedMomentsOperation<false>>(
	        "finance_weighted_var_internal", DOUBLE, DOUBLE, DOUBLE);
	weighted_variance.SetOrderDependent(AggregateOrderDependent::NOT_ORDER_DEPENDENT);
	FinanceRegisterFunction(loader, weighted_variance);

	FinanceRegisterFunction(loader, FinWindowAggregate<IVRangeState, IVRangeOperation>("fin_iv_rank", FinDoubles(1)));
	FinanceRegisterFunction(loader, 
	    FinWindowAggregate<IVPercentileState, IVPercentileOperation>("fin_iv_percentile", FinDoubles(1)));
}
