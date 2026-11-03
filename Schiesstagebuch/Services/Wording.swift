import SwiftUI

/// Lets the user call their firearms «Sportgeräte» instead of «Waffen» (Settings → Bezeichnung).
///
/// Views read `@Environment(\.term)` and pass German keys through it, e.g. `term("Waffe hinzufügen").loc`.
/// With the switch on, a key from `sportsEquipment` is swapped for its Sportgerät variant before the
/// usual lookup in Localizable.xcstrings, so en/fr/it follow too. Stored data is never changed.
enum Wording {
    static let sportsEquipmentKey = "wording.sportsEquipment"

    /// German key → Sportgerät variant. tools/extract_strings.py reads both sides, so every
    /// variant needs an entry in tools/translations_wording.py.
    static let sportsEquipment: [String: String] = [
        "Waffe": "Sportgerät",
        "Einträge zählen für den Lauf ihres Kalibers, der an diesem Tag montiert war. Pflege-Erinnerungen zählen alle Schüsse der Waffe.": "Einträge zählen für den Lauf ihres Kalibers, der an diesem Tag montiert war. Pflege-Erinnerungen zählen alle Schüsse des Sportgeräts.",
        "Für ein weiteres Programm am selben Anlass, auch mit einer anderen Waffe.": "Für ein weiteres Programm am selben Anlass, auch mit einem anderen Sportgerät.",
        "Waffen": "Sportgeräte",
        "Alle Waffen": "Alle Sportgeräte",
        "Deine Waffen": "Deine Sportgeräte",
        "Keine Waffen": "Keine Sportgeräte",
        "Neue Waffe": "Neues Sportgerät",
        "Neue Waffen": "Neue Sportgeräte",
        "Pro Waffe": "Pro Sportgerät",
        "Waffe bearbeiten": "Sportgerät bearbeiten",
        "Waffe hinzufügen": "Sportgerät hinzufügen",
        "Waffe löschen": "Sportgerät löschen",
        "Waffe löschen?": "Sportgerät löschen?",
        "Anlass, Anlage, Waffe …": "Anlass, Anlage, Sportgerät …",
        "Lege deine Waffen mit ihren Kalibern an.": "Lege deine Sportgeräte mit ihren Kalibern an.",
        "Seriennummer in der Waffenauswahl": "Seriennummer in der Sportgeräteauswahl",
        "Ab wann Erinnerungen nach Tagen zählen. Pro Waffe kannst du das ändern.":
            "Ab wann Erinnerungen nach Tagen zählen. Pro Sportgerät kannst du das ändern.",
        "Archivierte Waffen erscheinen nicht mehr bei neuen Einträgen, bleiben aber in Tagebuch und Statistik.":
            "Archivierte Sportgeräte erscheinen nicht mehr bei neuen Einträgen, bleiben aber in Tagebuch und Statistik.",
        "Einträge bleiben erhalten, verlieren aber die Waffe. Archivieren behält alles.":
            "Einträge bleiben erhalten, verlieren aber das Sportgerät. Archivieren behält alles.",
        "Das Verkaufsdatum kann nicht vor dem Kaufdatum liegen. Verkaufte Waffen werden archiviert.":
            "Das Verkaufsdatum kann nicht vor dem Kaufdatum liegen. Verkaufte Sportgeräte werden archiviert.",
        "Optional. Neue Einträge übernehmen die Werte des letzten Eintrags mit dieser Waffe.":
            "Optional. Neue Einträge übernehmen die Werte des letzten Eintrags mit diesem Sportgerät.",
        "Optional. Neue Einträge übernehmen die Werte des letzten Eintrags mit dieser Waffe. Deine Filter wählst du unter Einstellungen → Filter.":
            "Optional. Neue Einträge übernehmen die Werte des letzten Eintrags mit diesem Sportgerät. Deine Filter wählst du unter Einstellungen → Filter.",
        "Der Export enthält keine Kaliber. Jede Munition wird einem Kaliber zugeordnet; daraus ergeben sich die Kaliber deiner Waffen.":
            "Der Export enthält keine Kaliber. Jede Munition wird einem Kaliber zugeordnet; daraus ergeben sich die Kaliber deiner Sportgeräte.",
        "Prüfe unter Waffen die Kategorie und die Kaliber der importierten Waffen.":
            "Prüfe unter Sportgeräte die Kategorie und die Kaliber der importierten Sportgeräte."
    ]
}

/// The wording in effect; call it with a German key to get the key to localize.
struct Terms: Equatable {
    var sportsEquipment = false

    func callAsFunction(_ key: String) -> String {
        guard sportsEquipment else { return key }
        return Wording.sportsEquipment[key] ?? key
    }
}

private struct TermsKey: EnvironmentKey {
    static let defaultValue = Terms()
}

extension EnvironmentValues {
    var term: Terms {
        get { self[TermsKey.self] }
        set { self[TermsKey.self] = newValue }
    }
}
