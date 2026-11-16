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


class RepoTargetTests(unittest.TestCase):
    def setUp(self):
        self.targets = {t["id"]: t for t in targets.load()}

    def test_every_target_in_the_repo_is_fine(self):
        self.assertGreaterEqual(len(self.targets), 16)
        self.assertEqual({t["group"] for t in self.targets.values()}, {"Schweiz", "ISSF"})
        for t in self.targets.values():
            self.assertEqual(targets.problems(t), [], t["_file"])

    def test_issf_rings_match_the_rulebook(self):
        self.assertEqual(self.targets["issf-10m-air-rifle"]["ring_diameters_mm"][0], 0.5)
        self.assertEqual(self.targets["issf-10m-air-rifle"]["ring_diameters_mm"][-1], 45.5)
        self.assertEqual(self.targets["issf-25m-rapid-fire-pistol"]["ring_diameters_mm"], [100, 180, 260, 340, 420, 500])

    def test_sius_50m_targets(self):
        # SIUS STYX SUI-50m-Targets-Package: P and B pistol targets, Kleinkaliber A for the rifle.
        self.assertEqual(self.targets["ch-50m-p4"]["ring_diameters_mm"], [200, 300, 600, 1000])
        self.assertEqual(self.targets["ch-50m-p100"]["scoring"], {"min": 0, "max": 100})
        self.assertEqual(self.targets["ch-50m-pistol-b100"]["scoring"], {"min": 0, "max": 100})
        self.assertEqual(self.targets["ch-50m-kka5"]["ring_diameters_mm"], [32, 64, 96, 128, 160])
        self.assertEqual(self.targets["ch-50m-kka20"]["scoring"], {"values": list(range(20, -1, -1))})
        self.assertEqual(len(self.targets["ch-50m-kka20"]["ring_diameters_mm"]), 20)
        self.assertEqual(self.targets["ch-50m-kka100"]["scoring"], {"min": 0, "max": 100})

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
        zones = target(drop=("ring_diameters_mm", "black_mm"), scoring={"values": ["A", "C", "D", "M"]})
        self.assertEqual(targets.problems(zones), [])

    def test_scoring_is_a_range_or_a_list(self):
        self.assertIn("either", targets.problems(target(scoring={}))[0])
        self.assertIn("either", targets.problems(target(scoring={"min": 0, "max": 10, "values": [1, 0]}))[0])
        self.assertIn("min < max", targets.problems(target(scoring={"max": 10}))[0])
        self.assertIn("min < max", targets.problems(target(scoring={"min": 10, "max": 10}))[0])
        self.assertIn("best to worst", targets.problems(target(scoring={"values": [0, 7, 8, 9, 10]}))[0])
        self.assertIn("all numbers or all names", targets.problems(target(scoring={"values": [10, "A", 0]}))[0])
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


if __name__ == "__main__":
    unittest.main()
