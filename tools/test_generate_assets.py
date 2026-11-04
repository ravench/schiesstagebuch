"""Tests for the calibre catalogue generator: python3 -m unittest discover -s tools -p 'test_*.py'"""
import json, os, sys, unittest

sys.path.insert(0, os.path.dirname(__file__))
import generate_assets  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class PatchedBulletTests(unittest.TestCase):
    """GP 1890: paper-patched lead body with a steel-capped round nose."""

    def outline(self, name):
        from cartridges import CATALOGUE
        spec = next(s for _, items in CATALOGUE for s in items if s["name"] == name)
        return spec, generate_assets.outline(spec)

    def test_gp1890_has_paper_band_and_steel_cap(self):
        spec, o = self.outline("7.5x53.5 mm Swiss (GP 1890)")
        self.assertEqual(o["bulletMaterial"], "steel")
        self.assertIn("patch", o)

    def test_paper_band_starts_at_the_case_mouth(self):
        spec, o = self.outline("7.5x53.5 mm Swiss (GP 1890)")
        mouth = spec["oal"] - spec["case"]  # SVG y grows downwards from the tip
        ys = [float(p.split()[1]) for p in o["patch"].replace("Z", "").replace("M", "L").split("L") if p.strip()]
        self.assertAlmostEqual(max(ys), mouth, places=2)
        self.assertLess(max(ys) - min(ys), mouth / 2, "most of the visible bullet is the steel cap")

    def test_profile_steps_in_where_the_paper_ends(self):
        spec = self.outline("7.5x53.5 mm Swiss (GP 1890)")[0]
        r = spec["bullet"] / 2
        pts = generate_assets.bullet_profile(r, spec["case"], spec["oal"], spec["profile"])
        self.assertEqual(pts[0][0], r)
        self.assertLess(pts[2][0], r, "steel cap is a paper's thickness narrower")
        self.assertEqual(pts[-1], (0, spec["oal"]))
        self.assertTrue(all(b[1] >= a[1] for a, b in zip(pts, pts[1:])), "profile runs from base to tip")

    def test_jacketed_bullets_have_no_patch(self):
        for name in ("7.5x55 mm Swiss (GP 11)", "9x19 mm", ".22 LR"):
            o = self.outline(name)[1]
            self.assertNotIn("patch", o, name)
            self.assertNotIn("bulletMaterial", o, name)


class CalibreDataSubmoduleTests(unittest.TestCase):
    """The catalogue comes from the shared calibre-data submodule (github.com/ravench/calibre-data)."""

    def test_catalogue_comes_from_the_submodule(self):
        import cartridges, outline
        data = os.path.join(ROOT, "calibre-data")
        self.assertTrue(os.path.isfile(os.path.join(data, "cartridges.py")), "run: git submodule update --init")
        self.assertEqual(os.path.dirname(os.path.abspath(cartridges.__file__)), data)
        self.assertIs(generate_assets.outline, outline.outline)
        self.assertFalse(os.path.exists(os.path.join(ROOT, "tools", "cartridges.py")), "no second copy of the catalogue")

    def test_ci_checks_out_the_submodule(self):
        with open(os.path.join(ROOT, ".gitmodules")) as f:
            self.assertIn("url = https://github.com/ravench/calibre-data", f.read())
        with open(os.path.join(ROOT, ".github", "workflows", "build.yml")) as f:
            build_job = f.read().split("  build:", 1)[1]
        self.assertIn("submodules: true", build_job.split("- run:", 1)[0])


class DimensionGroupTests(unittest.TestCase):
    def test_identical_chambers_share_a_group(self):
        groups = generate_assets.dimension_groups()
        self.assertEqual(groups[".308 Winchester"], groups["7.62x51 mm NATO"])
        self.assertEqual(groups[".223 Remington"], groups["5.56x45 mm NATO"])
        self.assertEqual(groups["5.6 mm GP 90"], groups["5.56x45 mm NATO"])

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
