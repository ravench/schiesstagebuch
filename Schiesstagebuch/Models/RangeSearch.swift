import Foundation
import CoreLocation

/// Search for the range picker and the statistics list.
enum RangeSearch {
    /// True when every word of `query` is found in the range's name, place or address,
    /// or names one of its distances ("300", "300m", "300 m"). Case and accent insensitive.
    static func matches(_ range: some RangePlace, _ query: String) -> Bool {
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

    private static func matches(_ range: some RangePlace, word: String) -> Bool {
        if let d = distance(in: word) {
            if range.distances.contains(d) { return true }
            // A number of up to three digits is a distance, or stands as one in the name («… 50m»): «10» listed
            // 207 ranges by their house numbers and postcodes, 3 of them with 10 m (review 2026-11-27).
            // Four digits and more are a postcode and go on to the address.
            if d < 1000 { return range.name.split { !$0.isLetter && !$0.isNumber }.contains { distance(in: String($0)) == d } }
        }
        return range.name.localizedStandardContains(word)
            || range.place.localizedStandardContains(word)
            || range.address.localizedStandardContains(word)
    }

    /// The picker list: nearby ranges first (see `NearbyRanges.pickerOrder`), narrowed to `query`.
    static func results<R: RangePlace>(_ ranges: [R], matching query: String, from location: CLLocation? = nil) -> [R] {
        NearbyRanges.pickerOrder(ranges, from: location).filter { matches($0, query) }
    }

    /// The picker list of the user's ranges and the catalogue. A selected range that none of `choices`
    /// stands for (it is archived) is kept at the end so it stays visible.
    static func results(_ choices: [RangeChoice], matching query: String,
                        from location: CLLocation? = nil, keeping selection: ShootingRange?) -> [RangeChoice] {
        var list = choices
        if let selection, !list.contains(where: { $0.stands(for: selection) }) { list.append(.record(selection)) }
        return results(list, matching: query, from: location)
    }

    /// Second line of a picker row: place and, when nearby, the distance from here.
    static func subtitle(for range: some RangePlace, from location: CLLocation?, locale: Locale = .current) -> String? {
        let parts = [range.place.trimmingCharacters(in: .whitespaces),
                     NearbyRanges.subtitle(for: range, from: location, locale: locale) ?? ""]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
