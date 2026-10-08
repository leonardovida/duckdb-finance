import tempfile
import unittest
from pathlib import Path

from function_examples import ExampleError, parse_examples, render_signatures


def parse(text: str):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "examples.sql"
        path.write_text(text, encoding="utf-8")
        return parse_examples(path)


class ParseExamplesTest(unittest.TestCase):
    def test_parses_headers_signatures_and_multiline_sql(self) -> None:
        examples = parse(
            "-- preamble\n\n"
            "-- fin_npv(rate, cashflows)\n"
            "-- fin_npv(cashflows, times, rate, compounding)\n"
            "SELECT fin_npv(0.1, [-100.0, 60.0])\n"
            "FROM range(1);\n\n"
            "-- fin_alpha\n"
            "SELECT fin_alpha(r, b) FROM (VALUES (0.1, 0.2)) t(r, b);\n"
        )
        self.assertEqual([example.name for example in examples], ["fin_npv", "fin_alpha"])
        self.assertEqual(examples[0].sql, "SELECT fin_npv(0.1, [-100.0, 60.0]) FROM range(1);")
        self.assertEqual(render_signatures(examples[0]), "rate,cashflows;cashflows,times,rate,compounding")
        self.assertEqual(render_signatures(examples[1]), "")

    def test_type_hints(self) -> None:
        examples = parse("-- fin_next(date, days:BIGINT)\nSELECT fin_next(DATE '2026-01-01', 1);\n")
        self.assertEqual(render_signatures(examples[0]), "date,days:BIGINT")

    def test_rejects_multiple_statements(self) -> None:
        with self.assertRaisesRegex(ExampleError, "exactly one statement"):
            parse("-- fin_bps(x)\nSELECT fin_bps(1.0); SELECT 2;\n")

    def test_rejects_comment_inside_example(self) -> None:
        with self.assertRaisesRegex(ExampleError, "comments are not allowed"):
            parse("-- fin_bps(x)\nSELECT fin_bps(1.0)\n-- note\n;\n")

    def test_rejects_unterminated_example(self) -> None:
        with self.assertRaisesRegex(ExampleError, "does not end"):
            parse("-- fin_bps(x)\nSELECT fin_bps(1.0)\n")

    def test_rejects_mixed_header_names(self) -> None:
        with self.assertRaisesRegex(ExampleError, "without an example"):
            parse("-- fin_bps(x)\n-- fin_from_bps(x)\nSELECT fin_bps(1.0);\n")


if __name__ == "__main__":
    unittest.main()
