"""Tests for the shooting position pictograms: python3 -m unittest discover -s tools -p 'test_*.py'"""
import json, os, re, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(__file__))
import position_icons  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(os.path.join(ROOT, "Schiesstagebuch", "Models", "ShootingPosition.swift")) as _f:
    SWIFT = _f.read()


def subpaths(d):
    for part in d.split("Z"):
        nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", part)]
        if nums:
            yield list(zip(nums[::2], nums[1::2]))


def signed_area(pts):
    return sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1])) / 2


class PositionIconTests(unittest.TestCase):
    def test_one_icon_per_position_case(self):
        cases = re.search(r"case (prone[^\n]*)", SWIFT).group(1).replace(" ", "").split(",")
        self.assertEqual(set(position_icons.ICONS), set(cases))

    def test_shapes_wind_the_same_way_so_overlaps_join(self):
        # One path filled with the non-zero rule: a shape wound the other way would punch a hole.
        for key, paths in position_icons.ICONS.items():
            for d in paths:
                for pts in subpaths(d):
                    self.assertGreater(signed_area(pts), 0, key)

    def test_shapes_stay_in_the_box(self):
        for key, paths in position_icons.ICONS.items():
            for d in paths:
                for pts in subpaths(d):
                    for x, y in pts:
                        self.assertTrue(0 <= x <= 48 and 0 <= y <= 48, f"{key}: {x} {y}")

    def test_written_sets_are_vector_templates(self):
        with tempfile.TemporaryDirectory() as tmp:
            position_icons.write(tmp)
            for key in position_icons.ICONS:
                folder = os.path.join(tmp, f"Position-{key}.imageset")
                info = json.load(open(os.path.join(folder, "Contents.json")))
                self.assertEqual(info["properties"]["template-rendering-intent"], "template")
                self.assertTrue(info["properties"]["preserves-vector-representation"])
                svg = open(os.path.join(folder, info["images"][0]["filename"])).read()
                self.assertIn('viewBox="0 0 48 48"', svg)

    def test_checked_in_sets_are_up_to_date(self):
        assets = os.path.join(ROOT, "Schiesstagebuch", "Resources", "Assets.xcassets")
        for key, paths in position_icons.ICONS.items():
            with open(os.path.join(assets, f"Position-{key}.imageset", f"Position-{key}.svg")) as f:
                self.assertEqual(f.read(), position_icons.svg(paths), f"run tools/position_icons.py ({key})")


if __name__ == "__main__":
    unittest.main()
