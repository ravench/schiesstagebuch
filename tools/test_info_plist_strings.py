"""The permission texts iOS shows: the German ones in project.yml and their translations in
Schiesstagebuch/Resources/InfoPlist.xcstrings are kept by hand in two places and must agree.

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import json
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class InfoPlistStringsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, "project.yml")) as f:
            cls.project = dict(re.findall(r'INFOPLIST_KEY_(\w+UsageDescription): "([^"]+)"', f.read()))
        with open(os.path.join(ROOT, "Schiesstagebuch", "Resources", "InfoPlist.xcstrings")) as f:
            cls.strings = json.load(f)["strings"]

    def test_every_permission_text_is_in_both_places(self):
        self.assertTrue(self.project, "no usage descriptions found in project.yml")
        catalogue = {k for k in self.strings if k.endswith("UsageDescription")}
        self.assertEqual(set(self.project), catalogue)

    def test_german_is_the_same_in_both(self):
        for key, text in self.project.items():
            self.assertEqual(self.strings[key]["localizations"]["de"]["stringUnit"]["value"], text, key)

    def test_all_four_languages_are_there(self):
        for key in self.project:
            for lang in ("de", "en", "fr", "it"):
                value = self.strings[key]["localizations"].get(lang, {}).get("stringUnit", {}).get("value", "")
                self.assertTrue(value.strip(), f"{key} has no {lang} text")


if __name__ == "__main__":
    unittest.main()
