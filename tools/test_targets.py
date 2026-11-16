import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import targets  # noqa: E402


def face(**changes):
    target = {
        "_file": "t.toml", "id": "t", "name": "Test", "short_name": "T", "distances_m": [10],
        "top_value": 10, "ring_diameters_mm": [10, 20, 30, 40], "black_mm": 30, "black_from_ring": 8,
        "source": {"title": "Rules", "url": "https://example.org"},
    }
    target.update(changes)
    return target


class TargetDataTests(unittest.TestCase):
    def test_every_target_in_the_repo_is_fine(self):
        loaded = targets.load()
        self.assertGreaterEqual(len(loaded), 6)
        for target in loaded:
            self.assertEqual(targets.problems(target), [], target["_file"])

    def test_issf_air_rifle_matches_the_rulebook(self):
        rifle = {t["id"]: t for t in targets.load()}["issf-10m-air-rifle"]
        self.assertEqual(rifle["ring_diameters_mm"][0], 0.5)
        self.assertEqual(rifle["ring_diameters_mm"][-1], 45.5)
        self.assertNotIn("inner_ten_mm", rifle)

    def test_rapid_fire_has_only_rings_ten_to_five(self):
        rapid = {t["id"]: t for t in targets.load()}["issf-25m-rapid-fire-pistol"]
        self.assertEqual(rapid["ring_diameters_mm"], [100, 180, 260, 340, 420, 500])
        self.assertEqual(targets.shot_values(rapid), [10, 9, 8, 7, 6, 5, 0])

    def test_a5_takes_one_digit_shots_and_the_rifles_decimals(self):
        faces = {t["id"]: t for t in targets.load()}
        self.assertEqual(targets.shot_values(faces["ch-300m-a5"]), [5, 4, 3, 2, 1, 0])
        self.assertEqual(targets.shot_values(faces["ch-300m-a10"]), list(range(10, -1, -1)))
        self.assertEqual(len(targets.shot_values(faces["ch-300m-a100"])), 101)
        self.assertTrue(faces["issf-10m-air-rifle"].get("decimal"))
        self.assertFalse(faces["ch-300m-a10"].get("decimal", False))

    def test_a_good_face_has_no_problems(self):
        self.assertEqual(targets.problems(face()), [])

    def test_finds_wrong_ring_count_order_and_black(self):
        self.assertIn("centre scores only 3", targets.problems(face(top_value=3, black_from_ring=2))[0])
        self.assertIn("grow", targets.problems(face(ring_diameters_mm=[10, 30, 20, 40], black_mm=20))[0])
        self.assertIn("does not end in ring 8", targets.problems(face(black_mm=31))[0])
        self.assertEqual(targets.problems(face(black_mm=25)), [])
        self.assertIn("does not have", targets.problems(face(black_from_ring=5))[0])

    def test_finds_inner_ten_outside_the_ten_and_missing_source(self):
        self.assertIn("inner ten", targets.problems(face(inner_ten_mm=12))[0])
        self.assertIn("source", targets.problems(face(source={"title": "x"}))[0])
        self.assertIn("id", targets.problems(face(id="other"))[0])

    def test_app_json_leaves_out_comments_and_keeps_optional_fields_optional(self):
        out = targets.app_json([face(inner_ten_mm=5, source={"title": "Rules", "url": "u", "rule": "1.2"})])[0]
        self.assertEqual(out["ringDiameters"], [10, 20, 30, 40])
        self.assertEqual((out["topValue"], out["lowestRing"], out["decimal"]), (10, 7, False))
        self.assertEqual(out["innerTen"], 5)
        self.assertEqual(out["source"], "Rules, 1.2")
        self.assertNotIn("_file", out)
        bare = targets.app_json([{k: v for k, v in face().items() if k not in ("black_mm", "black_from_ring")}])[0]
        self.assertNotIn("black", bare)
        self.assertNotIn("innerTen", bare)


if __name__ == "__main__":
    unittest.main()
