"""Unit tests for tools/app_icon.py.

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import unittest

import app_icon


class AppIconBackgroundTests(unittest.TestCase):
    def test_every_appearance(self):
        self.assertEqual(set(app_icon.PALETTES), {"", "-Dark", "-Tinted"})

    def test_light_is_beige_dark_is_navy_tinted_is_black(self):
        expected = {"": app_icon.BEIGE, "-Dark": app_icon.NAVY, "-Tinted": app_icon.BLACK}
        for suffix, bg in expected.items():
            p = app_icon.PALETTES[suffix]
            self.assertEqual(p["bg_open"], bg, suffix)
            self.assertEqual(p["bg_hard"], bg, suffix)

    def test_svg_uses_the_background(self):
        for draw in (app_icon.open_journal, app_icon.hardcover):
            for p in app_icon.PALETTES.values():
                svg = draw(p)
                self.assertTrue(svg.startswith("<svg") and svg.endswith("</svg>"))
                top, bottom = p["bg_open"] if draw is app_icon.open_journal else p["bg_hard"]
                self.assertIn(f'stop-color="{top}"', svg)
                self.assertIn(f'stop-color="{bottom}"', svg)


if __name__ == "__main__":
    unittest.main()
