"""Tests for the calibre wall poster: python3 -m unittest discover -s tools -p 'test_*.py'"""
import os, re, sys, unittest

sys.path.insert(0, os.path.dirname(__file__))
import poster  # noqa: E402
from cartridges import CATALOGUE  # noqa: E402

ALL = [s for _, items in CATALOGUE for s in items]


class MergeIdenticalTests(unittest.TestCase):
    def test_identical_measurements_share_one_drawing(self):
        groups = [g["names"] for g in poster.merge_identical(ALL) if len(g["names"]) > 1]
        self.assertEqual(sorted(map(sorted, groups)),
                         sorted([sorted([".308 Winchester", "7.62x51 mm NATO"]),
                                 sorted([".223 Remington", "5.56x45 mm NATO", "5.6 mm GP 90 (Swiss)"])]))

    def test_no_cartridge_is_lost_or_doubled(self):
        names = [n for g in poster.merge_identical(ALL) for n in g["names"]]
        self.assertEqual(sorted(names), sorted(s["name"] for s in ALL))

    def test_similar_but_different_cartridges_stay_apart(self):
        groups = {n: i for i, g in enumerate(poster.merge_identical(ALL)) for n in g["names"]}
        self.assertNotEqual(groups["7.5x55 mm Swiss (GP 11)"], groups["7.5x53.5 mm Swiss (GP 1890)"])
        self.assertNotEqual(groups["9x19 mm"], groups["9x21 mm IMI"])

    def test_combined_label_lists_every_name(self):
        poster.LANG = "de"
        lines, extra = poster.label_lines(["7.62x51 mm NATO", ".308 Winchester"])
        self.assertEqual(lines, ["7.62x51 mm NATO", ".308 Winchester"])
        self.assertEqual(extra, ["gleiche Masse"])
        lines, _ = poster.label_lines([".223 Remington", "5.6 mm GP 90 (Swiss)"])
        self.assertEqual(lines[1], "5.6 mm GP 90", "parenthetical part is dropped in a combined label")


class BuildTests(unittest.TestCase):
    VERSIONS = [("A1", 1.0, "de"), ("A1", 1.0, "en"), ("A3", 0.5, "de"), ("A3", 0.5, "en")]

    def test_every_version_builds_and_fits_the_page(self):
        for size, k, lang in self.VERSIONS:
            with self.subTest(size=size, lang=lang):
                svg, (w, h), over, rows = poster.build(size, k, lang)
                self.assertTrue(svg.startswith("<svg"))
                self.assertIn(f'width="{w}mm" height="{h}mm"', svg)
                self.assertEqual((w, h), poster.SIZES[size])
                self.assertLessEqual(over, 2.0, "content runs into the footer")
                self.assertEqual(rows, 6)

    def test_every_cartridge_is_named_once(self):
        svg = poster.build("A1", 1.0, "de")[0]
        drawings = svg.count("<g transform=")
        self.assertEqual(drawings, len(poster.merge_identical(ALL)))
        self.assertEqual(svg.count("gleiche Masse"), 2)
        n = re.search(r"(\d+) Patronen von", svg)
        self.assertEqual(int(n.group(1)), len(ALL), "the subtitle counts every cartridge, merged or not")

    def test_english_labels(self):
        svg = poster.build("A3", 0.5, "en")[0]
        self.assertIn("Calibre Comparison", svg)
        self.assertIn("identical dimensions", svg)
        self.assertIn("Scale 1:2", svg)
        self.assertNotIn("Kaliber im Vergleich", svg)

    def test_licence_credit(self):
        for lang in ("de", "en"):
            self.assertIn("© 2026 Simon Giotta", poster.build("A1", 1.0, lang)[0])


if __name__ == "__main__":
    unittest.main()
