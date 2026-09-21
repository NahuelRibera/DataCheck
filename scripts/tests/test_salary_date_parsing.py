import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from salary_date_parsing import ParseError, is_valid_email, parse_date, parse_salary_to_cents


class ParseDateTests(unittest.TestCase):
    def test_iso_format_is_not_normalized(self):
        iso, normalized = parse_date("2024-03-05")
        self.assertEqual(iso, "2024-03-05")
        self.assertFalse(normalized)

    def test_us_slash_format_is_normalized(self):
        iso, normalized = parse_date("03/05/2024")
        self.assertEqual(iso, "2024-03-05")
        self.assertTrue(normalized)

    def test_dashed_day_first_format_is_normalized(self):
        iso, normalized = parse_date("05-03-2024")
        self.assertEqual(iso, "2024-03-05")
        self.assertTrue(normalized)

    def test_blank_raises(self):
        with self.assertRaises(ParseError):
            parse_date("")

    def test_garbage_raises(self):
        with self.assertRaises(ParseError):
            parse_date("not-a-date")

    def test_impossible_date_raises(self):
        with self.assertRaises(ParseError):
            parse_date("31/02/2024")


class ParseSalaryTests(unittest.TestCase):
    def test_plain_decimal(self):
        cents, normalized = parse_salary_to_cents("32500.50")
        self.assertEqual(cents, 3250050)
        self.assertFalse(normalized)

    def test_us_thousands_separator(self):
        cents, normalized = parse_salary_to_cents("32,500.50")
        self.assertEqual(cents, 3250050)
        self.assertTrue(normalized)

    def test_european_decimal_comma(self):
        cents, normalized = parse_salary_to_cents("32500,50")
        self.assertEqual(cents, 3250050)
        self.assertTrue(normalized)

    def test_currency_prefixed_thousands(self):
        cents, normalized = parse_salary_to_cents("€42,000")
        self.assertEqual(cents, 4200000)
        self.assertTrue(normalized)

    def test_negative_raises(self):
        with self.assertRaises(ParseError):
            parse_salary_to_cents("-500.00")

    def test_non_numeric_raises(self):
        with self.assertRaises(ParseError):
            parse_salary_to_cents("abc")

    def test_blank_raises(self):
        with self.assertRaises(ParseError):
            parse_salary_to_cents("")


class EmailValidationTests(unittest.TestCase):
    def test_valid_email(self):
        self.assertTrue(is_valid_email("person@example.com"))

    def test_missing_at_symbol(self):
        self.assertFalse(is_valid_email("missing-at-symbol.com"))

    def test_missing_domain(self):
        self.assertFalse(is_valid_email("broken@"))


if __name__ == "__main__":
    unittest.main()
