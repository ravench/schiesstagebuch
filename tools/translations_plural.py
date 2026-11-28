"""Singular forms of the counted texts: key (the plural, as in translations.T) → (de, en, fr, it).

localize.py writes them as plural variations, so one entry reads «1 Eintrag», not «1 Einträge».
Only texts with a single number; a text with two numbers is worded so that it needs no plural.
"""
ONE = {
    "%lld Einträge": ("%lld Eintrag", "%lld entry", "%lld entrée", "%lld voce"),
    "%lld Einträge importieren": ("%lld Eintrag importieren", "Import %lld entry", "Importer %lld entrée", "Importa %lld voce"),
    "%lld Einträge importiert": ("%lld Eintrag importiert", "%lld entry imported", "%lld entrée importée", "%lld voce importata"),
    "%lld Einträge wiederhergestellt.": ("%lld Eintrag wiederhergestellt.", "%lld entry restored.", "%lld entrée restaurée.",
                                         "%lld voce ripristinata."),
    "%lld Stiche": ("%lld Stich", "%lld match", "%lld cible", "%lld programma"),
    "%lld Schuss": ("%lld Schuss", "%lld shot", "%lld coup", "%lld colpo"),
}
