void RegisterFinanceTableFunctions(ExtensionLoader &loader) {
	loader.RegisterFunction(TableFunction(FinanceFunctionName("fin_schema_template"), {FinanceLogicalType(LogicalTypeId::VARCHAR)}, SchemaTemplateFunction,
	                                      SchemaTemplateBind, RowsInit));
	RegisterBindReplace(loader, "fin_validate_schema",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                    ValidateSchemaBindReplace);
	loader.RegisterFunction(BarIndexAggregate());

	auto list_double = LogicalType::LIST(FinanceLogicalType(LogicalTypeId::DOUBLE));
	auto list_list_double = LogicalType::LIST(list_double);
	auto list_varchar = LogicalType::LIST(FinanceLogicalType(LogicalTypeId::VARCHAR));
	RegisterTableFunctionPrefixes(loader, "fin_portfolio_optimize", {list_double, list_list_double},
	                              {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BOOLEAN), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                               FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                              PortfolioOptimizeFunction, PortfolioOptimizeBind, RowsInit);
	RegisterTableFunctionPrefixes(loader, "fin_hrp_weights", {list_list_double},
	                              {list_varchar, FinanceLogicalType(LogicalTypeId::VARCHAR)}, HRPWeightsFunction, HRPWeightsBind,
	                              RowsInit);
	RegisterTableFunctionPrefixes(loader, "fin_efficient_frontier", {list_double, list_list_double},
	                              {FinanceLogicalType(LogicalTypeId::BIGINT), FinanceLogicalType(LogicalTypeId::BOOLEAN)}, EfficientFrontierFunction,
	                              EfficientFrontierBind, RowsInit);

	RegisterBindReplacePrefixes(loader, "fin_option_chain",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                             FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR)}, OptionChainBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_normalize_ohlcv",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                             FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR)}, NormalizeOhlcvBindReplace);
	RegisterBindReplace(loader, "fin_normalize_returns",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                    NormalizeReturnsBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_normalize_option_chain",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                             FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR)}, NormalizeOptionChainBindReplace);

	RegisterBindReplacePrefixes(loader, "fin_bootstrap_curve",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR)}, BootstrapCurveBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_curve_bootstrap",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR)}, CurveBootstrapBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_portfolio_optimize_table",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BOOLEAN), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                            PortfolioOptimizeTableBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_portfolio_return_table",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR)}, PortfolioReturnTableBindReplace);
	RegisterBindReplace(loader, "fin_portfolio_variance_table",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                     FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                    PortfolioVarianceTableBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_factor_report",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                             FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::BIGINT)}, FactorReportBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_fama_macbeth",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                             list_varchar},
	                            {FinanceLogicalType(LogicalTypeId::BIGINT)}, FamaMacbethBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_garch_fit", {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::BIGINT), FinanceLogicalType(LogicalTypeId::BIGINT), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            GarchFitBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_calendar", {FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE)},
	                            CalendarBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_rebalance_trades",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::DOUBLE)}, RebalanceTradesBindReplace,
	                            {"asset_col", "weight_col", "price_col"});

	RegisterGridFunction(loader, "fin_resample_grid", ResampleGridBindReplace);
	RegisterGridFunction(loader, "fin_last_to_grid", ResampleGridBindReplace);
	RegisterGridFunction(loader, "fin_delta_to_grid", DeltaGridBindReplace);
	RegisterGridFunction(loader, "fin_rate_to_grid", RateGridBindReplace);
	RegisterGridFunction(loader, "fin_changes_to_grid", ChangesGridBindReplace);
	RegisterGridFunction(loader, "fin_resets_to_grid", ResetsGridBindReplace);
	auto varchar = FinanceLogicalType(LogicalTypeId::VARCHAR);
	auto timestamp = FinanceLogicalType(LogicalTypeId::TIMESTAMP);
	auto interval = FinanceLogicalType(LogicalTypeId::INTERVAL);
	auto double_type = FinanceLogicalType(LogicalTypeId::DOUBLE);
	RegisterBindReplacePrefixes(loader, "fin_predict_linear_to_grid",
	                            {varchar, varchar, varchar, timestamp, timestamp, interval, interval}, {interval},
	                            PredictLinearGridBindReplace, {"asset_col", "seq_col"});

	RegisterBindReplacePrefixes(loader, "fin_tick_bars", {varchar, varchar, varchar}, {double_type},
	                            TickBarsBindReplace, {"asset_col", "seq_col", "volume_col"});
	RegisterBindReplace(loader, "fin_volume_bars", {varchar, varchar, varchar, varchar, double_type},
	                    VolumeBarsBindReplace, {"asset_col", "seq_col"});
	RegisterBindReplace(loader, "fin_dollar_bars", {varchar, varchar, varchar, varchar, double_type},
	                    DollarBarsBindReplace, {"asset_col", "seq_col"});
	RegisterBindReplacePrefixes(loader, "fin_imbalance_bars", {varchar, varchar, varchar, varchar, double_type},
	                            {varchar}, ImbalanceBarsBindReplace, {"asset_col", "seq_col"});
}
