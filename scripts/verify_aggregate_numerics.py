#!/usr/bin/env python3
"""Check native aggregates against high-precision, independent SQL-free references."""
import argparse
import math
import random
import subprocess
from decimal import Decimal, localcontext

from benchmark_functions import decode_output
from run_sql_with_trace import sql_literal


def decimal(value):
    return Decimal(str(value))


def weighted_quantile(rows, q, method):
    samples = sorted((decimal(x), decimal(w)) for x, w, _ in rows if w > 0)
    if not samples:
        return None
    q = decimal(q)
    total = sum(w for _, w in samples)
    position = q * total
    previous, previous_weight = samples[0][0], Decimal(0)
    cumulative = Decimal(0)
    for value, weight in samples:
        cumulative += weight
        if position <= cumulative:
            if position == cumulative or method in ("higher", "inverted_cdf"):
                return value
            if method == "lower":
                return previous
            if method == "midpoint":
                return (previous + value) / 2
            if method == "nearest":
                return previous if position - previous_weight <= cumulative - position else value
            return previous + (value - previous) * (position - previous_weight) / weight
        previous, previous_weight = value, cumulative
    return samples[-1][0]


def spread(rows, buckets):
    if not rows:
        return None
    groups = {}
    for value, _, factor in rows:
        groups.setdefault(factor, []).append(decimal(value))
    size = math.ceil(len(rows) / buckets)

    def bucket_mean(factors):
        remaining, total = size, Decimal(0)
        for factor in factors:
            group = groups[factor]
            take = min(remaining, len(group))
            total += sum(group) / len(group) * take
            remaining -= take
            if remaining == 0:
                break
        return total / size

    return bucket_mean(sorted(groups, reverse=True)) - bucket_mean(sorted(groups))


def ema(values, period):
    if not values:
        return None
    alpha = Decimal(2) / (decimal(period) + 1)
    # Explicit geometric weights, rather than the native affine state/merger.
    decay = 1 - alpha
    weights = [decay ** (len(values) - 1)]
    weights += [alpha * decay ** (len(values) - 1 - i) for i in range(1, len(values))]
    return sum(decimal(x) * w for x, w in zip(values, weights))


def ewma_vol(values, decay, annualization):
    if not values:
        return None
    decay = decimal(decay)
    variance = decimal(values[0]) ** 2 * decay ** (len(values) - 1)
    variance += sum((1 - decay) * decay ** (len(values) - 1 - i) * decimal(x) ** 2
                    for i, x in enumerate(values[1:], start=1))
    return (variance * decimal(annualization)).sqrt()


def sortino(values):
    if not values:
        return None
    downside = sum(decimal(x) ** 2 for x in values if x < 0)
    if downside == 0:
        return None
    return sum(map(decimal, values)) / (decimal(len(values)) * downside).sqrt()


def outliers(values, threshold):
    if len(values) < 2:
        return 0
    values = list(map(decimal, values))
    mean = sum(values) / len(values)
    variance = sum((x - mean) ** 2 for x in values) / (len(values) - 1)
    if variance == 0:
        return 0
    cutoff = decimal(threshold) * variance.sqrt()
    return sum(abs(x - mean) > cutoff for x in values)


def percentile(values):
    if len(values) < 2:
        return None
    current = abs(values[-1])
    return Decimal(sum(abs(x) < current for x in values[:-1])) / (len(values) - 1)


def representable(expected):
    if expected is None:
        return None
    result = float(expected)
    return result if math.isfinite(result) else None


def check(label, actual, expected):
    expected = representable(expected)
    if expected is None:
        if actual is not None:
            raise AssertionError(f"{label}: expected NULL, got {actual}")
    elif actual is None or not math.isfinite(actual) or not math.isclose(actual, expected, rel_tol=3e-11, abs_tol=1e-300):
        raise AssertionError(f"{label}: expected {expected}, got {actual}")


