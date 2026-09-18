import collections
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.strings = json.loads((ROOT / "tracken/Resources/Localizable.xcstrings").read_text())["strings"]

    def test_translations_keep_format_arguments(self):
        pattern = r"%(?:\d+\$)?(?:@|lld|ld|d|f|%)"
        for key, entry in self.strings.items():
            for language in ("en", "ko"):
                with self.subTest(key=key, language=language):
                    unit = entry["localizations"][language]["stringUnit"]
                    self.assertEqual(unit["state"], "translated")
                    self.assertTrue(unit["value"])
                    self.assertEqual(collections.Counter(re.findall(pattern, key)),
                                     collections.Counter(re.findall(pattern, unit["value"])))

    def test_dynamic_labels_have_resources(self):
        patterns = [r'L10n\.(?:text|format)\("([^"\n]*)"',
                    r'title:\s*"([^"\n]*)"',
                    r'(?:compactMetric|window|metric)\("([^"\n]*)"']
        for path in (ROOT / "tracken/Features").rglob("*.swift"):
            source = path.read_text()
            for pattern in patterns:
                for key in re.findall(pattern, source):
                    with self.subTest(file=path.name, key=key):
                        self.assertIn(key, self.strings)


if __name__ == "__main__":
    unittest.main()
