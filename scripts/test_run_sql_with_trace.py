import unittest

from run_sql_with_trace import split_statements


class StatementSplittingTests(unittest.TestCase):
    def test_line_comments_preserve_semicolons_and_quotes(self):
        for newline in ("\n", "\r\n"):
            with self.subTest(newline=newline):
                first = "-- Don't split here; still a comment" + newline + "SELECT 1;"
                self.assertEqual(split_statements(first + newline + "SELECT 2;"), [first, "SELECT 2;"])

    def test_nested_block_comments_preserve_boundaries(self):
        first = "/* outer ' ; /* nested \" ; */ still a comment; */ SELECT 1;"
        self.assertEqual(split_statements(first + " SELECT 2;"), [first, "SELECT 2;"])

    def test_comment_markers_inside_quoted_values_are_not_comments(self):
        sql = "SELECT '--;/*', 'it''s;', 1 AS \"a\"\";--\";"
        self.assertEqual(split_statements(sql + " SELECT 2;"), [sql, "SELECT 2;"])

    def test_trailing_comment_is_preserved(self):
        self.assertEqual(split_statements("SELECT 1; -- trailing; '"), ["SELECT 1;", "-- trailing; '"])


if __name__ == "__main__":
    unittest.main()
