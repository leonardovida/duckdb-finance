void RegisterFinanceScalars(ExtensionLoader &loader) {
	loader.RegisterFunction(ScalarFunction(FinanceFunctionName("fin_version"), {}, FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceVersionFunction));

	AddScalar(loader, "fin_norm_pdf", {FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), NormPDFFunction);
	AddScalar(loader, "fin_norm_cdf", {FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), NormCDFFunction);
	AddScalar(loader, "fin_norm_inv", {FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), NormInvFunction);
	AddScalar(loader, "fin_student_t_cdf", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          StudentTCdfFunction);
	AddScalar(loader, "fin_student_t_inv", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          StudentTInvFunction);
	AddScalar(loader, "fin_chi2_cdf", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), Chi2CdfFunction);
	AddScalar(loader, "fin_chi2_inv", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), Chi2InvFunction);

	ScalarFunctionSet safe_div(FinanceFunctionName("fin_safe_div"));
	AddOverload(safe_div, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), SafeDivFunction);
	AddOverload(safe_div, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            SafeDivFunction);
	loader.RegisterFunction(std::move(safe_div));
	AddScalar(loader, "fin_bps", {FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), BpsFunction);
	AddScalar(loader, "fin_from_bps", {FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), FromBpsFunction);
	AddScalar(loader, "fin_clip", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          ClipFunction);
	ScalarFunctionSet round_tick(FinanceFunctionName("fin_round_to_tick"));
	AddOverload(round_tick, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), RoundToTickFunction);
	AddOverload(round_tick, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            RoundToTickFunction);
	loader.RegisterFunction(std::move(round_tick));

	ScalarFunctionSet yearfrac(FinanceFunctionName("fin_yearfrac"));
	AddOverload(yearfrac, {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), YearFracFunction);
	AddOverload(yearfrac, {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            YearFracFunction);
	loader.RegisterFunction(std::move(yearfrac));

	ScalarFunctionSet discount(FinanceFunctionName("fin_discount_factor"));
	AddOverload(discount, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), DiscountFactorFunction);
	AddOverload(discount, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            DiscountFactorFunction);
	AddOverload(discount, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::INTEGER)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), DiscountFactorFunction);
	loader.RegisterFunction(std::move(discount));

	ScalarFunctionSet rate_from_discount(FinanceFunctionName("fin_rate_from_discount"));
	AddOverload(rate_from_discount, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            RateFromDiscountFunction);
	AddOverload(rate_from_discount, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            RateFromDiscountFunction);
	AddOverload(rate_from_discount,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::INTEGER)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), RateFromDiscountFunction);
	loader.RegisterFunction(std::move(rate_from_discount));
	ScalarFunctionSet forward_rate(FinanceFunctionName("fin_forward_rate"));
	AddOverload(forward_rate,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), ForwardRateFunction);
	AddOverload(forward_rate,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), ForwardRateFunction);
	loader.RegisterFunction(std::move(forward_rate));
	ScalarFunctionSet pv(FinanceFunctionName("fin_present_value"));
	AddOverload(pv, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            PresentValueFunction);
	AddOverload(pv, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), PresentValueFunction);
	loader.RegisterFunction(std::move(pv));
	ScalarFunctionSet fv(FinanceFunctionName("fin_future_value"));
	AddOverload(fv, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            FutureValueFunction);
	AddOverload(fv, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), FutureValueFunction);
	loader.RegisterFunction(std::move(fv));

	ScalarFunctionSet annuity(FinanceFunctionName("fin_annuity_payment"));
	AddOverload(annuity, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            AnnuityPaymentFunction);
	AddOverload(annuity, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), AnnuityPaymentFunction);
	AddOverload(annuity,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), AnnuityPaymentFunction);
	loader.RegisterFunction(std::move(annuity));

	ScalarFunctionSet bond_price(FinanceFunctionName("fin_bond_price"));
	AddOverload(bond_price, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            BondPriceFunction);
	AddOverload(bond_price, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BondPriceFunction);
	AddOverload(bond_price,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER),
	             FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BondPriceFunction);
	loader.RegisterFunction(std::move(bond_price));
	ScalarFunctionSet bond_ytm(FinanceFunctionName("fin_bond_ytm"));
	AddOverload(bond_ytm, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            BondYTMFunction);
	AddOverload(bond_ytm, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BondYTMFunction);
	AddOverload(bond_ytm,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER),
	             FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BondYTMFunction);
	loader.RegisterFunction(std::move(bond_ytm));
	ScalarFunctionSet duration(FinanceFunctionName("fin_bond_duration"));
	AddOverload(duration, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            BondDurationFunction);
	AddOverload(duration, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BondDurationFunction);
	AddOverload(duration,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER),
	             FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BondDurationFunction);
	AddOverload(duration,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BondDurationFunction);
	loader.RegisterFunction(std::move(duration));
	ScalarFunctionSet convexity(FinanceFunctionName("fin_bond_convexity"));
	AddOverload(convexity, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            BondConvexityFunction);
	AddOverload(convexity, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BondConvexityFunction);
	AddOverload(convexity,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER),
	             FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BondConvexityFunction);
	loader.RegisterFunction(std::move(convexity));
	ScalarFunctionSet dv01(FinanceFunctionName("fin_dv01"));
	AddOverload(dv01, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), DV01Function);
	AddOverload(dv01, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), DV01Function);
	AddOverload(dv01,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER),
	             FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), DV01Function);
	loader.RegisterFunction(std::move(dv01));
	ScalarFunctionSet accrued(FinanceFunctionName("fin_accrued_interest"));
	AddOverload(accrued, {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), AccruedInterestFunction);
	AddOverload(accrued,
	            {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), AccruedInterestFunction);
	AddOverload(accrued,
	            {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), AccruedInterestFunction);
	loader.RegisterFunction(std::move(accrued));
	auto list_double = LogicalType::LIST(FinanceLogicalType(LogicalTypeId::DOUBLE));
	auto list_date = LogicalType::LIST(FinanceLogicalType(LogicalTypeId::DATE));
	ScalarFunctionSet npv(FinanceFunctionName("fin_npv"));
	AddOverload(npv, {FinanceLogicalType(LogicalTypeId::DOUBLE), list_double}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "npv"); });
	AddOverload(npv, {list_double, list_double, FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE), NPVWithTimesFunction);
	AddOverload(npv, {list_double, list_double, FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            NPVWithTimesFunction);
	loader.RegisterFunction(std::move(npv));
	ScalarFunctionSet irr(FinanceFunctionName("fin_irr"));
	AddOverload(irr, {list_double}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "irr"); });
	AddOverload(irr, {list_double, FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "irr"); });
	loader.RegisterFunction(std::move(irr));
	AddScalar(loader, "fin_mirr", {list_double, FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "mirr"); });
	ScalarFunctionSet xirr(FinanceFunctionName("fin_xirr"));
	AddOverload(xirr, {list_double, list_date}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "xirr"); });
	AddOverload(xirr, {list_double, list_date, FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            [](DataChunk &args, ExpressionState &state, Vector &result) { CashflowListFunction(args, state, result, "xirr"); });
	loader.RegisterFunction(std::move(xirr));
	AddScalar(loader, "fin_interpolate_curve", {list_double, list_double, FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CurveListFunction(args, state, result, "zero"); });
	AddScalar(loader, "fin_curve_zero_rate", {list_double, list_double, FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CurveListFunction(args, state, result, "zero"); });
	AddScalar(loader, "fin_curve_discount_factor", {list_double, list_double, FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { CurveListFunction(args, state, result, "discount"); });
	AddScalar(loader, "fin_swap_rate", {list_double, list_double}, FinanceLogicalType(LogicalTypeId::DOUBLE), SwapRateFunction);
	AddScalar(loader, "fin_fra_rate",
	          {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
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

	AddScalar(loader, "fin_option_payoff", {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          FinanceLogicalType(LogicalTypeId::DOUBLE), OptionPayoffFunction);
	ScalarFunctionSet forward_price(FinanceFunctionName("fin_forward_price"));
	AddOverload(forward_price, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            ForwardPriceFunction);
	AddOverload(forward_price,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), ForwardPriceFunction);
	loader.RegisterFunction(std::move(forward_price));
	ScalarFunctionSet parity(FinanceFunctionName("fin_put_call_parity"));
	AddOverload(parity,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), PutCallParityFunction);
	AddOverload(parity,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), PutCallParityFunction);
	loader.RegisterFunction(std::move(parity));
	ScalarFunctionSet d1(FinanceFunctionName("fin_bsm_d1"));
	AddOverload(d1, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                 FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMD1Function);
	AddOverload(d1, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                 FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMD1Function);
	loader.RegisterFunction(std::move(d1));
	ScalarFunctionSet d2(FinanceFunctionName("fin_bsm_d2"));
	AddOverload(d2, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                 FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMD2Function);
	AddOverload(d2, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                 FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMD2Function);
	loader.RegisterFunction(std::move(d2));
	ScalarFunctionSet bsm_price(FinanceFunctionName("fin_bsm_price"));
	AddOverload(bsm_price, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                        FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMPriceFunction);
	AddOverload(bsm_price, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                        FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMPriceFunction);
	AddOverload(bsm_price, {OptionSpecType()}, FinanceLogicalType(LogicalTypeId::DOUBLE), BSMPriceSpecFunction);
	loader.RegisterFunction(std::move(bsm_price));
	ScalarFunctionSet bsm_delta(FinanceFunctionName("fin_bsm_delta"));
	AddOverload(bsm_delta, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                        FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMDeltaFunction);
	AddOverload(bsm_delta, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                        FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMDeltaFunction);
	AddOverload(bsm_delta, {OptionSpecType()}, FinanceLogicalType(LogicalTypeId::DOUBLE), BSMDeltaSpecFunction);
	loader.RegisterFunction(std::move(bsm_delta));
	ScalarFunctionSet gamma(FinanceFunctionName("fin_bsm_gamma"));
	AddOverload(gamma, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                    FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMGammaFunction);
	AddOverload(gamma, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                    FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMGammaFunction);
	AddOverload(gamma, {OptionSpecType()}, FinanceLogicalType(LogicalTypeId::DOUBLE), BSMGammaSpecFunction);
	loader.RegisterFunction(std::move(gamma));
	ScalarFunctionSet bsm_vega(FinanceFunctionName("fin_bsm_vega"));
	AddOverload(bsm_vega, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                       FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMVegaFunction);
	AddOverload(bsm_vega, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                       FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMVegaFunction);
	AddOverload(bsm_vega, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                       FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMVegaFunction);
	AddOverload(bsm_vega, {OptionSpecType()}, FinanceLogicalType(LogicalTypeId::DOUBLE), BSMVegaSpecFunction);
	loader.RegisterFunction(std::move(bsm_vega));
	RegisterOptionFunctionWithScale(loader, "fin_bsm_theta", BSMThetaFunction);
	RegisterOptionFunctionWithScale(loader, "fin_bsm_rho", BSMRhoFunction);
	ScalarFunctionSet greeks(FinanceFunctionName("fin_bsm_greeks"));
	AddOverload(greeks,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            GreeksType(), BSMGreeksFunction);
	AddOverload(greeks,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            GreeksType(), BSMGreeksFunction);
	AddOverload(greeks, {OptionSpecType()}, GreeksType(), BSMGreeksSpecFunction);
	loader.RegisterFunction(std::move(greeks));
	ScalarFunctionSet all(FinanceFunctionName("fin_bsm_all"));
	AddOverload(all,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            BSMAllType(), BSMAllFunction);
	AddOverload(all,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            BSMAllType(), BSMAllFunction);
	AddOverload(all, {OptionSpecType()}, BSMAllType(), BSMAllSpecFunction);
	loader.RegisterFunction(std::move(all));
	ScalarFunctionSet iv(FinanceFunctionName("fin_bsm_implied_vol"));
	AddOverload(iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMImpliedVolFunction);
	AddOverload(iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMImpliedVolFunction);
	AddOverload(iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMImpliedVolFunction);
	AddOverload(iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMImpliedVolFunction);
	AddOverload(iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMImpliedVolFunction);
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
	ScalarFunctionSet price_dates(FinanceFunctionName("fin_bsm_price_dates"));
	AddOverload(price_dates,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DATE),
	             FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMPriceDatesFunction);
	AddOverload(price_dates,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DATE),
	             FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMPriceDatesFunction);
	AddOverload(price_dates,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DATE),
	             FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BSMPriceDatesFunction);
	loader.RegisterFunction(std::move(price_dates));
	AddScalar(loader, "fin_black76_price",
	          {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	           FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          FinanceLogicalType(LogicalTypeId::DOUBLE), Black76PriceFunction);
	AddScalar(loader, "fin_black76_greeks",
	          {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	           FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          GreeksType(), Black76GreeksFunction);
	ScalarFunctionSet black_iv(FinanceFunctionName("fin_black76_implied_vol"));
	AddOverload(black_iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), Black76ImpliedVolFunction);
	AddOverload(black_iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), Black76ImpliedVolFunction);
	AddOverload(black_iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), Black76ImpliedVolFunction);
	loader.RegisterFunction(std::move(black_iv));
	AddScalar(loader, "fin_bachelier_price",
	          {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	           FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          FinanceLogicalType(LogicalTypeId::DOUBLE), BachelierPriceFunction);
	AddScalar(loader, "fin_bachelier_greeks",
	          {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	           FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          GreeksType(), BachelierGreeksFunction);
	ScalarFunctionSet bach_iv(FinanceFunctionName("fin_bachelier_implied_vol"));
	AddOverload(bach_iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BachelierImpliedVolFunction);
	AddOverload(bach_iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BachelierImpliedVolFunction);
	AddOverload(bach_iv,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BachelierImpliedVolFunction);
	loader.RegisterFunction(std::move(bach_iv));
	ScalarFunctionSet binomial(FinanceFunctionName("fin_binomial_price"));
	AddOverload(binomial, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                       FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BinomialPriceFunction);
	AddOverload(binomial, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                       FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BinomialPriceFunction);
	AddOverload(binomial, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                       FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BinomialPriceFunction);
	AddOverload(binomial,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER),
	             FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BinomialPriceFunction);
	AddOverload(binomial,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::INTEGER),
	             FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BinomialPriceFunction);
	loader.RegisterFunction(std::move(binomial));
	ScalarFunctionSet digital(FinanceFunctionName("fin_digital_price"));
	AddOverload(digital, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                      FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), DigitalPriceFunction);
	AddOverload(digital, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                      FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), DigitalPriceFunction);
	AddOverload(digital, {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	                      FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), DigitalPriceFunction);
	loader.RegisterFunction(std::move(digital));
	RegisterOptionFunction(loader, "fin_asset_or_nothing_price", AssetOrNothingPriceFunction);
	RegisterOptionFunction(loader, "fin_asian_geometric_price", AsianGeometricPriceFunction);
	ScalarFunctionSet barrier(FinanceFunctionName("fin_barrier_price"));
	AddOverload(barrier,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BarrierPriceFunction);
	AddOverload(barrier,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BarrierPriceFunction);
	AddOverload(barrier,
	            {FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), BarrierPriceFunction);
	loader.RegisterFunction(std::move(barrier));
	ScalarFunctionSet sabr(FinanceFunctionName("fin_sabr_vol"));
	AddOverload(sabr,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), SABRVolFunction);
	AddOverload(sabr,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	             FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), SABRVolFunction);
	loader.RegisterFunction(std::move(sabr));
	AddScalar(loader, "fin_svi_total_variance",
	          {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	           FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          FinanceLogicalType(LogicalTypeId::DOUBLE), SviTotalVarianceFunction);
	AddScalar(loader, "fin_svi_vol",
	          {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE),
	           FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          FinanceLogicalType(LogicalTypeId::DOUBLE), SviVolFunction);

	AddScalar(loader, "fin_avg_price",
	          {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "avg"); });
	AddScalar(loader, "fin_typ_price", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "typ"); });
	AddScalar(loader, "fin_median_price", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "median"); });
	AddScalar(loader, "fin_weighted_close", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PriceTransformFunction(args, state, result, "weighted"); });
	AddScalar(loader, "fin_mid", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "mid"); });
	AddScalar(loader, "fin_spread", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "spread"); });
	AddScalar(loader, "fin_spread_bps", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "spread_bps"); });
	AddScalar(loader, "fin_microprice",
	          {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	          FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "microprice"); });
	AddScalar(loader, "fin_order_imbalance", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "imbalance"); });
	AddScalar(loader, "fin_queue_imbalance", {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MicrostructureFunction(args, state, result, "imbalance"); });
	ScalarFunctionSet trade_sign(FinanceFunctionName("fin_trade_sign"));
	AddOverload(trade_sign, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            TradeSignFunction);
	AddOverload(trade_sign, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::DOUBLE), TradeSignFunction);
	loader.RegisterFunction(std::move(trade_sign));

	auto double_list = LogicalType::LIST(FinanceLogicalType(LogicalTypeId::DOUBLE));
	auto matrix_type = LogicalType::LIST(double_list);
	AddScalar(loader, "fin_dot", {double_list, double_list}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "dot"); });
	AddScalar(loader, "fin_vector_sum", {double_list}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "sum"); });
	AddScalar(loader, "fin_vector_mean", {double_list}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "mean"); });
	AddScalar(loader, "fin_vector_scale", {double_list, FinanceLogicalType(LogicalTypeId::DOUBLE)}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "scale"); });
	AddScalar(loader, "fin_vector_add", {double_list, double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "add"); });
	AddScalar(loader, "fin_vector_sub", {double_list, double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "sub"); });
	AddScalar(loader, "fin_vector_normalize_sum", {double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "normalize"); });
	AddScalar(loader, "fin_turnover", {double_list, double_list}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "turnover"); });
	ScalarFunctionSet equal_weights(FinanceFunctionName("fin_equal_weights"));
	AddOverload(equal_weights, {FinanceLogicalType(LogicalTypeId::INTEGER)}, double_list, EqualWeightsFunction);
	AddOverload(equal_weights, {FinanceLogicalType(LogicalTypeId::BIGINT)}, double_list, EqualWeightsFunction);
	loader.RegisterFunction(std::move(equal_weights));
	AddScalar(loader, "fin_inverse_vol_weights", {double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { ListScalarFunction(args, state, result, "inverse_vol"); });
	child_list_t<LogicalType> shape_children;
	shape_children.emplace_back("rows", FinanceLogicalType(LogicalTypeId::BIGINT));
	shape_children.emplace_back("cols", FinanceLogicalType(LogicalTypeId::BIGINT));
	AddScalar(loader, "fin_matrix_shape", {matrix_type}, LogicalType::STRUCT(std::move(shape_children)), MatrixShapeFunction);
	AddScalar(loader, "fin_matrix_transpose", {matrix_type}, matrix_type,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "transpose"); });
	AddScalar(loader, "fin_matrix_vecmul", {matrix_type, double_list}, double_list,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixFunction(args, state, result, "vecmul"); });
	AddScalar(loader, "fin_matrix_mul", {matrix_type, matrix_type}, matrix_type, MatrixMulFunction);
	AddScalar(loader, "fin_matrix_cholesky", {matrix_type}, matrix_type,
	          [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "cholesky"); });
	ScalarFunctionSet matrix_psd(FinanceFunctionName("fin_matrix_is_psd"));
	AddOverload(matrix_psd, {matrix_type}, FinanceLogicalType(LogicalTypeId::BOOLEAN), MatrixIsPsdFunction);
	AddOverload(matrix_psd, {matrix_type, FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), MatrixIsPsdFunction);
	loader.RegisterFunction(std::move(matrix_psd));
	ScalarFunctionSet nearest_psd(FinanceFunctionName("fin_nearest_psd"));
	AddOverload(nearest_psd, {matrix_type}, matrix_type,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "nearest_psd"); });
	AddOverload(nearest_psd, {matrix_type, FinanceLogicalType(LogicalTypeId::VARCHAR)}, matrix_type,
	            [](DataChunk &args, ExpressionState &state, Vector &result) { MatrixNestedFunction(args, state, result, "nearest_psd"); });
	loader.RegisterFunction(std::move(nearest_psd));
	AddScalar(loader, "fin_portfolio_return", {double_list, double_list}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "dot"); });
	AddScalar(loader, "fin_portfolio_expected_return", {double_list, double_list}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { BinaryListFunction(args, state, result, "dot"); });
	AddScalar(loader, "fin_portfolio_variance", {double_list, matrix_type}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PortfolioScalarFunction(args, state, result, "variance"); });
	AddScalar(loader, "fin_portfolio_vol", {double_list, matrix_type}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	          [](DataChunk &args, ExpressionState &state, Vector &result) { PortfolioScalarFunction(args, state, result, "vol"); });
	ScalarFunctionSet portfolio_sharpe(FinanceFunctionName("fin_portfolio_sharpe"));
	AddOverload(portfolio_sharpe, {double_list, double_list, matrix_type}, FinanceLogicalType(LogicalTypeId::DOUBLE), PortfolioSharpeFunction);
	AddOverload(portfolio_sharpe, {double_list, double_list, matrix_type, FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::DOUBLE),
	            PortfolioSharpeFunction);
	loader.RegisterFunction(std::move(portfolio_sharpe));

	AddScalar(loader, "fin_validate_ohlc",
	          {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, ValidationType(),
	          ValidateOhlcFunction);
	ScalarFunctionSet valid_return(FinanceFunctionName("fin_validate_return"));
	AddOverload(valid_return, {FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), ValidateReturnFunction);
	AddOverload(valid_return, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), ValidateReturnFunction);
	loader.RegisterFunction(std::move(valid_return));
	AddScalar(loader, "fin_is_finite", {FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), IsFiniteFunction);
	ScalarFunctionSet is_price(FinanceFunctionName("fin_is_price"));
	AddOverload(is_price, {FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), IsPriceFunction);
	AddOverload(is_price, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BOOLEAN)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), IsPriceFunction);
	loader.RegisterFunction(std::move(is_price));
	ScalarFunctionSet is_rate(FinanceFunctionName("fin_is_rate"));
	AddOverload(is_rate, {FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), IsRateFunction);
	AddOverload(is_rate, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::BOOLEAN)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), IsRateFunction);
	loader.RegisterFunction(std::move(is_rate));
	AddScalar(loader, "fin_is_vol", {FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), IsVolFunction);
	ScalarFunctionSet outlier(FinanceFunctionName("fin_is_outlier_zscore"));
	AddOverload(outlier, {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)}, FinanceLogicalType(LogicalTypeId::BOOLEAN),
	            IsOutlierZScoreFunction);
	AddOverload(outlier,
	            {FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE), FinanceLogicalType(LogicalTypeId::DOUBLE)},
	            FinanceLogicalType(LogicalTypeId::BOOLEAN), IsOutlierZScoreFunction);
	loader.RegisterFunction(std::move(outlier));
	AddScalar(loader, "fin_parse_option_kind", {FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::VARCHAR), ParseOptionKindFunction);
	AddScalar(loader, "fin_parse_exercise_style", {FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::VARCHAR),
	          ParseExerciseStyleFunction);
	AddScalar(loader, "fin_parse_day_count", {FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::VARCHAR), ParseDayCountFunction);
	AddScalar(loader, "fin_parse_compounding", {FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::VARCHAR), ParseCompoundingFunction);
	AddScalar(loader, "fin_parse_return_method", {FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::VARCHAR), ParseReturnMethodFunction);
	AddScalar(loader, "fin_normalize_currency", {FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::VARCHAR), NormalizeCurrencyFunction);
	ScalarFunctionSet is_bd(FinanceFunctionName("fin_is_business_day"));
	AddOverload(is_bd, {FinanceLogicalType(LogicalTypeId::DATE)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), BusinessDayFunction);
	AddOverload(is_bd, {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::BOOLEAN), BusinessDayFunction);
	loader.RegisterFunction(std::move(is_bd));
	ScalarFunctionSet next_bd(FinanceFunctionName("fin_next_business_day"));
	AddOverload(next_bd, {FinanceLogicalType(LogicalTypeId::DATE)}, FinanceLogicalType(LogicalTypeId::DATE),
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, 1); });
	AddOverload(next_bd, {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::INTEGER)}, FinanceLogicalType(LogicalTypeId::DATE),
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, 1); });
	loader.RegisterFunction(std::move(next_bd));
	ScalarFunctionSet prev_bd(FinanceFunctionName("fin_prev_business_day"));
	AddOverload(prev_bd, {FinanceLogicalType(LogicalTypeId::DATE)}, FinanceLogicalType(LogicalTypeId::DATE),
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, -1); });
	AddOverload(prev_bd, {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::INTEGER)}, FinanceLogicalType(LogicalTypeId::DATE),
	            [](DataChunk &args, ExpressionState &state, Vector &result) { NextPrevBusinessDayFunction(args, state, result, -1); });
	loader.RegisterFunction(std::move(prev_bd));
	ScalarFunctionSet bd_between(FinanceFunctionName("fin_business_days_between"));
	AddOverload(bd_between, {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE)}, FinanceLogicalType(LogicalTypeId::BIGINT), BusinessDaysBetweenFunction);
	AddOverload(bd_between, {FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::DATE), FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::BIGINT),
	            BusinessDaysBetweenFunction);
	loader.RegisterFunction(std::move(bd_between));
	ScalarFunctionSet session_date(FinanceFunctionName("fin_session_date"));
	AddOverload(session_date, {FinanceLogicalType(LogicalTypeId::TIMESTAMP), FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::DATE), SessionDateFunction);
	AddOverload(session_date, {FinanceLogicalType(LogicalTypeId::TIMESTAMP), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::DATE),
	            SessionDateFunction);
	loader.RegisterFunction(std::move(session_date));
	ScalarFunctionSet regular_session(FinanceFunctionName("fin_is_regular_session"));
	AddOverload(regular_session, {FinanceLogicalType(LogicalTypeId::TIMESTAMP), FinanceLogicalType(LogicalTypeId::VARCHAR)}, FinanceLogicalType(LogicalTypeId::BOOLEAN),
	            RegularSessionFunction);
	AddOverload(regular_session, {FinanceLogicalType(LogicalTypeId::TIMESTAMP), FinanceLogicalType(LogicalTypeId::VARCHAR), FinanceLogicalType(LogicalTypeId::VARCHAR)},
	            FinanceLogicalType(LogicalTypeId::BOOLEAN), RegularSessionFunction);
	loader.RegisterFunction(std::move(regular_session));
}
