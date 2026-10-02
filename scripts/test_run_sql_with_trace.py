import unittest

from run_sql_with_trace import profile_path, split_statements, sql_literal
from pathlib import Path


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

    def test_dollar_quoted_strings_keep_statement_boundaries(self):
        for marker in ("$$", "$finance_tag$"):
            first = f"SELECT {marker}a; '-- /* \" $other$ b{marker};"
            self.assertEqual(split_statements(first + " SELECT 2;"), [first, "SELECT 2;"])

    def test_dollar_quotes_in_comments_and_identifiers(self):
        first = '-- $$;\nSELECT 1 AS "$tag$;";'
        self.assertEqual(split_statements(first + " SELECT 2;"), [first, "SELECT 2;"])

    def test_escape_strings_preserve_escaped_quotes_and_semicolons(self):
        for prefix in ("E", "e"):
            for backslashes in (1, 3, 5):
                with self.subTest(prefix=prefix, backslashes=backslashes):
                    first = "SELECT " + prefix + "'one" + "\\" * backslashes + "';two' AS s;"
                    self.assertEqual(split_statements(first + " SELECT 2;"), [first, "SELECT 2;"])

    def test_even_backslashes_allow_escape_string_to_close(self):
        for backslashes in (2, 4, 6):
            with self.subTest(backslashes=backslashes):
                first = "SELECT E'one" + "\\" * backslashes + "' AS s;"
                self.assertEqual(split_statements(first + " SELECT 2;"), [first, "SELECT 2;"])

    def test_escape_mode_survives_newline_literal_continuation(self):
        for separator in ("\n", "\r\n", " -- comment; ' \\\n"):
            with self.subTest(separator=separator):
                first = "SELECT E'first'" + separator + "'second\\';third' AS s;"
                self.assertEqual(split_statements(first + " SELECT 2;"), [first, "SELECT 2;"])

    def test_standard_strings_keep_literal_backslashes(self):
        first = "SELECT 'one\\' AS s;"
        self.assertEqual(split_statements(first + " SELECT 2;"), [first, "SELECT 2;"])

    def test_identifier_suffix_is_not_an_escape_prefix(self):
        for identifier in ("fooE", "_E", "foo$E", "name\u00a7E"):
            with self.subTest(identifier=identifier):
                first = "SELECT " + identifier + "'one\\' AS s;"
                self.assertEqual(split_statements(first + " SELECT 2;"), [first, "SELECT 2;"])

    def test_paths_are_escaped_as_sql_literals(self):
        self.assertEqual(sql_literal("/tmp/it's an extension"), "'/tmp/it''s an extension'")

    def test_profiles_have_distinct_paths(self):
        output = Path("/tmp/profile.json")
        self.assertEqual(profile_path(output, 2), Path("/tmp/profile.json.d/statement-0002.json"))
        self.assertNotEqual(profile_path(output, 1), profile_path(output, 2))


if __name__ == "__main__":
    unittest.main()
