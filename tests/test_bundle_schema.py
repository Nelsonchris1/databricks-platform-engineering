import unittest

from scripts.check_bundle_schema import make_validator


class BundleSchemaTests(unittest.TestCase):
    def test_cli_unicode_patterns_accept_letters_and_reject_other_values(self):
        validator = make_validator({"type": "string", "pattern": r"^[\p{L}]+$"})
        self.assertTrue(validator.is_valid("café"))
        self.assertFalse(validator.is_valid("café123"))
        self.assertFalse(validator.is_valid(123))

    def test_unknown_fields_and_invalid_types_remain_errors(self):
        validator = make_validator({
            "type": "object", "additionalProperties": False,
            "properties": {"timeout_seconds": {"type": "integer"}},
        })
        self.assertTrue(validator.is_valid({"timeout_seconds": 1800}))
        self.assertFalse(validator.is_valid({"timeout_seconds": "forever"}))
        self.assertFalse(validator.is_valid({"unsupported_flag": True}))
