"""Terms that Schiesstagebuch and Kaliberfinder translate the same way (Raven, 2026-11-05)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from translations import T  # noqa: E402


class SharedTermTests(unittest.TestCase):
    def test_weapon_categories_match_kaliberfinder_in_french(self):
        self.assertEqual(T["Flinte"][1], "Fusil de chasse")
        self.assertEqual(T["Langwaffe"][1], "Arme longue")
        self.assertEqual(T["Kurzwaffe"][1], "Arme de poing")


if __name__ == "__main__":
    unittest.main()
