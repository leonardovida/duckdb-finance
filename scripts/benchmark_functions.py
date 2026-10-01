#!/usr/bin/env python3
"""Repeat representative queries in one DuckDB process; save timings and results."""
import argparse
import json
import math
import re
import statistics
import subprocess
from pathlib import Path

from run_sql_with_trace import split_statements, sql_literal


def workload(scale):
    rows = max(100, round(1_000_000 * scale))
    solves = max(100, rows // 20)
    trees = max(20, rows // 500)
    setup = f"""
CREATE TEMP TABLE options AS
SELECT CASE WHEN i%2=0 THEN 'call' ELSE 'put' END kind,
       90+(i%21)::DOUBLE s, 100.0 k, .5+(i%10)::DOUBLE/10 t,
       .02+(i%7)::DOUBLE/1000 r, .12+(i%23)::DOUBLE/100 v
FROM range({rows}) z(i);
CREATE TEMP TABLE quotes AS SELECT *,
       fin_bsm_price(kind,s,k,t,r,v) bsm,
       fin_black76_price(kind,s,k,t,r,v) black,
       fin_bachelier_price(kind,s-100,k-100,t,r,v*100) normal
FROM options LIMIT {solves};
CREATE TEMP TABLE bonds AS
SELECT .03+(i%100)::DOUBLE/10000 coupon, .02+(i%100)::DOUBLE/10000 ytm
FROM range({rows}) z(i);
CREATE TEMP TABLE flows AS SELECT [-100.0-(i%10),25.0,30.0,35.0,40.0,45.0] cf,
       [DATE '2026-01-01',DATE '2026-04-01',DATE '2026-07-01',
        DATE '2026-10-01',DATE '2027-01-01',DATE '2027-04-01'] dates
FROM range({solves}) z(i);
CREATE TEMP TABLE vectors AS SELECT [.25+(i%10)::DOUBLE/1000,.25,.25,.25] w,
       [[.04,.01,.0,.0],[.01,.05,.01,.0],[.0,.01,.06,.01],[.0,.0,.01,.03]] cov
FROM range({rows}) z(i);
CREATE TEMP TABLE observations AS SELECT i,
       sin(i::DOUBLE)*.01+(i%13)::DOUBLE/10000 r,
       1+(i%5)::DOUBLE/10 w, 100+sin(i::DOUBLE)*5 px
FROM range({rows}) z(i);
CREATE TEMP TABLE calendar_dates AS SELECT DATE '2026-01-01'+(i%365)::INTEGER d
FROM range({rows}) z(i);
"""
    cases = {
        "bsm_separate": "SELECT fsum(fin_bsm_price(kind,s,k,t,r,v)) price, fsum(fin_bsm_delta(kind,s,k,t,r,v)) delta, fsum(fin_bsm_vega(kind,s,k,t,r,v)) vega FROM options",
        "bsm_all": "SELECT fsum(a.price) price, fsum(a.delta) delta, fsum(a.vega) vega FROM (SELECT fin_bsm_all(kind,s,k,t,r,v) a FROM options)",
        "bsm_iv": "SELECT fsum(fin_bsm_implied_vol(kind,bsm,s,k,t,r)) result FROM quotes",
        "black76_iv": "SELECT fsum(fin_black76_implied_vol(kind,black,s,k,t,r)) result FROM quotes",
        "bachelier_iv": "SELECT fsum(fin_bachelier_implied_vol(kind,normal,s-100,k-100,t,r)) result FROM quotes",
        "binomial_default": f"SELECT fsum(fin_binomial_price(kind,s,k,t,r,v)) result FROM (SELECT * FROM options LIMIT {trees})",
        "bond_risk_600_periods": "SELECT fsum(fin_bond_duration(coupon,ytm,300)) duration, fsum(fin_bond_convexity(coupon,ytm,300)) convexity FROM bonds",
        "irr": "SELECT fsum(fin_irr(cf)) result FROM flows",
        "xirr": "SELECT fsum(fin_xirr(cf,dates)) result FROM flows",
        "matrix_vecmul": "SELECT fsum(fin_vector_sum(fin_matrix_vecmul(cov,w))) result FROM vectors",
        "portfolio_risk": "SELECT fsum(fin_portfolio_vol(w,cov)) vol, fsum(fin_vector_sum(fin_component_risk(w,cov))) components FROM vectors",
        "robust_means_cvar": "SELECT fin_trimmed_mean(r) trimmed, fin_winsorized_mean(r) winsorized, fin_cvar(r) cvar FROM observations",
        "weighted_mean": "SELECT fin_weighted_mean(r,w) result FROM observations",
        "weighted_quantile": "SELECT fin_weighted_quantile(r,w,.95) result FROM observations",
        "weighted_quantile_endpoints": "SELECT fin_weighted_quantile(r,w,0) minimum, fin_weighted_quantile(r,w,1) maximum FROM observations",
        "quantile_spread": "SELECT fin_quantile_spread(sin(i::DOUBLE),r) result FROM observations",
        "outlier_count": "SELECT fin_outlier_count(r,1.5) result FROM observations",
        "sortino": "SELECT fin_sortino(r) result FROM observations",
        "ewma": "SELECT fin_ewma_vol(r ORDER BY i) result FROM observations",
        "ema": "SELECT fin_ema(px ORDER BY i) result FROM observations",
        "iv_percentile": "SELECT fin_iv_percentile(px ORDER BY i) result FROM observations",
        "ordered_risk": "SELECT fin_rsi(px ORDER BY i) rsi, fin_ewma_vol(r ORDER BY i) ewma, fin_max_drawdown(r ORDER BY i) drawdown FROM observations",
        "calendar": "SELECT sum(date_diff('day',d,fin_next_business_day(d,'weekday',1000))) result FROM calendar_dates",
        "curve_128_knots": "SELECT fsum(fin_curve_zero_rate(list_transform(range(1,129),lambda x: x/10.0),list_transform(range(1,129),lambda x: .03+.001*x),.1+(i%256)::DOUBLE*.05)) result FROM observations",
    }
    return setup, cases


def select_setup(setup, cases):
    statements = split_statements(setup)
    tables = {re.match(r"CREATE TEMP TABLE ([a-z_]+) AS", statement).group(1): statement
              for statement in statements}
    required = set()
    pending = list(cases.values())
    while pending:
        query = pending.pop()
        for name, statement in tables.items():
            if name not in required and re.search(rf"\bFROM\s+{name}\b", query, re.I):
                required.add(name)
                pending.append(statement)
    return "\n".join(statement for name, statement in tables.items() if name in required)


def decode_output(stdout):
    timings = [float(v) for v in re.findall(r"^Run Time \(s\): real ([\d.]+)", stdout, re.M)]
    clean = re.sub(r"^Run Time \(s\):[^\n]*\n?", "", stdout, flags=re.M)
    decoder = json.JSONDecoder()
    results = []
    while clean.strip():
        clean = clean.lstrip()
        value, end = decoder.raw_decode(clean)
        results.append(value)
        clean = clean[end:]
    return timings, results


def equivalent(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(equivalent(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(equivalent(x, y) for x, y in zip(a, b))
    if isinstance(a, (float, int)) and isinstance(b, (float, int)):
        return math.isfinite(a) and math.isfinite(b) and math.isclose(a, b, rel_tol=1e-8, abs_tol=1e-8)
    return a == b


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duckdb", required=True)
    parser.add_argument("--extension", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--profile-dir", type=Path, help="Collect one untimed JSON operator profile per selected case")
    parser.add_argument("--scale", type=float, default=1.0, help="Fraction of one million input rows (default: 1)")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--case", action="append", help="Run only a named case; repeat to select multiple cases")
    args = parser.parse_args()
    if not math.isfinite(args.scale) or args.scale <= 0 or args.threads < 1 or args.warmups < 0 or args.repeats < 1:
        parser.error("scale/threads/repeats must be positive and warmups non-negative")
    setup, cases = workload(args.scale)
    if args.case:
        unknown = set(args.case) - cases.keys()
        if unknown:
            parser.error(f"Unknown cases: {', '.join(sorted(unknown))}")
        cases = {name: cases[name] for name in args.case}
    setup = select_setup(setup, cases)
    baseline = None
    if args.baseline:
        baseline = json.loads(args.baseline.read_text())
        if baseline["scale"] != args.scale or baseline["threads"] != args.threads:
            parser.error("Baseline scale and thread count must match")
        for name, query in cases.items():
            if name not in baseline["cases"] or baseline["cases"][name]["sql"] != query:
                parser.error(f"Baseline has no matching query for {name}")
    sql = f".bail on\nLOAD {sql_literal(args.extension)};\nSET threads={args.threads};\nSET enable_progress_bar=false;\n{setup}\n.timer on\n"
    runs = args.warmups + args.repeats
    sql += "\n".join(query + ";" for query in cases.values() for _ in range(runs)) + "\n"
    if args.profile_dir:
        args.profile_dir.mkdir(parents=True, exist_ok=True)
        sql += ".timer off\nPRAGMA enable_profiling='json';\n"
        for name, query in cases.items():
            profile = args.profile_dir / f"{name}.json"
            profile.unlink(missing_ok=True)
            sql += f"PRAGMA profiling_output={sql_literal(str(profile.resolve()))};\n{query};\n"
    process = subprocess.run([args.duckdb, "-init", "/dev/null", "-unsigned", "-json"], input=sql, text=True, capture_output=True)
    if process.returncode:
        raise RuntimeError(process.stderr or process.stdout)
    try:
        timings, results = decode_output(process.stdout)
    except ValueError:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        diagnostic = Path(str(args.output) + ".stdout.txt")
        diagnostic.write_text(process.stdout)
        raise RuntimeError(f"Could not decode DuckDB output; see {diagnostic}") from None
    profile_count = len(cases) if args.profile_dir else 0
    if len(timings) != len(cases)*runs or len(results) != len(timings)+profile_count:
        raise RuntimeError("DuckDB returned an unexpected number of timings/results")
    measurements = {}
    for i, (name, query) in enumerate(cases.items()):
        values = timings[i*runs+args.warmups:(i+1)*runs]
        result = results[i*runs]
        if not all(equivalent(result, r) for r in results[i*runs:(i+1)*runs]):
            raise RuntimeError(f"Inconsistent repeated results for {name}")
        measurements[name] = {"median_seconds": statistics.median(values), "seconds": values, "result": result, "sql": query}
        if args.profile_dir:
            if not equivalent(result, results[len(timings)+i]):
                raise RuntimeError(f"Profiled result differs for {name}")
            profile = args.profile_dir / f"{name}.json"
            json.loads(profile.read_text())
            measurements[name]["profile"] = str(profile.resolve())
    report = {"duckdb": args.duckdb, "extension": args.extension, "scale": args.scale,
              "threads": args.threads, "warmups": args.warmups, "repeats": args.repeats, "cases": measurements}
    if args.baseline:
        for name, measurement in measurements.items():
            before = baseline["cases"][name]
            if not equivalent(before["result"], measurement["result"]):
                raise RuntimeError(f"Baseline query/result mismatch for {name}")
            measurement["speedup"] = before["median_seconds"]/measurement["median_seconds"] if measurement["median_seconds"] else None
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    for name, m in measurements.items():
        change = f" ({m['speedup']:.2f}x)" if m.get("speedup") is not None else ""
        print(f"{name}: {m['median_seconds']:.6f}s{change}")


if __name__ == "__main__":
    main()
