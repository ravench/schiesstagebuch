import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import targets  # noqa: E402

TEN_TO_ZERO = list(range(10, -1, -1))


def target(drop=(), **changes):
    t = {
        "_file": "t.toml", "id": "t", "name": "Test", "short_name": "T", "group": "ISSF", "distances_m": [10],
        "ring_diameters_mm": [10, 20, 30, 40], "black_mm": 30,
        "scoring": {"values": [10, 9, 8, 7, 0]},
        "source": {"title": "Rules", "url": "https://example.org"},
    }
    t.update(changes)
    return {k: v for k, v in t.items() if k not in drop}


def inside(x, y, polygon, tolerance=0.2):
    """True if (x, y) lies in the polygon or within `tolerance` mm of its edge."""
    def near_edge(a, b):
        (ax, ay), (bx, by) = a, b
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        return (ax + t * dx - x) ** 2 + (ay + t * dy - y) ** 2 <= tolerance ** 2
    edges = list(zip(polygon, polygon[1:] + polygon[:1]))
    if any(near_edge(a, b) for a, b in edges):
        return True
    crossings = sum(1 for (ax, ay), (bx, by) in edges if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay))
    return crossings % 2 == 1


class RepoTargetTests(unittest.TestCase):
    def setUp(self):
        self.targets = {t["id"]: t for t in targets.load()}

    def test_every_target_in_the_repo_is_fine(self):
        self.assertGreaterEqual(len(self.targets), 16)
        countries = {"Österreich", "Deutschland", "Dänemark", "Frankreich", "Kroatien", "Italien", "Luxemburg",
                     "Niederlande", "Norwegen", "Schweden", "USA", "Kanada", "Grossbritannien"}
        self.assertLessEqual({t["group"] for t in self.targets.values()}, {"Schweiz", "ISSF"} | countries)
        for t in self.targets.values():
            self.assertEqual(targets.problems(t), [], t["_file"])

    def test_other_countries_name_their_country(self):
        # Targets of other countries (from SIUSData) end in their country code, so «A10 Reduced 200 (DK)»
        # and «(SE)» can be told apart in a Stich, and their ids start with it.
        foreign = [t for t in self.targets.values() if t["group"] not in ("Schweiz", "ISSF")]
        self.assertGreaterEqual(len(foreign), 40)
        for t in foreign:
            code = t["id"].split("-")[0]
            self.assertTrue(t["name"].endswith(f"({code.upper()})"), t["id"])
            self.assertIn("SiusData", t["source"]["title"])
        self.assertEqual(self.targets["us-sr1-100y"]["scoring"]["values"], [10, 9, 8, 7, 6, 5, 0])
        self.assertEqual(self.targets["no-dfs-300"]["distances_m"], [300])

    def test_field_figures_count_a_hit(self):
        # Norwegian, Swedish and Danish field figures (added by hand from SIUSData's drawings): a hit
        # anywhere on the figure counts 1, so their only values are 1 and 0; the figure is drawn black.
        figures = [t for t in self.targets.values() if "-felt-" in t["id"] or t["id"].startswith("se-falt-")]
        self.assertGreaterEqual(len(figures), 40)
        for t in figures:
            self.assertEqual(t["scoring"]["values"], [1, 0], t["id"])
            self.assertTrue(any(s.get("fill") == "black" for s in t["shapes"][1:]), t["id"])
        # Fullbore: the 2 is the rest of the square card, so it has shapes and no rings.
        lr = self.targets["ca-fullbore-300-yards"]
        self.assertEqual(lr["scoring"]["values"], [5, 4, 3, 2, 0])
        self.assertEqual(lr["shapes"][0]["rect"], [-600, -600, 1200, 1200])
        self.assertEqual(self.targets["dk-trekant-50m"]["scoring"]["values"], list(range(10, -1, -1)))
        self.assertEqual(self.targets["no-sprint-luft"]["ring_diameters_mm"], [22, 48.6, 75.2, 101.8, 128.4, 155])

    def test_issf_rings_match_the_rulebook(self):
        self.assertEqual(self.targets["issf-10m-air-rifle"]["ring_diameters_mm"][0], 0.5)
        self.assertEqual(self.targets["issf-10m-air-rifle"]["ring_diameters_mm"][-1], 45.5)
        self.assertEqual(self.targets["issf-25m-rapid-fire-pistol"]["ring_diameters_mm"], [100, 180, 260, 340, 420, 500])
        self.assertEqual(self.targets["issf-50m-running-target"]["ring_diameters_mm"][::9], [60, 366])
        self.assertEqual(self.targets["issf-10m-running-target"]["ring_diameters_mm"][::9], [5.5, 50.5])

    def test_names_say_who_issues_the_target(self):
        # Raven 2026-11-16: ISSF and VBS targets with almost the same name must be told apart.
        names = [t["name"] for t in self.targets.values()]
        self.assertEqual(len(set(names)), len(names))
        for target in self.targets.values():
            # VBS only for the targets of the military regulation (Raven); the SSV and local Swiss ones
            # (Morgarten, Ustertag) carry neither VBS nor ISSF.
            military = "SR 512.311" in target["source"]["title"]
            self.assertEqual(target["name"].startswith("ISSF "), target["group"] == "ISSF", target["name"])
            self.assertEqual(target["name"].startswith("VBS "), military, target["name"])

    def test_ssv_and_sius_targets(self):
        # SIUS STYX SUI-50m-Targets-Package: P and B pistol targets, Kleinkaliber A for the rifle.
        self.assertEqual(self.targets["ch-50m-p4"]["ring_diameters_mm"], [200, 300, 600, 1000])
        self.assertEqual(self.targets["ch-50m-p100"]["scoring"], {"min": 0, "max": 100})
        self.assertEqual(self.targets["ch-50m-pistol-b100"]["scoring"], {"min": 0, "max": 100})
        # Kleinkaliber A: the ISSF 50 m face (SSV TRG Art. 26); A5 joins two rings into one.
        self.assertEqual(self.targets["ch-50m-kka5"]["ring_diameters_mm"], [26.4, 58.4, 90.4, 122.4, 154.4])
        self.assertEqual(self.targets["ch-50m-kka10"]["ring_diameters_mm"], self.targets["issf-50m-rifle"]["ring_diameters_mm"])
        self.assertEqual(self.targets["ch-50m-kka20"]["scoring"], {"values": list(range(20, -1, -1))})
        self.assertEqual(len(self.targets["ch-50m-kka20"]["ring_diameters_mm"]), 20)
        self.assertEqual(self.targets["ch-50m-kka100"]["scoring"], {"min": 0, "max": 100})
        self.assertEqual(self.targets["ch-10m-air-rifle-100"]["scoring"], {"min": 0, "max": 100})
        self.assertEqual(self.targets["ch-50m-morgarten-f5"]["scoring"], {"values": [5, 4, 3, 2, 1, 0]})
        self.assertEqual(self.targets["ch-25m-ustertag"]["scoring"], {"values": [5, 4, 3, 0]})
        self.assertEqual(self.targets["ch-300m-ustertag"]["scoring"], {"values": [5, 4, 3, 2, 0]})

    def test_ustertag_25m_shield_shows_the_uster_arms(self):
        # Raven 2026-11-22: the shield had no arms. Right half: five equal bars, the 1st, 3rd and 5th red.
        shapes = self.targets["ch-25m-ustertag"]["shapes"]
        shield = shapes[2]["polygon"]
        top, bottom = min(y for _, y in shield), max(y for _, y in shield)
        bar = (bottom - top) / 5
        red = [s for s in shapes[3:] if s.get("fill") == "red"]
        self.assertEqual(len(red), 3)
        for k, shape in zip((0, 2, 4), red):
            if "rect" in shape:
                x, y, w, h = shape["rect"]
                points = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
            else:
                points = shape["polygon"]
            ys = [y for _, y in points]
            self.assertAlmostEqual(min(ys), top + k * bar, places=0)
            self.assertAlmostEqual(max(ys), top + (k + 1) * bar, places=0)
            for x, y in points:
                self.assertGreaterEqual(x, 0, "right half only")
                self.assertTrue(inside(x, y, shield), (x, y))

    def test_scorings_of_the_swiss_and_issf_targets(self):
        self.assertEqual(self.targets["ch-300m-a5"]["scoring"], {"values": [5, 4, 3, 2, 1, 0]})
        self.assertEqual(self.targets["ch-300m-a10"]["scoring"], {"values": TEN_TO_ZERO})
        self.assertEqual(self.targets["issf-25m-rapid-fire-pistol"]["scoring"], {"values": [10, 9, 8, 7, 6, 5, 0]})
        self.assertEqual(self.targets["ch-300m-b4"]["scoring"], {"values": [4, 3, 2, 1, 0]})
        self.assertEqual(self.targets["ch-25m-ordonnanz-rapid-fire"]["scoring"], {"values": [10, 9, 8, 7, 6, 0]})
        self.assertEqual(self.targets["ch-300m-a100"]["scoring"], {"min": 0, "max": 100})
        self.assertEqual(self.targets["issf-10m-air-rifle"]["scoring"], {"min": 0, "max": 10.9})


