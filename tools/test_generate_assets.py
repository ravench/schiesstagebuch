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
        # The army's 1892 drawing (calibre-data #113): 12.7 of the 23.7 mm out of the case are paper.
        self.assertAlmostEqual(max(ys) - min(ys), 12.7, places=1)
        self.assertLess(max(ys) - min(ys), mouth, "the capped nose shows")

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
            self.assertNotIn("patch", self.outline(name)[1], name)
        self.assertNotIn("bulletMaterial", self.outline("9x19 mm")[1])
        # calibre-data #115: the GP 11's first bullet had a cupronickel-plated steel jacket.
        self.assertEqual(self.outline("7.5x55 mm Swiss (GP 11)")[1]["bulletMaterial"], "cupronickel")

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
        self.assertEqual(by_name["9x19 mm"]["currentCaseMaterials"], ["steel", "aluminium"])


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

    def test_rimfire_and_centrefire_versions_are_not_grouped(self):
        """calibre-data f049201: the Vetterli is rimfire and its centrefire version a calibre of its own,
        with the same measurements; a rimfire gun cannot fire the centrefire one."""
        groups = generate_assets.dimension_groups()
        kinds = {c["name"]: c["kind"] for c in generate_assets.build()[0]}
        for rimfire, centrefire in [("10.4x38 mm R Vetterli", "10.4x38 mm R Vetterli Centrefire"),
                                    (".44 Henry", ".44 Henry Centrefire"), (".32 Long Rimfire", ".32 Long Centrefire")]:
            self.assertEqual((kinds[rimfire], kinds[centrefire]), ("rimfire", "rimmed"))
            self.assertNotIn(rimfire, groups)
            self.assertNotIn(centrefire, groups)

    def test_swiss_match_is_its_own_cartridge(self):
        """calibre-data #77: the 6x47 mm SM (Swiss Match) is a rifle calibre of its own, found by its
        common names, and not the 6.5x47 mm Lapua's chamber."""
        groups = generate_assets.dimension_groups()
        sm = next(c for c in generate_assets.build()[0] if c["name"] == "6x47 mm SM")
        self.assertEqual(sm["category"], "Langwaffe")
        self.assertIn("6x47", sm["aliases"])
        self.assertIn("swiss match", sm["aliases"])
        self.assertNotIn("6x47 mm SM", groups)
        self.assertNotIn("6.5x47 mm Lapua", groups)

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
        self.assertRegex(stored["date"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$",
                         "a numeric offset, never Z, whichever git version wrote it")


class CatalogueOnlyDataTests(unittest.TestCase):
    def test_catalogue_only_data_stays_out(self):
        """calibre-data eafed3b: the cannon rounds (Kanone), tip colours and fired-by lists are for the
        catalogue only; the app knows six categories and reads none of them."""
        from cartridges import ALL_CATALOGUE, COLOUR_CODES, FIRED_BY
        calibers = generate_assets.build()[0]
        cannon = {s["name"] for cat, items in ALL_CATALOGUE if cat == "Kanone" for s in items}
        self.assertTrue(cannon)
        self.assertFalse(cannon & {c["name"] for c in calibers})
        self.assertEqual({c["category"] for c in calibers},
                         {"Randfeuer", "Kurzwaffe", "Langwaffe", "Schwarzpulver", "Flinte", "Luftdruck"})
        self.assertTrue(COLOUR_CODES and FIRED_BY)
        self.assertEqual(set().union(*calibers), {"id", "name", "category", "kind", "aliases", "displayAliases",
                                                  "dimensionGroup", "outline", "obsolete", "rare"})

    def test_obsolete_and_rare_are_flagged(self):
        """calibre-data #114: `obsolete` and `rare` (cartridges.tags) go into the JSON so the app can keep
        rare calibres behind the search; a current, common calibre has neither key."""
        import cartridges
        by_name = {c["name"]: c for c in generate_assets.build()[0]}
        self.assertEqual({k for k in by_name["9x19 mm"] if k in ("obsolete", "rare")}, set())
        self.assertEqual({n for n, c in by_name.items() if c.get("obsolete")}, cartridges.OBSOLETE & set(by_name))
        self.assertEqual({n for n, c in by_name.items() if c.get("rare")}, cartridges.RARE & set(by_name))
        self.assertTrue(cartridges.RARE & set(by_name), "the catalogue has rare calibres")

    def test_bump_tool_regenerates_the_assets(self):
        """tools/bump_data.py moves the submodule and runs the generators (ported from Kaliberfinder)."""
        with open(os.path.join(ROOT, "tools", "bump_data.py")) as f:
            source = f.read()
        self.assertIn('("generate_assets.py", "localize.py")', source)
        self.assertNotIn("fixture", source.lower().split("ported")[0].split("import")[0] + source.split('"""', 2)[2],
                         "this repo has no catalogue fixture")

    def test_ci_refuses_a_submodule_behind_main(self):
        """A merge can keep a branch's older calibre-data pointer and so revert a bump once merged
        (Kaliberfinder PR 188): the tools job checks the pointer against main's and regenerates."""
        with open(os.path.join(ROOT, ".github", "workflows", "build.yml")) as f:
            tools_job = f.read().split("  tools:", 1)[1].split("  build:", 1)[0]
        self.assertIn("merge-base --is-ancestor", tools_job)
        self.assertIn("tools/bump_data.py", tools_job)
        self.assertIn("python3 tools/generate_assets.py", tools_job)
        self.assertIn("git diff --exit-code Schiesstagebuch/Resources", tools_job)


if __name__ == "__main__":
    unittest.main()
