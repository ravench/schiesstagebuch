#!/usr/bin/env python3
"""Builds Schiesstagebuch/Resources/Localizable.xcstrings (source: German; en, fr, it).

    python3 tools/localize.py

Fails if a key used in the Swift sources has no translation, so new UI text
can't ship untranslated.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from extract_strings import keys
from translations import T
from translations_plural import ONE

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Schiesstagebuch", "Resources", "Localizable.xcstrings")
EXTRA = {"oder"}  # used inside an interpolation the extractor can't see

used = set(keys()) | EXTRA
missing = sorted(k for k in used if k not in T) + sorted(k for k in ONE if k not in T)
if missing:
    print("Missing translations:\n  " + "\n  ".join(missing))
    sys.exit(1)

strings = {}
for key in sorted(T):
    # (en, fr, it) or (en, fr, it, de) when the German text differs from the key,
    # e.g. a plural that is spelled like the singular in German but not in English.
    en, fr, it, *de = T[key]
    langs = (("en", en), ("fr", fr), ("it", it)) + tuple(("de", v) for v in de)
    unit = lambda v: {"stringUnit": {"state": "translated", "value": v}}  # noqa: E731
    strings[key] = {"extractionState": "manual", "localizations": {lang: unit(v) for lang, v in langs}}
    if key in ONE:  # «1 Eintrag», not «1 Einträge»: the text above is the form for every other number
        other = dict(langs, de=dict(langs).get("de", key))
        strings[key]["localizations"] = {
            lang: {"variations": {"plural": {"one": unit(one), "other": unit(other[lang])}}}
            for lang, one in zip(("de", "en", "fr", "it"), ONE[key])}
json.dump({"sourceLanguage": "de", "strings": strings, "version": "1.0"},
          open(OUT, "w"), ensure_ascii=False, indent=2, sort_keys=True)
unused = sorted(k for k in T if k not in used)
print(f"{len(strings)} keys written" + (f"; unused: {unused}" if unused else ""))
