void RegisterFinanceTableFunctions(ExtensionLoader &loader) {
	loader.RegisterFunction(TableFunction("fin_schema_template", {LogicalType::VARCHAR}, SchemaTemplateFunction,
	                                      SchemaTemplateBind, RowsInit));
	loader.RegisterFunction(TableFunction("fin_validate_schema", {LogicalType::VARCHAR, LogicalType::VARCHAR},
	                                      SchemaTemplateFunction, SchemaTemplateBind, RowsInit));

	auto list_double = LogicalType::LIST(LogicalType::DOUBLE);
	auto list_list_double = LogicalType::LIST(list_double);
	auto list_varchar = LogicalType::LIST(LogicalType::VARCHAR);
	RegisterTableFunctionPrefixes(loader, "fin_portfolio_optimize", {list_double, list_list_double},
	                              {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::BOOLEAN, LogicalType::DOUBLE,
	                               LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	                              PortfolioOptimizeFunction, PortfolioOptimizeBind, RowsInit);
	RegisterTableFunctionPrefixes(loader, "fin_hrp_weights", {list_list_double},
	                              {list_varchar, LogicalType::VARCHAR}, PortfolioOptimizeFunction, HRPWeightsBind,
	                              RowsInit);
	RegisterTableFunctionPrefixes(loader, "fin_efficient_frontier", {list_double, list_list_double},
	                              {LogicalType::INTEGER, LogicalType::BOOLEAN}, EfficientFrontierFunction,
	                              EfficientFrontierBind, RowsInit);

	RegisterBindReplace(loader, "fin_option_chain",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                     LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                    OptionChainBindReplace);
	RegisterBindReplace(loader, "fin_option_chain",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                     LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                    OptionChainBindReplace);

	RegisterBindReplacePrefixes(loader, "fin_bootstrap_curve",
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                            {LogicalType::VARCHAR}, BootstrapCurveBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_curve_bootstrap",
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                            {LogicalType::VARCHAR}, BootstrapCurveBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_portfolio_optimize_table",
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::BOOLEAN, LogicalType::DOUBLE,
	                             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	                            PortfolioOptimizeTableBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_factor_report",
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                             LogicalType::VARCHAR},
	                            {LogicalType::INTEGER}, FactorReportBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_fama_macbeth",
	                            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                             list_varchar},
	                            {LogicalType::INTEGER}, FamaMacbethBindReplace);
	RegisterBindReplacePrefixes(loader, "fin_garch_fit", {LogicalType::VARCHAR, LogicalType::VARCHAR},
	                            {LogicalType::INTEGER, LogicalType::INTEGER, LogicalType::VARCHAR},
	                            GarchFitBindReplace);
	RegisterBindReplace(loader, "fin_calendar", {LogicalType::VARCHAR}, CalendarBindReplace);
	RegisterBindReplace(loader, "fin_calendar", {LogicalType::VARCHAR, LogicalType::DATE}, CalendarBindReplace);
	RegisterBindReplace(loader, "fin_calendar", {LogicalType::VARCHAR, LogicalType::DATE, LogicalType::DATE},
	                    CalendarBindReplace);
	RegisterBindReplace(loader, "fin_rebalance_trades",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                    RebalanceTradesBindReplace);
	RegisterBindReplace(loader, "fin_rebalance_trades",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::DOUBLE},
	                    RebalanceTradesBindReplace);

	RegisterGridFunction(loader, "fin_resample_grid", ResampleGridBindReplace);
	RegisterGridFunction(loader, "fin_last_to_grid", ResampleGridBindReplace);
	RegisterGridFunction(loader, "fin_delta_to_grid", DeltaGridBindReplace);
	RegisterGridFunction(loader, "fin_rate_to_grid", RateGridBindReplace);
	RegisterGridFunction(loader, "fin_changes_to_grid", ChangesGridBindReplace);
	RegisterGridFunction(loader, "fin_resets_to_grid", ResetsGridBindReplace);
	RegisterGridFunction(loader, "fin_predict_linear_to_grid", ResampleGridBindReplace);

	RegisterBindReplace(loader, "fin_tick_bars", {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                    TickBarsBindReplace);
	RegisterBindReplace(loader, "fin_tick_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::INTEGER},
	                    TickBarsBindReplace);
	RegisterBindReplace(loader, "fin_tick_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::BIGINT},
	                    TickBarsBindReplace);
	RegisterBindReplace(loader, "fin_volume_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                     LogicalType::DOUBLE},
	                    VolumeBarsBindReplace);
	RegisterBindReplace(loader, "fin_dollar_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                     LogicalType::DOUBLE},
	                    DollarBarsBindReplace);
	RegisterBindReplace(loader, "fin_imbalance_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR},
	                    ImbalanceBarsBindReplace);
	RegisterBindReplace(loader, "fin_imbalance_bars",
	                    {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
	                     LogicalType::VARCHAR},
	                    ImbalanceBarsBindReplace);
}
