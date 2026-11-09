"""Tests for the calibre catalogue generator: python3 -m unittest discover -s tools -p 'test_*.py'"""
import json, os, subprocess, sys, unittest

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
        for name in ("7.5x55 mm Swiss (GP 11)", "9x19 mm"):
            o = self.outline(name)[1]
            self.assertNotIn("patch", o, name)
            self.assertNotIn("bulletMaterial", o, name)

    def test_original_bullets_and_cases(self):
        # Raven 2026-11-05: draw each calibre's original bullet and case (calibre-data #46).
        self.assertEqual(self.outline(".22 LR")[1]["bulletMaterial"], "lead")
        gras = self.outline("11x59 mm R Gras")[1]
        self.assertEqual(gras["bulletMaterial"], "lead")
        self.assertIn("patch", gras)
        self.assertIn("tip", self.outline("9.3x62 mm")[1])
        self.assertNotIn("tip", self.outline("7.62x51 mm NATO")[1])
        self.assertEqual(self.outline(".17 HMR")[1]["tipMaterial"], "polymer")
        self.assertEqual(self.outline(".277 SIG Fury")[1]["headMaterial"], "steel")
        snider = self.outline(".577 Snider")[1]
        self.assertIn("head", snider, "paper case in a brass cup (calibre-data #49)")
        self.assertNotIn("headMaterial", snider)
        calibers = generate_assets.build()[0]
        materials = {c["outline"]["caseMaterial"] for c in calibers if "caseMaterial" in c["outline"]}
        self.assertTrue(materials)
        self.assertLessEqual(materials, set(generate_assets.CASE_COLOURS))
        by_name = {c["name"]: c["outline"] for c in calibers}
        self.assertEqual(by_name[".45-70 Government"]["currentCaseMaterials"], ["brass"])
        self.assertEqual(by_name["9x19 mm"]["currentCaseMaterials"], ["steel"])


class BlankTests(unittest.TestCase):
    """Alarm and starter blanks (calibre-data #45): no bullet; the app draws only the case."""

    def test_crimped_blanks_have_no_bullet(self):
        calibers = {c["name"]: c for c in generate_assets.build()[0]}
        for name in (".22 Blank (6.8/11)", "9 mm R Knall", ".320 Knall", ".45 Knall", ".22 Long Knall",
                     "6 mm Flobert Knall", "8 mm Knall", ".315 Knall"):
            o = calibers[name]["outline"]
            self.assertNotIn("bullet", o, name)
            self.assertIn("case", o, name)
        self.assertEqual(calibers["9 mm R Knall"]["kind"], "rimmed")
        self.assertIn("9 mm R.K.", calibers["9 mm R Knall"]["displayAliases"])


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

    def test_generated_file_names_the_calibre_data_commit(self):
        """Settings show the calibre-data commit of the app's catalogue (CaliberCatalog.source)."""
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=generate_assets.DATA, text=True).strip()
        with open(os.path.join(ROOT, "Schiesstagebuch", "Resources", "Calibers.json")) as f:
            stored = json.load(f)["calibreData"]
        self.assertEqual(stored["commit"], head, "run python3 tools/generate_assets.py")
        # The committer date with its offset, which the app decodes as ISO 8601.
        self.assertRegex(stored["date"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(Z|[+-]\d\d:\d\d)$")


if __name__ == "__main__":
    unittest.main()
