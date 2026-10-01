import unittest

from check_function_usability import PLACEHOLDER_PATTERNS


class PlaceholderDetectionTests(unittest.TestCase):
    def test_ignored_smoothing_and_decay_parameters_are_flagged(self):
        for definition in ("(x, period := 20) AS avg(x)", "(x, ts, halflife) AS avg(x)",
                           "(x, ts, halflife) AS fsum(x)", "(x, ts, halflife) AS max(x)",
                           "(ts, halflife) AS count(ts)"):
            with self.subTest(definition=definition):
                self.assertTrue(any(pattern.search(definition) for pattern in PLACEHOLDER_PATTERNS))

    def test_plain_means_and_actual_parameter_use_are_allowed(self):
        for definition in ("(x) AS avg(x)", "(x, p) AS native_ema(x,p)",
                           "(x, p) AS avg(x) * p", "(x, ts, halflife) AS native_decay(x,ts,halflife)"):
            with self.subTest(definition=definition):
                self.assertFalse(any(pattern.search(definition) for pattern in PLACEHOLDER_PATTERNS))
