"""Checks that every UI text naming Waffe(n) can switch to Sportgerät(e).

    python3 -m unittest discover -s tools -p 'test_wording.py'
"""
import os
import re
import unittest

import extract_strings
from translations import T

ROOT = extract_strings.ROOT
WORDING = os.path.join(ROOT, "Services", "Wording.swift")
LIT = r'"((?:[^"\\]|\\.)*)"'
# Texts that must keep saying Waffe: the switch itself, data formats and parser input.
KEEP = {"«Sportgeräte» statt «Waffen»"}


def mapping():
    src = open(WORDING).read()
    body = src.split("sportsEquipment: [String: String] = [")[1].split("\n    ]")[0]
    return dict(re.findall(LIT + r'\s*:\s*' + LIT, body))


class WordingTests(unittest.TestCase):
    def test_every_waffe_ui_key_has_a_variant(self):
        m = mapping()
        ui = {k for k, f in extract_strings.keys().items()
              if "Waffe" in k and f not in ("Backup.swift", "LegacyImport.swift", "Wording.swift")}
        self.assertEqual(sorted(ui - set(m) - KEEP), [])

    def test_views_go_through_term(self):
        m = mapping()
        for folder in ("Views", "App"):
            for dirpath, _, files in os.walk(os.path.join(ROOT, folder)):
                for f in files:
                    src = open(os.path.join(dirpath, f)).read()
                    for lit in re.finditer(LIT, src):
                        if lit.group(1) in m:
                            before = src[max(0, lit.start() - 5):lit.start()]
                            self.assertEqual(before, "term(", f"{f}: {lit.group(1)!r} is not wrapped in term(…)")

    def test_variants_are_translated(self):
        for key, variant in mapping().items():
            self.assertIn(key, T)
            self.assertIn(variant, T)
            self.assertNotIn("Waffe", variant)
            en, fr, it = T[variant][:3]
            self.assertNotRegex(en.lower(), r"firearm|weapon", variant)
            self.assertNotRegex(fr.lower(), r"\barmes?\b", variant)
            self.assertNotRegex(it.lower(), r"\barm[ai]\b", variant)


if __name__ == "__main__":
    unittest.main()