class CheckTests(unittest.TestCase):
    def test_good_targets_have_no_problems(self):
        self.assertEqual(targets.problems(target()), [])
        self.assertEqual(targets.problems(target(scoring={"min": 0, "max": 10.9})), [])

    def test_scoring_is_a_range_or_a_list(self):
        self.assertIn("either", targets.problems(target(scoring={}))[0])
        # The app reads numbers only: named zones would make the whole template list fail to load.
        zones = target(drop=("ring_diameters_mm", "black_mm"), scoring={"values": ["A", "C", "D", "M"]})
        self.assertTrue(any("must all be numbers" in p for p in targets.problems(zones)))
        self.assertIn("either", targets.problems(target(scoring={"min": 0, "max": 10, "values": [1, 0]}))[0])
        self.assertIn("min < max", targets.problems(target(scoring={"max": 10}))[0])
        self.assertIn("min < max", targets.problems(target(scoring={"min": 10, "max": 10}))[0])
        self.assertIn("best to worst", targets.problems(target(scoring={"values": [0, 7, 8, 9, 10]}))[0])
        self.assertIn("must all be numbers", targets.problems(target(scoring={"values": [10, "A", 0]}))[0])
        self.assertIn("two different", targets.problems(target(scoring={"values": [5, 5]}))[0])

    def test_rings_must_fit_the_scores_and_each_other(self):
        self.assertIn("grow", targets.problems(target(ring_diameters_mm=[10, 30, 20, 40]))[0])
        self.assertIn("3 rings for 4 scores", targets.problems(target(ring_diameters_mm=[10, 20, 40]))[0])
        self.assertIn("inner ten", targets.problems(target(inner_ten_mm=12))[0])
        self.assertIn("black", targets.problems(target(black_mm=50))[0])
        self.assertIn("need ring diameters", targets.problems(target(drop=("ring_diameters_mm",)))[0])

    def test_finds_missing_source_and_wrong_file_name(self):
        self.assertIn("source", targets.problems(target(source={"title": "x"}))[0])
        self.assertIn("id", targets.problems(target(id="other"))[0])

    def test_app_json_keeps_the_scoring_and_leaves_out_what_is_not_there(self):
        out = targets.app_json([target(inner_ten_mm=5, source={"title": "Rules", "url": "u", "rule": "1.2"})])[0]
        self.assertEqual(out["scoring"], {"values": [10, 9, 8, 7, 0]})
        self.assertEqual(out["ringDiameters"], [10, 20, 30, 40])
        self.assertEqual(out["innerTen"], 5)
        self.assertEqual(out["source"], "Rules, 1.2")
        self.assertNotIn("_file", out)
        bare = targets.app_json([target(drop=("ring_diameters_mm", "black_mm"), scoring={"min": 0, "max": 100})])[0]
        self.assertEqual(bare["scoring"], {"min": 0, "max": 100})
        self.assertNotIn("ringDiameters", bare)
        self.assertNotIn("black", bare)



