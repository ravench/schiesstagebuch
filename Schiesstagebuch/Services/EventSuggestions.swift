import Foundation

/// Autocomplete for the event ("Anlass") field: names from earlier events that match what is being typed.
///
/// Matching ignores case and accents ("feld" finds "Feldschiessen", "Ehrengaben" finds "Éhrengaben").
/// Names that start with the typed text come first, then names with a word that starts with it,
/// then names that merely contain it. Within each group the more often used and then the more
/// recently used name wins. Spellings that differ only in case count as one name; the most
/// recently used spelling is shown.
enum EventSuggestions {
    static let defaultLimit = 4

    private static let folding: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func suggestions(for query: String, in history: [(event: String, date: Date)],
                            limit: Int = defaultLimit) -> [String] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty, limit > 0 else { return [] }

        struct Candidate { var name: String; var count = 0; var last = Date.distantPast }
        var byKey: [String: Candidate] = [:]
        for (raw, date) in history {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = fold(name)
            var c = byKey[key] ?? Candidate(name: name)
            c.count += 1
            if date > c.last { c.last = date; c.name = name }
            byKey[key] = c
        }

        let ranked: [(tier: Int, candidate: Candidate)] = byKey.compactMap { key, c in
            // Typing the full name needs no suggestion.
            guard key != needle, let tier = tier(of: needle, in: key) else { return nil }
            return (tier, c)
        }
        return ranked.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.candidate.count != b.candidate.count { return a.candidate.count > b.candidate.count }
            if a.candidate.last != b.candidate.last { return a.candidate.last > b.candidate.last }
            return a.candidate.name.localizedStandardCompare(b.candidate.name) == .orderedAscending
        }
        .prefix(limit).map(\.candidate.name)
    }

    /// Each event counts once, however many Stiche it holds.
    static func suggestions(for query: String, in events: [ShootingEvent], limit: Int = defaultLimit) -> [String] {
        suggestions(for: query, in: events.map { (event: $0.name, date: $0.date) }, limit: limit)
    }

    /// 0 = name starts with the query, 1 = a word starts with it, 2 = contains it, nil = no match.
    private static func tier(of needle: String, in key: String) -> Int? {
        if key.hasPrefix(needle) { return 0 }
        guard let first = key.range(of: needle) else { return nil }
        var range: Range<String.Index>? = first
        while let r = range {
            if let before = key[..<r.lowerBound].last, !before.isLetter, !before.isNumber { return 1 }
            range = key.range(of: needle, range: key.index(after: r.lowerBound)..<key.endIndex)
        }
        return 2
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: folding, locale: nil)
    }
}
