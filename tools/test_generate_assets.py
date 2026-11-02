"""Tests for the calibre catalogue generator: python3 -m unittest discover -s tools -p 'test_*.py'"""
import json, os, sys, unittest

sys.path.insert(0, os.path.dirname(__file__))
import generate_assets  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class DimensionGroupTests(unittest.TestCase):
    def test_identical_chambers_share_a_group(self):
        groups = generate_assets.dimension_groups()
        self.assertEqual(groups[".308 Winchester"], groups["7.62x51 mm NATO"])
        self.assertEqual(groups[".223 Remington"], groups["5.56x45 mm NATO"])
        self.assertEqual(groups["5.6 mm GP 90 (Swiss)"], groups["5.56x45 mm NATO"])

    def test_different_cartridges_are_not_grouped(self):
        groups = generate_assets.dimension_groups()
        self.assertNotIn("9x19 mm", groups)
        self.assertNotIn(".38 Special", groups, "a .357 chamber takes .38 Spl, but the cases differ")
        self.assertNotEqual(groups[".308 Winchester"], groups[".223 Remington"])

    def test_generated_file_is_up_to_date(self):
        calibers, _ = generate_assets.build()
        with open(os.path.join(ROOT, "Schiesstagebuch", "Resources", "Calibers.json")) as f:
            stored = json.load(f)["calibers"]
        self.assertEqual(stored, json.loads(json.dumps(calibers)), "run python3 tools/generate_assets.py")


if __name__ == "__main__":
    unittest.main()
