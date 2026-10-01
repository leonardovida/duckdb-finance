import unittest

from benchmark_functions import decode_output, equivalent, select_setup, workload


class BenchmarkTests(unittest.TestCase):
    def test_cli_json_and_timings_remain_aligned(self):
        output = '[{"result":2.0}]\nRun Time (s): real 0.125 user 0.1 sys 0.0\n'
        output += '[{"result":null}]\nRun Time (s): real 0.001 user 0.0 sys 0.0\n'
        times, results = decode_output(output)
        self.assertEqual(times, [0.125, 0.001])
        self.assertEqual(results, [[{"result": 2.0}], [{"result": None}]])

    def test_output_comparison_rejects_missing_and_changed_results(self):
        self.assertTrue(equivalent([{"v": 1.0}], [{"v": 1.0 + 1e-10}]))
        self.assertFalse(equivalent([{"v": 1.0}], [{"v": None}]))
        self.assertFalse(equivalent([{"v": 1.0}], [{"other": 1.0}]))
        self.assertFalse(equivalent([{"v": 1.0}], [{"v": 1.1}]))
        self.assertFalse(equivalent([{"v": 1.0}], []))

    def test_nonfinite_results_cannot_pass_numeric_comparison(self):
        self.assertFalse(equivalent(float("nan"), float("nan")))
        self.assertFalse(equivalent(float("inf"), float("inf")))

    def test_workload_changes_scale_without_changing_queries(self):
        small_setup, small_cases = workload(.01)
        large_setup, large_cases = workload(1)
        self.assertIn('range(10000)', small_setup)
        self.assertIn('range(1000000)', large_setup)
        self.assertEqual(small_cases['bond_risk_600_periods'], large_cases['bond_risk_600_periods'])

    def test_selected_setup_includes_dependencies_and_omits_other_tables(self):
        setup, cases = workload(.01)
        selected = select_setup(setup, {'bsm_iv': cases['bsm_iv']})
        self.assertIn('CREATE TEMP TABLE options', selected)
        self.assertIn('CREATE TEMP TABLE quotes', selected)
        self.assertNotIn('CREATE TEMP TABLE bonds', selected)
        selected = select_setup(setup, {'weighted_mean': cases['weighted_mean']})
        self.assertIn('CREATE TEMP TABLE observations', selected)
        self.assertNotIn('CREATE TEMP TABLE options', selected)


if __name__ == "__main__":
    unittest.main()
