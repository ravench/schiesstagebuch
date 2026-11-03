"""Checks spelling and capitalisation consistency of the translated UI texts.

    python3 -m unittest discover -s tools -p 'test_text_style.py'
"""
import re
import unittest

from translations import T

EN, FR, IT = 0, 1, 2
SETTINGS = {EN: "Settings", FR: "Réglages", IT: "Impostazioni"}
# “x” in English, « x » in French, «x» in Italian.
QUOTED = re.compile(r"“([^”]+)”|«\s?([^»]+?)\s?»")
# English is British, and the app says "firearm", never "weapon".
NOT_BRITISH = re.compile(r"\b(calibers?|colors?|programs?|licenses?|catalogs?|centers?|"
                         r"weapons?|ammo|recogniz\w*|organiz\w*)\b", re.I)
# Words that may be capitalised mid-sentence: names, products and screens they refer to.
PROPER = {"Albisgüetli", "Edit", "Elmiger", "Equipment", "Files", "Firearms", "Geco", "Log", "Maps",
          "Menu", "My", "On", "Photos", "Settings", "ShootCounter-Export", "Swiss"}


def english():
    return [v[EN] for v in T.values()]


class TextStyleTests(unittest.TestCase):
    def test_wording_switch_quotes_the_tab_titles_as_shown(self):
        # The screenshot bug: “Equipment” instead of “firearms”, but the tab says “Firearms”.
        text = T["«Sportgeräte» statt «Waffen»"]
        for lang in (EN, FR, IT):
            quoted = [a or b for a, b in QUOTED.findall(text[lang])]
            self.assertEqual(quoted, [T["Sportgeräte"][lang], T["Waffen"][lang]], text[lang])

    def test_english_uses_british_spelling(self):
        bad = [t for t in english() if NOT_BRITISH.search(t)]
        self.assertEqual(bad, [])

    def test_english_uses_sentence_case(self):
        bad = []
        for text in english():
            for part in re.split(r"[.:?!/(›→·;]\s*|\s[–-]\s", text):
                words = re.findall(r"[A-Za-zÀ-ÿ][\w’'-]*", part)
                bad += [(w, text) for w in words[1:]
                        if w[0].isupper() and not w.isupper() and not any(c.isdigit() for c in w)
                        and w not in PROPER]
        self.assertEqual(bad, [])

    def test_settings_paths_name_real_screens(self):
        for lang, settings in SETTINGS.items():
            titles = {v[lang] for v in T.values()}
            for text in (v[lang] for v in T.values()):
                for rest in re.findall(re.escape(settings) + r" [›→] ([^.,)]+)", text):
                    self.assertIn(rest.strip(), titles, text)
                self.assertNotIn(settings + " →", text, "use › like the other paths")

    def test_sentence_case_check_catches_title_case(self):
        words = re.findall(r"[A-Za-zÀ-ÿ][\w’'-]*", "App Icon")
        self.assertTrue(any(w[0].isupper() and w not in PROPER for w in words[1:]))


if __name__ == "__main__":
    unittest.main()
