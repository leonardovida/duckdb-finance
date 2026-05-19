INSTALL finance FROM community;
LOAD finance;

SELECT
  fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS call_price,
  (fin_bsm_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.20)).delta AS call_delta,
  fin_discount_factor(0.05, 1.0) AS discount_factor,
  fin_simple_return(105.0, 100.0) AS simple_return;