class FaceTests(unittest.TestCase):
    CARD = {"rect": [-50, -50, 100, 100], "fill": "white"}

    def test_shapes_are_checked(self):
        self.assertEqual(targets.problems(target(shapes=[self.CARD, {"ellipse": [0, 0, 10, 20], "line": "black"}])), [])
        self.assertIn("one of rect", targets.problems(target(shapes=[self.CARD, {"fill": "black"}]))[0])
        self.assertIn("size above 0", targets.problems(target(shapes=[self.CARD, {"rect": [0, 0, 0, 5], "fill": "red"}]))[0])
        self.assertIn("three", targets.problems(target(shapes=[self.CARD, {"polygon": [[0, 0], [1, 1]], "fill": "red"}]))[0])
        self.assertIn("fill or a line", targets.problems(target(shapes=[self.CARD, {"rect": [0, 0, 1, 1]}]))[0])
        self.assertIn("not one of", targets.problems(target(shapes=[self.CARD, {"rect": [0, 0, 1, 1], "fill": "pink"}]))[0])
        self.assertIn("rects only", targets.problems(target(shapes=[self.CARD, {"ellipse": [0, 0, 1, 1], "fill": "red", "radius": 1}]))[0])
        self.assertIn("the card", targets.problems(target(shapes=[{"ellipse": [0, 0, 1, 1], "fill": "red"}]))[0])
        self.assertIn("itself", targets.problems(target(face="t"))[0])

    def test_face_references_must_exist_and_not_go_round(self):
        a, b = target(id="a", _file="a.toml", face="b"), target(id="b", _file="b.toml", face="a")
        self.assertIn("circle", targets.face_reference_problems([a, b])[0])
        self.assertIn("no target", targets.face_reference_problems([target(face="x")])[0])
        bare = target(drop=("ring_diameters_mm", "black_mm"))
        self.assertIn("nothing to draw", targets.face_reference_problems([bare])[0])
        self.assertEqual(targets.face_reference_problems([target()]), [])

    def test_face_draws_the_named_target_first(self):
        base = target(id="base", shapes=[self.CARD])
        child = target(id="child", drop=("ring_diameters_mm", "black_mm"), face="base",
                       shapes=[{"ellipse": [0, 0, 5, 5], "line": "black"}])
        by_id = {"base": base, "child": child}
        self.assertEqual(targets.face(child, by_id),
                         {"shapes": [self.CARD, {"ellipse": [0, 0, 5, 5], "line": "black"}], "rings": [10, 20, 30, 40], "black": 30})
        self.assertIsNone(targets.face(target(drop=("ring_diameters_mm", "black_mm")), {}))
        out = targets.app_json([base, child])
        self.assertEqual(out[1]["face"]["rings"], [10, 20, 30, 40])
        # The hundred rating's own data keeps no rings: they are only drawn.
        self.assertNotIn("ringDiameters", out[1])

    def test_every_target_in_the_repo_is_drawn(self):
        all_targets = targets.load()
        self.assertEqual(targets.face_reference_problems(all_targets), [])
        by_id = {t["id"]: t for t in all_targets}
        for t in all_targets:
            self.assertIsNotNone(targets.face(t, by_id), t["id"])
        self.assertEqual(targets.face(by_id["ch-300m-a100"], by_id), targets.face(by_id["ch-300m-a10"], by_id))
        def size(polygon):
            xs, ys = [p[0] for p in polygon], [p[1] for p in polygon]
            return max(xs) - min(xs), max(ys) - min(ys)

        # The B figures are 45 x 50 cm: SIUS's rifle B4 one, and the pistol one (Sui PB5 sweep) that sits higher.
        rifle = by_id["ch-300m-b4"]["shapes"][1]["polygon"]
        pistol = by_id["ch-50m-pistol-b5"]["shapes"][1]["polygon"]
        self.assertEqual(size(rifle), (450, 500))
        self.assertEqual(size(pistol), (450, 499))
        self.assertEqual(by_id["ch-50m-pistol-b10"]["shapes"][1]["polygon"], pistol)
        self.assertLess(min(p[1] for p in pistol), min(p[1] for p in rifle), "the pistol figure's head is higher")
        # The rifle B10 draws the B4 face; the pistol B10 its own, with the pistol figure.
        self.assertEqual(targets.face(by_id["ch-300m-b10"], by_id)["shapes"][1]["polygon"], rifle)
        self.assertEqual(targets.face(by_id["ch-50m-pistol-b10"], by_id)["shapes"][1]["polygon"], pistol)
        # SIUS's Morgarten figure: 46 x 101 cm.
        self.assertEqual(size(by_id["ch-50m-morgarten-f5"]["shapes"][1]["polygon"]), (460, 1010))

    def test_targets_from_siusdata(self):
        by_id = {t["id"]: t for t in targets.load()}
        a6 = by_id["ch-300m-a6"]
        self.assertEqual(a6["scoring"]["values"], [6, 5, 4, 3, 2, 1, 0])
        self.assertEqual(a6["shapes"][0]["rect"], [-600, -600, 1200, 1200], "the 1 is the rest of the 120 cm card")
        self.assertEqual(by_id["ch-300m-f5"]["scoring"]["values"], [5, 4, 3, 0], "SIUS draws only the 5, 4 and the figure")
        zimmer = by_id["ch-15m-zimmerstutzen"]
        self.assertEqual(zimmer["distances_m"], [15])
        rings = zimmer["ring_diameters_mm"]
        self.assertEqual(len(rings), 10)
        self.assertTrue(all(abs(b - a - 9) < 1e-9 for a, b in zip(rings, rings[1:])), "rings 4.5 mm wide")
        for t in (a6, by_id["ch-300m-f5"], zimmer):
            self.assertEqual(targets.problems(t), [], t["id"])


if __name__ == "__main__":
    unittest.main()