def run(duckdb, extension, sql):
    return subprocess.run([duckdb, "-init", "/dev/null", "-unsigned", "-json"],
                          input=f".bail on\nLOAD {sql_literal(extension)};\n{sql}",
                          text=True, capture_output=True, timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duckdb", required=True)
    parser.add_argument("--extension", required=True)
    args = parser.parse_args()
    rng = random.Random(20261001)
    groups = []
    for scale in (1e-200, 1.0, 1e200):
        for _ in range(4):
            groups.append([(rng.uniform(-2, 3) * scale, rng.choice([0, .25, .5, 1, 2]), rng.randrange(5))
                           for _ in range(31)])
    groups += [[(0.0, 1.0, 0)] * 4, [(1e308, 1e308, 1)] * 4,
               [(-1e308, 1e308, 0), (1e308, 1e308, 1)], [(2.0, 0.0, 1)],
               [(1e16, 1.0, 0), (1.0, 1.0, 1), (-1e16, 1.0, 2)],
               [(-1e100, 1.0, 0), (1e308, 1.0, 1)], [(-1e-308, 1.0, 0), (1e-200, 1.0, 1)]]
    # Cross vector boundaries and exercise ordered segment-tree Combine paths.
    groups.append([((i % 7) - 2.0, 1.0, i % 17) for i in range(8197)])
    normal_group = len(groups) - 1
    tied = [(0.0,1.0,0),(10.0,2.0,1),(10.0,5.0,2),(20.0,3.0,3)]
    groups += [tied, list(reversed(tied))]
    groups.append([(1e308 if i == 0 else 0.0, 1.0, i % 17) for i in range(8197)])
    methods = ("linear", "lower", "higher", "nearest", "midpoint", "inverted_cdf")
    cells = ",".join(f"({g},{i},{x!r},{w!r},{f!r})" for g, rows in enumerate(groups) for i, (x, w, f) in enumerate(rows))
    expressions = [f"fin_weighted_quantile(x,w,.73,'{method}') AS q_{method}" for method in methods]
    expressions += ["fin_ema(x,7 ORDER BY i) AS ema", "fin_ewma_vol(x,.8,1 ORDER BY i) AS ewma",
                    "fin_sortino(x,0,1) AS sortino", "fin_outlier_count(x,1.5) AS outliers",
                    "fin_quantile_spread(f,x,3) AS spread", "fin_iv_percentile(abs(x) ORDER BY i) AS percentile"]
    sql = f"CREATE TEMP TABLE observations AS SELECT * FROM (VALUES {cells}) t(g,i,x,w,f);\n"
    sql += "SELECT g," + ",".join(expressions) + " FROM observations GROUP BY g ORDER BY g;\n"
    last_group = len(groups) - 1
    sql += f"""SELECT * FROM (
      SELECT i, fin_ema(x,7) OVER win AS ema, fin_ewma_vol(x,.8,1) OVER win AS ewma,
             fin_iv_percentile(abs(x)) OVER win AS percentile
      FROM observations WHERE g={last_group}
      WINDOW win AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    ) WHERE i >= 8187 ORDER BY i;
    """
    sql += """CREATE TEMP TABLE ungrouped AS SELECT x FROM observations;
    SELECT fin_outlier_count(x,1.5) AS outliers, fin_outlier_count(x) AS defaults FROM ungrouped;
    """
    sql += f"""CREATE TEMP TABLE ordinary AS SELECT x FROM observations WHERE g={normal_group}
    UNION ALL SELECT x FROM (VALUES (1e16),(1.0),(-1e16))t(x);
    SELECT fin_sortino(x) AS sortino FROM ordinary;
    """
    checks = 0
    with localcontext() as context:
        context.prec = 80
        for threads in (1, 4):
            process = run(args.duckdb, args.extension, f"SET threads={threads};\n" + sql)
            if process.returncode:
                raise RuntimeError(process.stderr)
            _, results = decode_output(process.stdout)
            if (len(results) != 4 or len(results[0]) != len(groups) or len(results[1]) != 10 or
                    len(results[2]) != 1 or len(results[3]) != 1):
                raise AssertionError("Missing grouped/windowed results")
            for result, rows in zip(results[0], groups):
                values = [x for x, _, _ in rows]
                expected = {f"q_{method}": weighted_quantile(rows, .73, method) for method in methods}
                expected.update(ema=ema(values, 7), ewma=ewma_vol(values, .8, 1), sortino=sortino(values),
                                outliers=outliers(values, 1.5), spread=spread(rows, 3), percentile=percentile(values))
                for name, value in expected.items():
                    check(f"threads={threads}, group={result['g']}, {name}", result[name], value)
                    checks += 1
            values = [x for rows in groups for x, _, _ in rows]
            for name, threshold in (("outliers",1.5),("defaults",3.0)):
                check(f"threads={threads}, flat ungrouped {name}", results[2][0][name], outliers(values,threshold))
                checks += 1
            values = [x for x, _, _ in groups[normal_group]] + [1e16,1.0,-1e16]
            check(f"threads={threads}, flat ungrouped sortino", results[3][0]['sortino'], sortino(values)*Decimal(252).sqrt())
            checks += 1
            for result in results[1]:
                i = result['i']
                values = [x for x, _, _ in groups[-1][:i+1]]
                for name, expected in (("ema", ema(values, 7)), ("ewma", ewma_vol(values, .8, 1)),
                                       ("percentile", percentile(values))):
                    check(f"threads={threads}, window={i}, {name}", result[name], expected)
                    checks += 1

    invalid = [
        ("SELECT fin_ema(1,0)", "EMA period"),
        ("SELECT fin_ema(1,1.5)", "EMA period"),
        ("SELECT fin_ema(1,2147483648)", "EMA period"),
        ("SELECT fin_ema(1,'Infinity'::DOUBLE)", "EMA period"),
        ("SELECT fin_ema('NaN'::DOUBLE)", "EMA observations"),
        ("SELECT fin_ema(x,p) FROM (VALUES (1,2),(2,3))t(x,p)", "EMA period must be constant"),
        ("SELECT fin_ewma_vol(1,1)", "fin_ewma_vol: lambda"),
        ("SELECT fin_ewma_variance(1,.94,0)", "fin_ewma_variance: annualization"),
        ("SELECT fin_weighted_quantile(1,1,2)", "in [0, 1]"),
        ("SELECT fin_weighted_quantile(1,1,.5,'typo')", "fin_weighted_quantile: unknown method"),
        ("SELECT fin_weighted_quantile(1,1,q) FROM (VALUES (.2),(.3))t(q)", "must be constant"),
        ("SELECT fin_weighted_quantile(1,1,.5,m) FROM (VALUES ('linear'),('lower'))t(m)", "must be constant"),
        ("SELECT fin_quantile_spread(1,2,1)", "buckets must be greater"),
        ("SELECT fin_outlier_count(1,0)", "threshold must be positive"),
        ("SELECT fin_outlier_count(x,t) FROM (VALUES (1.0,1.5),(2.0,2.0))v(x,t)", "must be constant"),
    ]
    for sql, message in invalid:
        process = run(args.duckdb, args.extension, sql + ";\n")
        if process.returncode == 0 or message not in process.stderr:
            raise AssertionError(f"Expected controlled rejection ({message}): {process.stderr}")
    # Non-finite or out-of-domain observations are data, not configuration: the
    # group returns NULL instead of aborting the query.
    null_groups = [
        "SELECT fin_iv_rank(-.1) AS v",
        "SELECT fin_iv_percentile('Infinity'::DOUBLE) AS v",
        "SELECT fin_sortino('NaN'::DOUBLE) AS v",
        "SELECT fin_sortino(1,'Infinity'::DOUBLE) AS v",
        "SELECT fin_ewma_vol('NaN'::DOUBLE) AS v",
        "SELECT fin_weighted_quantile(1,-1,.5) AS v",
    ]
    for sql in null_groups:
        process = run(args.duckdb, args.extension, sql + ";\n")
        if process.returncode:
            raise AssertionError(f"Expected NULL group for {sql}: {process.stderr}")
        _, results = decode_output(process.stdout)
        if results[0][0]["v"] is not None:
            raise AssertionError(f"Expected NULL group for {sql}: {results[0][0]['v']}")
    print(f"Aggregate numerical verification passed: {checks} reference comparisons, {len(invalid)} invalid-input checks, "
          f"{len(null_groups)} NULL-group checks.")


if __name__ == "__main__":
    main()
