void RegisterFinanceTableFunctions(ExtensionLoader &loader) {
	loader.RegisterFunction(TableFunction("fin_schema_template", {FinanceLogicalType(LogicalTypeId::VARCHAR)}, SchemaTemplateFunction,
	                                      SchemaTemplateBind, RowsInit));
	loader.RegisterFunction(TableFunction("fin_validate_schema", {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                                      SchemaTemplateFunction, SchemaTemplateBind, RowsInit));

	auto list_double = LogicalType::LIST(FinanceLogicalType(LogicalTypeId::DOUBLE));
	auto list_list_double = LogicalType::LIST(list_double);
	auto list_varchar = LogicalType::LIST(FinanceLogicalType(LogicalTypeId::VARCHAR));
	RegisterTableFunctionPrefixes(loader, "fin_portfolio_optimize", {list_double, list_list_double},
	                              {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BOOLEAN), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                               FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                              PortfolioOptimizeFunction, PortfolioOptimizeBind, RowsInit);
	RegisterTableFunctionPrefixes(loader, "fin_hrp_weights", {list_list_double},
	                              {list_varchar, FinanceLogicalType(LogicalTypeId::VARCHAR)}, PortfolioOptimizeFunction, HRPWeightsBind,
	                              RowsInit);
	RegisterTableFunctionPrefixes(loader, "fin_efficient_frontier", {list_double, list_list_double},
	                              {FinanceLogicalType(LogicalTypeId::INTEGER), FinanceLogicalType(LogicalTypeId::BOOLEAN)}, EfficientFrontierFunction,
	                              EfficientFrontierBind, RowsInit);

	RegisterBindReplace(loader, "fin_option_chain",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                     FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                    OptionChainBindReplace);
	RegisterBindReplace(loader, "fin_option_chain",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                     FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                    OptionChainBindReplace);

	RegisterBindReplacePrefixes(loader, "fin_bootstrap_curve",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR)}, BootstrapCurveBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_curve_bootstrap",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR)}, BootstrapCurveBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_portfolio_optimize_table",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BOOLEAN), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                            PortfolioOptimizeTableBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_factor_report",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                             FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::INTEGER)}, FactorReportBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_fama_macbeth",
	                            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                             list_varchar},
	                            {FinanceLogicalType(LogicalTypeId::INTEGER)}, FamaMacbethBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_garch_fit", {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            {FinanceLogicalType(LogicalTypeId::INTEGER), FinanceLogicalType(LogicalTypeId::INTEGER), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                            GarchFitBindReplace);
	RegisterBindReplace(loader, "fin_calendar", {FinanceLogicalType(LogicalTypeId::VARCHAR)}, CalendarBindReplace);
	RegisterBindReplace(loader, "fin_calendar", {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DATE)}, CalendarBindReplace);
	RegisterBindReplace(loader, "fin_calendar", {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE)},
	                    CalendarBindReplace);
	RegisterBindReplace(loader, "fin_rebalance_trades",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                    RebalanceTradesBindReplace);
	RegisterBindReplace(loader, "fin_rebalance_trades",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                    RebalanceTradesBindReplace);

	RegisterGridFunction(loader, "fin_resample_grid", ResampleGridBindReplace);
	RegisterGridFunction(loader, "fin_last_to_grid", ResampleGridBindReplace);
	RegisterGridFunction(loader, "fin_delta_to_grid", DeltaGridBindReplace);
	RegisterGridFunction(loader, "fin_rate_to_grid", RateGridBindReplace);
	RegisterGridFunction(loader, "fin_changes_to_grid", ChangesGridBindReplace);
	RegisterGridFunction(loader, "fin_resets_to_grid", ResetsGridBindReplace);
	RegisterGridFunction(loader, "fin_predict_linear_to_grid", ResampleGridBindReplace);

	RegisterBindReplace(loader, "fin_tick_bars", {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                    TickBarsBindReplace);
	RegisterBindReplace(loader, "fin_tick_bars",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::INTEGER)},
	                    TickBarsBindReplace);
	RegisterBindReplace(loader, "fin_tick_bars",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::BIGINT)},
	                    TickBarsBindReplace);
	RegisterBindReplace(loader, "fin_volume_bars",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                     FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                    VolumeBarsBindReplace);
	RegisterBindReplace(loader, "fin_dollar_bars",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                     FinanceLogicalType(LogicalTypeId::DOUBLE)},
	                    DollarBarsBindReplace);
	RegisterBindReplace(loader, "fin_imbalance_bars",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                    ImbalanceBarsBindReplace);
	RegisterBindReplace(loader, "fin_imbalance_bars",
	                    {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR),
	                     FinanceLogicalType(LogicalTypeId::VARCHAR)},
	                    ImbalanceBarsBindReplace);
}
