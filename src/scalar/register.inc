void RegisterFinanceScalars(ExtensionLoader &loader) {
	loader.RegisterFunction(ScalarFunction("fin_version", {}, LogicalType::VARCHAR, FinanceVersionFunction));

	AddScalar(loader, "fin_norm_pdf", {LogicalType::DOUBLE}, LogicalType::DOUBLE, NormPDFFunction);
	AddScalar(loader, "fin_norm_cdf", {LogicalType::DOUBLE}, LogicalType::DOUBLE, NormCDFFunction);
	AddScalar(loader, "fin_norm_inv", {LogicalType::DOUBLE}, LogicalType::DOUBLE, NormInvFunction);
	AddScalar(loader, "fin_student_t_cdf", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          StudentTCdfFunction);
	AddScalar(loader, "fin_student_t_inv", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          StudentTInvFunction);
	AddScalar(loader, "fin_chi2_cdf", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, Chi2CdfFunction);
	AddScalar(loader, "fin_chi2_inv", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, Chi2InvFunction);

	ScalarFunctionSet safe_div("fin_safe_div");
	AddOverload(safe_div, {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, SafeDivFunction);
	AddOverload(safe_div, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            SafeDivFunction);
	loader.RegisterFunction(std::move(safe_div));
	AddScalar(loader, "fin_bps", {LogicalType::DOUBLE}, LogicalType::DOUBLE, BpsFunction);
	AddScalar(loader, "fin_from_bps", {LogicalType::DOUBLE}, LogicalType::DOUBLE, FromBpsFunction);
	AddScalar(loader, "fin_clip", {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          ClipFunction);
	ScalarFunctionSet round_tick("fin_round_to_tick");
	AddOverload(round_tick, {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, RoundToTickFunction);
	AddOverload(round_tick, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR}, LogicalType::DOUBLE,
	            RoundToTickFunction);
	loader.RegisterFunction(std::move(round_tick));

	ScalarFunctionSet yearfrac("fin_yearfrac");
	AddOverload(yearfrac, {LogicalType::DATE, LogicalType::DATE}, LogicalType::DOUBLE, YearFracFunction);
	AddOverload(yearfrac, {LogicalType::DATE, LogicalType::DATE, LogicalType::VARCHAR}, LogicalType::DOUBLE,
	            YearFracFunction);
	loader.RegisterFunction(std::move(yearfrac));

	ScalarFunctionSet discount("fin_discount_factor");
	AddOverload(discount, {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, DiscountFactorFunction);
	AddOverload(discount, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR}, LogicalType::DOUBLE,
	            DiscountFactorFunction);
	AddOverload(discount, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR, LogicalType::INTEGER},
	            LogicalType::DOUBLE, DiscountFactorFunction);
	loader.RegisterFunction(std::move(discount));

	ScalarFunctionSet rate_from_discount("fin_rate_from_discount");
	AddOverload(rate_from_discount, {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            RateFromDiscountFunction);
	AddOverload(rate_from_discount, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR}, LogicalType::DOUBLE,
	            RateFromDiscountFunction);
	AddOverload(rate_from_discount,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR, LogicalType::INTEGER},
	            LogicalType::DOUBLE, RateFromDiscountFunction);
	loader.RegisterFunction(std::move(rate_from_discount));
	ScalarFunctionSet forward_rate("fin_forward_rate");
	AddOverload(forward_rate,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, ForwardRateFunction);
	AddOverload(forward_rate,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::VARCHAR},
	            LogicalType::DOUBLE, ForwardRateFunction);
	loader.RegisterFunction(std::move(forward_rate));
	ScalarFunctionSet pv("fin_present_value");
	AddOverload(pv, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            PresentValueFunction);
	AddOverload(pv, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR},
	            LogicalType::DOUBLE, PresentValueFunction);
	loader.RegisterFunction(std::move(pv));
	ScalarFunctionSet fv("fin_future_value");
	AddOverload(fv, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            FutureValueFunction);
	AddOverload(fv, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR},
	            LogicalType::DOUBLE, FutureValueFunction);
	loader.RegisterFunction(std::move(fv));

	ScalarFunctionSet annuity("fin_annuity_payment");
	AddOverload(annuity, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            AnnuityPaymentFunction);
	AddOverload(annuity, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, AnnuityPaymentFunction);
	AddOverload(annuity,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::VARCHAR},
	            LogicalType::DOUBLE, AnnuityPaymentFunction);
	loader.RegisterFunction(std::move(annuity));

	ScalarFunctionSet bond_price("fin_bond_price");
	AddOverload(bond_price, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            BondPriceFunction);
	AddOverload(bond_price, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BondPriceFunction);
	AddOverload(bond_price,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BondPriceFunction);
	loader.RegisterFunction(std::move(bond_price));
	ScalarFunctionSet bond_ytm("fin_bond_ytm");
	AddOverload(bond_ytm, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            BondYTMFunction);
	AddOverload(bond_ytm, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BondYTMFunction);
	AddOverload(bond_ytm,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BondYTMFunction);
	loader.RegisterFunction(std::move(bond_ytm));
	ScalarFunctionSet duration("fin_bond_duration");
	AddOverload(duration, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            BondDurationFunction);
	AddOverload(duration, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BondDurationFunction);
	AddOverload(duration,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BondDurationFunction);
	AddOverload(duration,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE, LogicalType::VARCHAR},
	            LogicalType::DOUBLE, BondDurationFunction);
	loader.RegisterFunction(std::move(duration));
	ScalarFunctionSet convexity("fin_bond_convexity");
	AddOverload(convexity, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            BondConvexityFunction);
	AddOverload(convexity, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BondConvexityFunction);
	AddOverload(convexity,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BondConvexityFunction);
	loader.RegisterFunction(std::move(convexity));
	ScalarFunctionSet dv01("fin_dv01");
	AddOverload(dv01, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE, DV01Function);
	AddOverload(dv01, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, DV01Function);
	AddOverload(dv01,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, DV01Function);
	loader.RegisterFunction(std::move(dv01));
	ScalarFunctionSet accrued("fin_accrued_interest");
	AddOverload(accrued, {LogicalType::DATE, LogicalType::DATE, LogicalType::DATE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, AccruedInterestFunction);
	AddOverload(accrued,
	            {LogicalType::DATE, LogicalType::DATE, LogicalType::DATE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, AccruedInterestFunction);
	AddOverload(accrued,
	            {LogicalType::DATE, LogicalType::DATE, LogicalType::DATE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::VARCHAR},
	            LogicalType::DOUBLE, AccruedInterestFunction);
	loader.RegisterFunction(std::move(accrued));
	auto list_double = LogicalType::LIST(LogicalType::DOUBLE);
	auto list_date = LogicalType::LIST(LogicalType::DATE);
	ScalarFunctionSet npv("fin_npv");
	AddOverload(npv, {LogicalType::DOUBLE, list_double}, LogicalType::DOUBLE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "npv"); });
	AddOverload(npv, {list_double, list_double, LogicalType::DOUBLE}, LogicalType::DOUBLE, NPVWithTimesFunction);
	AddOverload(npv, {list_double, list_double, LogicalType::DOUBLE, LogicalType::VARCHAR}, LogicalType::DOUBLE,
	            NPVWithTimesFunction);
	loader.RegisterFunction(std::move(npv));
	ScalarFunctionSet irr("fin_irr");
	AddOverload(irr, {list_double}, LogicalType::DOUBLE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "irr"); });
	AddOverload(irr, {list_double, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "irr"); });
	loader.RegisterFunction(std::move(irr));
	AddScalar(loader, "fin_mirr", {list_double, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "mirr"); });
	ScalarFunctionSet xirr("fin_xirr");
	AddOverload(xirr, {list_double, list_date}, LogicalType::DOUBLE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "xirr"); });
	AddOverload(xirr, {list_double, list_date, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "xirr"); });
	loader.RegisterFunction(std::move(xirr));
	AddScalar(loader, "fin_interpolate_curve", {list_double, list_double, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CurveListFunction(args, state, result, "zero"); });
	AddScalar(loader, "fin_curve_zero_rate", {list_double, list_double, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CurveListFunction(args, state, result, "zero"); });
	AddScalar(loader, "fin_curve_discount_factor", {list_double, list_double, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CurveListFunction(args, state, result, "discount"); });
	AddScalar(loader, "fin_swap_rate", {list_double, list_double}, LogicalType::DOUBLE, SwapRateFunction);
	AddScalar(loader, "fin_fra_rate",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &, Vector &result) {
		          ExecuteDouble(args, result, [](const PreparedInputs &input, idx_t row) {
			          double t1 = input.GetDouble(2, row);
			          double t2 = input.GetDouble(3, row);
			          if (!(t2 > t1)) {
				          throw InvalidInputException("fin_fra_rate requires t2 > t1");
			          }
			          return (input.GetDouble(1, row) * t2 - input.GetDouble(0, row) * t1) / (t2 - t1);
		          });
	          });

	AddScalar(loader, "fin_option_payoff", {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE, OptionPayoffFunction);
	ScalarFunctionSet forward_price("fin_forward_price");
	AddOverload(forward_price, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            ForwardPriceFunction);
	AddOverload(forward_price,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, ForwardPriceFunction);
	loader.RegisterFunction(std::move(forward_price));
	ScalarFunctionSet parity("fin_put_call_parity");
	AddOverload(parity,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, PutCallParityFunction);
	AddOverload(parity,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, PutCallParityFunction);
	loader.RegisterFunction(std::move(parity));
	ScalarFunctionSet d1("fin_bsm_d1");
	AddOverload(d1, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                 LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMD1Function);
	AddOverload(d1, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                 LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMD1Function);
	loader.RegisterFunction(std::move(d1));
	ScalarFunctionSet d2("fin_bsm_d2");
	AddOverload(d2, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                 LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMD2Function);
	AddOverload(d2, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                 LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMD2Function);
	loader.RegisterFunction(std::move(d2));
	RegisterOptionFunction(loader, "fin_bsm_price", BSMPriceFunction);
	RegisterOptionFunction(loader, "fin_bsm_delta", BSMDeltaFunction);
	ScalarFunctionSet gamma("fin_bsm_gamma");
	AddOverload(gamma, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                    LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMGammaFunction);
	AddOverload(gamma, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                    LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMGammaFunction);
	loader.RegisterFunction(std::move(gamma));
	RegisterOptionFunctionWithScale(loader, "fin_bsm_vega", BSMVegaFunction);
	RegisterOptionFunctionWithScale(loader, "fin_bsm_theta", BSMThetaFunction);
	RegisterOptionFunctionWithScale(loader, "fin_bsm_rho", BSMRhoFunction);
	ScalarFunctionSet greeks("fin_bsm_greeks");
	AddOverload(greeks,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            GreeksType(), BSMGreeksFunction);
	AddOverload(greeks,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            GreeksType(), BSMGreeksFunction);
	loader.RegisterFunction(std::move(greeks));
	ScalarFunctionSet all("fin_bsm_all");
	AddOverload(all,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            BSMAllType(), BSMAllFunction);
	AddOverload(all,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            BSMAllType(), BSMAllFunction);
	loader.RegisterFunction(std::move(all));
	ScalarFunctionSet iv("fin_bsm_implied_vol");
	AddOverload(iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMImpliedVolFunction);
	AddOverload(iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMImpliedVolFunction);
	AddOverload(iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMImpliedVolFunction);
	AddOverload(iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMImpliedVolFunction);
	AddOverload(iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BSMImpliedVolFunction);
	loader.RegisterFunction(std::move(iv));
	RegisterOptionFunction(loader, "fin_bsm_prob_itm", BSMProbITMFunction);
	RegisterOptionFunction(loader, "fin_bsm_prob_touch", BSMProbTouchFunction);
	RegisterOptionFunction(loader, "fin_bsm_elasticity", BSMElasticityFunction);
	RegisterOptionFunction(loader, "fin_bsm_vanna", BSMHigherGreekScalar("vanna"));
	RegisterOptionFunction(loader, "fin_bsm_vomma", BSMHigherGreekScalar("vomma"));
	RegisterOptionFunction(loader, "fin_bsm_speed", BSMHigherGreekScalar("speed"));
	RegisterOptionFunction(loader, "fin_bsm_zomma", BSMHigherGreekScalar("zomma"));
	RegisterOptionFunction(loader, "fin_bsm_ultima", BSMHigherGreekScalar("ultima"));
	RegisterOptionFunction(loader, "fin_bsm_charm", BSMHigherGreekScalar("charm"));
	RegisterOptionFunction(loader, "fin_bsm_color", BSMHigherGreekScalar("color"));
	ScalarFunctionSet price_dates("fin_bsm_price_dates");
	AddOverload(price_dates,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DATE,
	             LogicalType::DATE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMPriceDatesFunction);
	AddOverload(price_dates,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DATE,
	             LogicalType::DATE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BSMPriceDatesFunction);
	AddOverload(price_dates,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DATE,
	             LogicalType::DATE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::VARCHAR},
	            LogicalType::DOUBLE, BSMPriceDatesFunction);
	loader.RegisterFunction(std::move(price_dates));
	AddScalar(loader, "fin_black76_price",
	          {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE, Black76PriceFunction);
	AddScalar(loader, "fin_black76_greeks",
	          {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE},
	          GreeksType(), Black76GreeksFunction);
	ScalarFunctionSet black_iv("fin_black76_implied_vol");
	AddOverload(black_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, Black76ImpliedVolFunction);
	AddOverload(black_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, Black76ImpliedVolFunction);
	AddOverload(black_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, Black76ImpliedVolFunction);
	loader.RegisterFunction(std::move(black_iv));
	AddScalar(loader, "fin_bachelier_price",
	          {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE, BachelierPriceFunction);
	AddScalar(loader, "fin_bachelier_greeks",
	          {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE},
	          GreeksType(), BachelierGreeksFunction);
	ScalarFunctionSet bach_iv("fin_bachelier_implied_vol");
	AddOverload(bach_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BachelierImpliedVolFunction);
	AddOverload(bach_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BachelierImpliedVolFunction);
	AddOverload(bach_iv,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BachelierImpliedVolFunction);
	loader.RegisterFunction(std::move(bach_iv));
	ScalarFunctionSet binomial("fin_binomial_price");
	AddOverload(binomial, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                       LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BinomialPriceFunction);
	AddOverload(binomial, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                       LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BinomialPriceFunction);
	AddOverload(binomial, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                       LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER},
	            LogicalType::DOUBLE, BinomialPriceFunction);
	AddOverload(binomial,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::VARCHAR},
	            LogicalType::DOUBLE, BinomialPriceFunction);
	AddOverload(binomial,
	            {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::INTEGER,
	             LogicalType::VARCHAR, LogicalType::VARCHAR},
	            LogicalType::DOUBLE, BinomialPriceFunction);
	loader.RegisterFunction(std::move(binomial));
	ScalarFunctionSet digital("fin_digital_price");
	AddOverload(digital, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                      LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, DigitalPriceFunction);
	AddOverload(digital, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                      LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, DigitalPriceFunction);
	AddOverload(digital, {LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	                      LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, DigitalPriceFunction);
	loader.RegisterFunction(std::move(digital));
	RegisterOptionFunction(loader, "fin_asset_or_nothing_price", AssetOrNothingPriceFunction);
	RegisterOptionFunction(loader, "fin_asian_geometric_price", AsianGeometricPriceFunction);
	ScalarFunctionSet barrier("fin_barrier_price");
	AddOverload(barrier,
	            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BarrierPriceFunction);
	AddOverload(barrier,
	            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BarrierPriceFunction);
	AddOverload(barrier,
	            {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, BarrierPriceFunction);
	loader.RegisterFunction(std::move(barrier));
	ScalarFunctionSet sabr("fin_sabr_vol");
	AddOverload(sabr,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, SABRVolFunction);
	AddOverload(sabr,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	             LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, SABRVolFunction);
	loader.RegisterFunction(std::move(sabr));
	AddScalar(loader, "fin_svi_total_variance",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE, SviTotalVarianceFunction);
	AddScalar(loader, "fin_svi_vol",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE,
	           LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE, SviVolFunction);

	AddScalar(loader, "fin_avg_price",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "avg"); });
	AddScalar(loader, "fin_typ_price", {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "typ"); });
	AddScalar(loader, "fin_median_price", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "median"); });
	AddScalar(loader, "fin_weighted_close", {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "weighted"); });
	AddScalar(loader, "fin_mid", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "mid"); });
	AddScalar(loader, "fin_spread", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "spread"); });
	AddScalar(loader, "fin_spread_bps", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "spread_bps"); });
	AddScalar(loader, "fin_microprice",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	          LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "microprice"); });
	AddScalar(loader, "fin_order_imbalance", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "imbalance"); });
	AddScalar(loader, "fin_queue_imbalance", {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "imbalance"); });
	ScalarFunctionSet trade_sign("fin_trade_sign");
	AddOverload(trade_sign, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            TradeSignFunction);
	AddOverload(trade_sign, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::DOUBLE, TradeSignFunction);
	loader.RegisterFunction(std::move(trade_sign));

	auto double_list = LogicalType::LIST(LogicalType::DOUBLE);
	auto matrix_type = LogicalType::LIST(double_list);
	AddScalar(loader, "fin_dot", {double_list, double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "dot"); });
	AddScalar(loader, "fin_vector_sum", {double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "sum"); });
	AddScalar(loader, "fin_vector_mean", {double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "mean"); });
	AddScalar(loader, "fin_vector_scale", {double_list, LogicalType::DOUBLE}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "scale"); });
	AddScalar(loader, "fin_vector_add", {double_list, double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "add"); });
	AddScalar(loader, "fin_vector_sub", {double_list, double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "sub"); });
	AddScalar(loader, "fin_vector_normalize_sum", {double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "normalize"); });
	AddScalar(loader, "fin_turnover", {double_list, double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "turnover"); });
	ScalarFunctionSet equal_weights("fin_equal_weights");
	AddOverload(equal_weights, {LogicalType::INTEGER}, double_list, EqualWeightsFunction);
	AddOverload(equal_weights, {LogicalType::BIGINT}, double_list, EqualWeightsFunction);
	loader.RegisterFunction(std::move(equal_weights));
	AddScalar(loader, "fin_inverse_vol_weights", {double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "inverse_vol"); });
	child_list_t<LogicalType> shape_children;
	shape_children.emplace_back("rows", LogicalType::BIGINT);
	shape_children.emplace_back("cols", LogicalType::BIGINT);
	AddScalar(loader, "fin_matrix_shape", {matrix_type}, LogicalType::STRUCT(std::move(shape_children)), MatrixShapeFunction);
	AddScalar(loader, "fin_matrix_transpose", {matrix_type}, matrix_type,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "transpose"); });
	AddScalar(loader, "fin_matrix_vecmul", {matrix_type, double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixFunction(args, state, result, "vecmul"); });
	AddScalar(loader, "fin_matrix_mul", {matrix_type, matrix_type}, matrix_type, MatrixMulFunction);
	AddScalar(loader, "fin_matrix_cholesky", {matrix_type}, matrix_type,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "cholesky"); });
	ScalarFunctionSet matrix_psd("fin_matrix_is_psd");
	AddOverload(matrix_psd, {matrix_type}, LogicalType::BOOLEAN, MatrixIsPsdFunction);
	AddOverload(matrix_psd, {matrix_type, LogicalType::DOUBLE}, LogicalType::BOOLEAN, MatrixIsPsdFunction);
	loader.RegisterFunction(std::move(matrix_psd));
	ScalarFunctionSet nearest_psd("fin_nearest_psd");
	AddOverload(nearest_psd, {matrix_type}, matrix_type,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "nearest_psd"); });
	AddOverload(nearest_psd, {matrix_type, LogicalType::VARCHAR}, matrix_type,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "nearest_psd"); });
	loader.RegisterFunction(std::move(nearest_psd));
	AddScalar(loader, "fin_portfolio_return", {double_list, double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "dot"); });
	AddScalar(loader, "fin_portfolio_expected_return", {double_list, double_list}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "dot"); });
	AddScalar(loader, "fin_portfolio_variance", {double_list, matrix_type}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PortfolioScalarFunction(args, state, result, "variance"); });
	AddScalar(loader, "fin_portfolio_vol", {double_list, matrix_type}, LogicalType::DOUBLE,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PortfolioScalarFunction(args, state, result, "vol"); });
	ScalarFunctionSet portfolio_sharpe("fin_portfolio_sharpe");
	AddOverload(portfolio_sharpe, {double_list, double_list, matrix_type}, LogicalType::DOUBLE, PortfolioSharpeFunction);
	AddOverload(portfolio_sharpe, {double_list, double_list, matrix_type, LogicalType::DOUBLE}, LogicalType::DOUBLE,
	            PortfolioSharpeFunction);
	loader.RegisterFunction(std::move(portfolio_sharpe));

	AddScalar(loader, "fin_validate_ohlc",
	          {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, ValidationType(),
	          ValidateOhlcFunction);
	ScalarFunctionSet valid_return("fin_validate_return");
	AddOverload(valid_return, {LogicalType::DOUBLE}, LogicalType::BOOLEAN, ValidateReturnFunction);
	AddOverload(valid_return, {LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::BOOLEAN, ValidateReturnFunction);
	loader.RegisterFunction(std::move(valid_return));
	AddScalar(loader, "fin_is_finite", {LogicalType::DOUBLE}, LogicalType::BOOLEAN, IsFiniteFunction);
	ScalarFunctionSet is_price("fin_is_price");
	AddOverload(is_price, {LogicalType::DOUBLE}, LogicalType::BOOLEAN, IsPriceFunction);
	AddOverload(is_price, {LogicalType::DOUBLE, LogicalType::BOOLEAN}, LogicalType::BOOLEAN, IsPriceFunction);
	loader.RegisterFunction(std::move(is_price));
	ScalarFunctionSet is_rate("fin_is_rate");
	AddOverload(is_rate, {LogicalType::DOUBLE}, LogicalType::BOOLEAN, IsRateFunction);
	AddOverload(is_rate, {LogicalType::DOUBLE, LogicalType::BOOLEAN}, LogicalType::BOOLEAN, IsRateFunction);
	loader.RegisterFunction(std::move(is_rate));
	AddScalar(loader, "fin_is_vol", {LogicalType::DOUBLE}, LogicalType::BOOLEAN, IsVolFunction);
	ScalarFunctionSet outlier("fin_is_outlier_zscore");
	AddOverload(outlier, {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE}, LogicalType::BOOLEAN,
	            IsOutlierZScoreFunction);
	AddOverload(outlier,
	            {LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::DOUBLE},
	            LogicalType::BOOLEAN, IsOutlierZScoreFunction);
	loader.RegisterFunction(std::move(outlier));
	AddScalar(loader, "fin_parse_option_kind", {LogicalType::VARCHAR}, LogicalType::VARCHAR, ParseOptionKindFunction);
	AddScalar(loader, "fin_parse_exercise_style", {LogicalType::VARCHAR}, LogicalType::VARCHAR,
	          ParseExerciseStyleFunction);
	AddScalar(loader, "fin_parse_day_count", {LogicalType::VARCHAR}, LogicalType::VARCHAR, ParseDayCountFunction);
	AddScalar(loader, "fin_parse_compounding", {LogicalType::VARCHAR}, LogicalType::VARCHAR, ParseCompoundingFunction);
	AddScalar(loader, "fin_parse_return_method", {LogicalType::VARCHAR}, LogicalType::VARCHAR, ParseReturnMethodFunction);
	AddScalar(loader, "fin_normalize_currency", {LogicalType::VARCHAR}, LogicalType::VARCHAR, NormalizeCurrencyFunction);
	ScalarFunctionSet is_bd("fin_is_business_day");
	AddOverload(is_bd, {LogicalType::DATE}, LogicalType::BOOLEAN, BusinessDayFunction);
	AddOverload(is_bd, {LogicalType::DATE, LogicalType::VARCHAR}, LogicalType::BOOLEAN, BusinessDayFunction);
	loader.RegisterFunction(std::move(is_bd));
	ScalarFunctionSet next_bd("fin_next_business_day");
	AddOverload(next_bd, {LogicalType::DATE}, LogicalType::DATE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, 1); });
	AddOverload(next_bd, {LogicalType::DATE, LogicalType::VARCHAR, LogicalType::INTEGER}, LogicalType::DATE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, 1); });
	loader.RegisterFunction(std::move(next_bd));
	ScalarFunctionSet prev_bd("fin_prev_business_day");
	AddOverload(prev_bd, {LogicalType::DATE}, LogicalType::DATE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, -1); });
	AddOverload(prev_bd, {LogicalType::DATE, LogicalType::VARCHAR, LogicalType::INTEGER}, LogicalType::DATE,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, -1); });
	loader.RegisterFunction(std::move(prev_bd));
	ScalarFunctionSet bd_between("fin_business_days_between");
	AddOverload(bd_between, {LogicalType::DATE, LogicalType::DATE}, LogicalType::BIGINT, BusinessDaysBetweenFunction);
	AddOverload(bd_between, {LogicalType::DATE, LogicalType::DATE, LogicalType::VARCHAR}, LogicalType::BIGINT,
	            BusinessDaysBetweenFunction);
	loader.RegisterFunction(std::move(bd_between));
	ScalarFunctionSet session_date("fin_session_date");
	AddOverload(session_date, {LogicalType::TIMESTAMP, LogicalType::VARCHAR}, LogicalType::DATE, SessionDateFunction);
	AddOverload(session_date, {LogicalType::TIMESTAMP, LogicalType::VARCHAR, LogicalType::VARCHAR}, LogicalType::DATE,
	            SessionDateFunction);
	loader.RegisterFunction(std::move(session_date));
	ScalarFunctionSet regular_session("fin_is_regular_session");
	AddOverload(regular_session, {LogicalType::TIMESTAMP, LogicalType::VARCHAR}, LogicalType::BOOLEAN,
	            RegularSessionFunction);
	AddOverload(regular_session, {LogicalType::TIMESTAMP, LogicalType::VARCHAR, LogicalType::VARCHAR},
	            LogicalType::BOOLEAN, RegularSessionFunction);
	loader.RegisterFunction(std::move(regular_session));
}
