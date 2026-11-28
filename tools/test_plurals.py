"""The counted texts have a singular form in every language, and the catalogue carries it."""
import json, os, sys, unittest

sys.path.insert(0, os.path.dirname(__file__))
from translations import T
from translations_plural import ONE

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class PluralTests(unittest.TestCase):
    def test_singular_forms_belong_to_a_text_with_one_number(self):
        for key, forms in ONE.items():
            self.assertIn(key, T)
            self.assertEqual(key.count("%lld"), 1, key)
            self.assertEqual(len(forms), 4, key)
            for form in forms:
                self.assertEqual(form.count("%lld"), 1, form)

    def test_catalogue_has_both_forms(self):
        with open(os.path.join(ROOT, "Schiesstagebuch", "Resources", "Localizable.xcstrings"), encoding="utf-8") as f:
            strings = json.load(f)["strings"]
        for key, (de, en, fr, it) in ONE.items():
            for lang, one in (("de", de), ("en", en), ("fr", fr), ("it", it)):
                plural = strings[key]["localizations"][lang]["variations"]["plural"]
                self.assertEqual(plural["one"]["stringUnit"]["value"], one)
                self.assertEqual(plural["other"]["stringUnit"]["value"], key if lang == "de" else T[key][("en", "fr", "it").index(lang)])

    def test_no_counted_noun_without_a_singular(self):
        """A new «%lld Einträge» text needs its «Eintrag» too. Texts whose noun does not follow the number are listed."""
        fine = {"Foto %lld", "Passe %lld", "Schuss %lld", "~%lld m", "%lld× geschossen", "Scheiben ~%lld m höher", "Scheiben ~%lld m tiefer",
                "%lld hoch", "%lld tief", "%lld rechts", "%lld links", "%lld bei hoch", "%lld bei tief", "%lld bei rechts", "%lld bei links",
                # Only shown for two or more.
                "Datum, Schiessanlage und Anlass gelten für alle %lld Stiche.", "Gilt für alle %lld Stiche dieses Anlasses.",
                "Der Export enthält nur Verweise auf Fotos in deiner Mediathek (%lld). "
                "Sie werden gefunden, wenn die Fotos noch auf diesem Gerät oder in iCloud-Fotos sind."}
        open_ = sorted(k for k in T if k.count("%lld") == 1 and k not in ONE and k not in fine)
        self.assertEqual(open_, [])


if __name__ == "__main__":
    unittest.main()
