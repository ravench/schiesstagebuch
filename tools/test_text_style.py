"""Checks spelling and capitalisation consistency of the translated UI texts.

    python3 -m unittest discover -s tools -p 'test_text_style.py'
"""
import os
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
# Schusszähler-Schiesstagebuch is someone else's app and still maintained: name it, never "the old app".
OLD_APP = re.compile(r"\b(alten?|old|ancienne|vecchia) app\b", re.I)
# German is Swiss Standard German (CONTRIBUTING.md): ss, «», decimal point, Swiss words.
SWISS = [(re.compile(r"ß"), "ss"), (re.compile(r"[„“”]"), "«»"), (re.compile(r"\d,\d"), "decimal point, 10.9")]
GERMANISMS = {r"Webseiten?": "Website", r"oftmals": "oft", r"Los geht['’]s": "Starten", r"Wartung\w*": "Pflege or Service",
              r"Displays?": "Bildschirm"}
README = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "README.md")
# Words that may be capitalised mid-sentence: names, products and screens they refer to.
PROPER = {"Albisgüetli", "Apple", "Edit", "Elmiger", "Equipment", "Files", "Firearms", "Geco", "Grünig", "Kingdom", "Log", "Maps",
          "Menu", "My", "On", "Photos", "Ranges", "Settings", "ShootCounter-Export", "Swiss", "Weather"}


# French says «tu», like the German «du»: no «vous», «votre», «vos», and no verb in the vous form.
FORMAL_FRENCH = re.compile(r"\b(vous|votre|vos|veuillez)\b|\b(?!assez\b|chez\b)\w{4,}ez\b", re.I)


def german():
    """Every German text: the keys, and the German spelling where it differs from the key."""
    return list(T) + [v[3] for v in T.values() if len(v) > 3]


def swiss_problems(texts):
    bad = [(text, hint) for text in texts for pattern, hint in SWISS if pattern.search(text)]
    return bad + [(text, swiss) for text in texts for word, swiss in GERMANISMS.items()
                  if re.search(rf"(?<!\w){word}(?!\w)", text, re.I)]


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

    def test_french_addresses_the_user_informally(self):
        # Ten texts said «vous» among 37 that said «tu»; the Sportgerät switch even flipped the form.
        bad = [v[FR] for v in T.values() if FORMAL_FRENCH.search(v[FR])]
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

    def test_import_texts_do_not_call_schusszaehler_the_old_app(self):
        texts = [k for k in T] + [v for vs in T.values() for v in vs]
        self.assertEqual([t for t in texts if OLD_APP.search(t)], [])
        with open(README, encoding="utf-8") as f:
            readme = f.read()
        self.assertIsNone(OLD_APP.search(readme))
        self.assertIn("«Schusszähler-Schiesstagebuch» by carusoNET", readme)

    def test_old_app_check_catches_all_languages(self):
        for text in ("Die alte App kannte", "The old app had", "L'ancienne app ne", "La vecchia app non"):
            self.assertIsNotNone(OLD_APP.search(text), text)
        self.assertIsNone(OLD_APP.search("Der Export enthält keine Kaliber."))

    def test_sentence_case_check_catches_title_case(self):
        words = re.findall(r"[A-Za-zÀ-ÿ][\w’'-]*", "App Icon")
        self.assertTrue(any(w[0].isupper() and w not in PROPER for w in words[1:]))

    def test_german_is_swiss(self):
        self.assertEqual(swiss_problems(german()), [])

    def test_swiss_check_catches_german_spelling(self):
        bad = ["Größe", "„Stich“", "0 bis 10,9", "Los geht's", "Wartungsintervall", "Los geht’s"]
        found = swiss_problems(["Grösse", "10.9"] + bad)
        self.assertEqual([text for text, _ in found], bad)


if __name__ == "__main__":
    unittest.main()
