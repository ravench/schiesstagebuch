import Foundation
import CoreLocation

/// Search for the range picker and the statistics list.
enum RangeSearch {
    /// True when every word of `query` is found in the range's name, place or address,
    /// or names one of its distances ("300", "300m", "300 m"). Case and accent insensitive.
    static func matches(_ range: ShootingRange, _ query: String) -> Bool {
        words(query).allSatisfy { matches(range, word: $0) }
    }

    /// The words of a query, with a lone "m" joined to the number before it ("300 m" → "300m").
    static func words(_ query: String) -> [String] {
        var words: [String] = []
        for word in query.split(whereSeparator: \.isWhitespace).map(String.init) {
            if word.lowercased() == "m", let last = words.last, Int(last) != nil {
                words[words.count - 1] = last + "m"
            } else {
                words.append(word)
            }
        }
        return words
    }

    /// The distance in metres a word names, e.g. 300 for "300" or "300m"; nil for other words.
    static func distance(in word: String) -> Int? {
        var w = word.lowercased()
        if w.hasSuffix("m") { w.removeLast() }
        guard !w.isEmpty, w.allSatisfy(\.isASCII) else { return nil }
        return Int(w)
    }

    private static func matches(_ range: ShootingRange, word: String) -> Bool {
        if let d = distance(in: word), range.distances.contains(d) { return true }
        return range.name.localizedStandardContains(word)
            || range.place.localizedStandardContains(word)
            || range.address.localizedStandardContains(word)
    }

    /// The picker list: nearby ranges first (see `NearbyRanges.pickerOrder`), narrowed to `query`.
    /// A selected range that is not in `ranges` (archived) is kept at the end so it stays visible.
    static func results(_ ranges: [ShootingRange], matching query: String,
                        from location: CLLocation? = nil, keeping selection: ShootingRange? = nil) -> [ShootingRange] {
        var list = NearbyRanges.pickerOrder(ranges, from: location)
        if let selection, !list.contains(selection) { list.append(selection) }
        return list.filter { matches($0, query) }
    }

    /// Second line of a picker row: place and, when nearby, the distance from here.
    static func subtitle(for range: ShootingRange, from location: CLLocation?, locale: Locale = .current) -> String? {
        let parts = [range.place.trimmingCharacters(in: .whitespaces),
                     NearbyRanges.subtitle(for: range, from: location, locale: locale) ?? ""]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
