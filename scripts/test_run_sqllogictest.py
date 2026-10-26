import tempfile
import unittest
from pathlib import Path

from run_sqllogictest import parse


def parse_text(text: str):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "case.test"
        path.write_text(text)
        return parse(path)


class SqlLogicTestParsingTests(unittest.TestCase):
    def test_records_and_expected_output(self):
        records = parse_text(
            "require finance\n\n"
            "statement ok\nLOAD finance\n\n"
            "# comment\n"
            "statement error\nSELECT fin_mid(1.0)\n----\nNo function matches\n\n"
            "query IR rowsort\nSELECT 1,\n  2.0\n----\n1\t2.0\n0\t1.0\n"
        )
        self.assertEqual([record.kind for record in records], ["ok", "error", "query"])
        self.assertEqual(records[0].sql, "LOAD finance")
        self.assertEqual(records[1].expected, ["No function matches"])
        self.assertEqual(records[2].sql, "SELECT 1,\n  2.0")
        self.assertEqual(records[2].expected, ["1\t2.0", "0\t1.0"])
        self.assertEqual(records[2].sort, "rowsort")
        self.assertEqual(records[2].line, 12)
        self.assertEqual(records[2].columns, 2)

    def test_unsupported_records_are_rejected(self):
        for text in ("query I valuesort\nSELECT 1\n----\n1\n", "loop i 0 2\n", "statement ok\nSELECT 1\n----\n1\n"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_text(text)


if __name__ == "__main__":
    unittest.main()
