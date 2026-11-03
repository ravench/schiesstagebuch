import Foundation

/// Finds the shooting range an imported range stands for, so imports reuse the ranges already in
/// the app (the user's own and the Swiss catalogue) instead of adding duplicates.
///
/// Cues: the words of the name (spelling variants and generic words like "Schiessanlage" are
/// tolerated), the town and street, a postcode, distances written in the name ("300m"), the
/// distances the weapons shot there usually need, and for backups the position.
enum RangeMatcher {
    /// What is known about a range, whether it is in the app or only in the catalogue.
    struct Place {
        var name: String
        var place = ""
        var address = ""
        var distances: [Int] = []
        var latitude: Double?
        var longitude: Double?
        var catalogID = ""
        /// Already in the app: wins a tie against a catalogue range.
        var isExisting = false
    }

    /// A range prepared once for comparing against many names.
    struct Candidate {
        let place: Place
        let nameTokens: [String]
        let placeTokens: [String]
        let addressTokens: [String]
        let postcodes: Set<String>
        let distances: Set<Int>

        init(_ place: Place) {
            self.place = place
            let name = RangeMatcher.parse(place.name)
            nameTokens = name.tokens
            placeTokens = RangeMatcher.parse(place.place).tokens
            addressTokens = RangeMatcher.parse(place.address).tokens
            postcodes = RangeMatcher.postcodes(inAddress: place.address)
            distances = Set(place.distances).union(name.distances)
        }
    }

    // MARK: Text

    /// Words that say nothing about which range it is (de/fr/it/en).
    static let genericWords: Set<String> = [
        "schiessanlage", "schiessanlagen", "schiessstand", "schiesstand", "schiessplatz", "schutzenhaus", "schuetzenhaus",
        "schutzenstand", "pistolenstand", "gewehrstand", "kleinkaliberstand", "anlage", "stand", "sa", "ssv", "sv", "sg",
        "schutzen", "schutzenverein", "schutzengesellschaft", "verein", "indoor",
        "de", "du", "des", "la", "le", "les", "tir", "poligono", "di", "del", "della", "tiro",
        "im", "am", "an", "auf", "bei", "der", "die", "das", "und", "et", "en", "au", "the", "range", "shooting",
    ]

    /// Lower case without accents: "Albisgüetli" → "albisguetli".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// Name for comparing equal names: folded, single spaces.
    static func normalizedName(_ text: String) -> String {
        fold(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // swiftlint:disable force_try
    private static let distancePattern = try! NSRegularExpression(pattern: #"(\d+(?:\s*/\s*\d+)*)\s*m\b"#)
    private static let postcodePattern = try! NSRegularExpression(pattern: #"\b[1-9]\d{3}\b"#)
    private static let addressPostcodePattern = try! NSRegularExpression(pattern: #",\s*([1-9]\d{3})\b"#)
    // swiftlint:enable force_try

    /// Words, postcodes and distances ("300/50m" → 300, 50) of a range name typed by someone.
    struct Query {
        var tokens: [String]
        var postcodes: Set<String> = []
        var distances: Set<Int> = []
    }

    static func parse(_ text: String) -> Query {
        var s = fold(text)
        var distances = Set<Int>()
        let ns = s as NSString
        for m in distancePattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            ns.substring(with: m.range(at: 1)).split(separator: "/").forEach {
                if let n = Int($0.trimmingCharacters(in: .whitespaces)) { distances.insert(n) }
            }
        }
        s = distancePattern.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        let rest = s as NSString
        let postcodes = Set(postcodePattern.matches(in: s, range: NSRange(location: 0, length: rest.length))
            .map { rest.substring(with: $0.range) })
        let tokens = s.components(separatedBy: CharacterSet.alphanumerics.inverted).filter {
            $0.count >= 2 && !($0.first?.isNumber ?? true) && !genericWords.contains($0)
        }
        return Query(tokens: tokens, postcodes: postcodes, distances: distances)
    }

    /// The postcode of an address like "Uetlibergstrasse 341, 8045 Zürich".
    static func postcodes(inAddress address: String) -> Set<String> {
        let ns = address as NSString
        return Set(addressPostcodePattern.matches(in: address, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) })
    }

    /// 2 for the same word, 1 for a spelling variant of a long word ("Albisgüetli" / "Albisgütli"), else 0.
    static func wordMatch(_ a: String, _ b: String) -> Int {
        if a == b { return 2 }
        let shorter = min(a.count, b.count)
        let allowed = shorter >= 10 ? 2 : shorter >= 7 ? 1 : 0
        guard allowed > 0, abs(a.count - b.count) <= allowed else { return 0 }
        return editDistance(Array(a), Array(b)) <= allowed ? 1 : 0
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: Matching a typed name

    /// Ranking of one candidate, compared in order: postcode, words found in its name, already in the
    /// app, fitting distances, words found in its town.
    private struct Score: Comparable {
        var parts: [Int]
        static func < (a: Score, b: Score) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
    }

    private static func score(_ query: Query, hint: Set<Int>, _ c: Candidate) -> Score? {
        if !query.postcodes.isEmpty, !c.postcodes.isEmpty, query.postcodes.isDisjoint(with: c.postcodes) { return nil }
        if !query.distances.isEmpty, !query.distances.isSubset(of: c.distances) { return nil }
        var name = 0, town = 0
        for q in query.tokens {
            let inName = c.nameTokens.map { wordMatch(q, $0) }.max() ?? 0
            let inTown = c.placeTokens.contains { wordMatch(q, $0) > 0 }
            // Every word has to be somewhere: in the name, the town or the street.
            guard inName > 0 || inTown || c.addressTokens.contains(where: { wordMatch(q, $0) > 0 }) else { return nil }
            name += inName
            if inTown { town += 1 }
        }
        let distance = !hint.isDisjoint(with: c.distances) ? 2 : c.distances.isEmpty ? 1 : 0
        let postcode = query.postcodes.isEmpty || c.postcodes.isEmpty ? 0 : 1
        return Score(parts: [postcode, name, c.place.isExisting ? 1 : 0, distance, town])
    }

    /// Index of the range `text` stands for, or nil when none or several fit equally well.
    /// `hint`: distances the weapons shot there usually need (e.g. 300 for a service rifle).
    static func bestMatch(for text: String, preferring hint: [Int] = [], among candidates: [Candidate]) -> Int? {
        let query = parse(text)
        guard !query.tokens.isEmpty else { return nil }
        let hint = Set(hint)
        var best: [Int] = []
        var bestScore: Score?
        for (i, c) in candidates.enumerated() {
            guard let s = score(query, hint: hint, c) else { continue }
            if let b = bestScore, s < b { continue }
            if let b = bestScore, s == b { best.append(i) } else { best = [i]; bestScore = s }
        }
        if best.count <= 1 { return best.first }
        // A tie goes to the range whose whole name was typed ("Aarwangen" → "Aarwangen 50m").
        let whole = best.filter { i in
            candidates[i].nameTokens.allSatisfy { t in query.tokens.contains { wordMatch(t, $0) > 0 } }
        }
        return whole.count == 1 ? whole[0] : nil
    }

    // MARK: Matching a backed-up range

    /// Positions further apart than this are different ranges even with the same name.
    static let sameNameMaxMetres = 1000.0

    /// Index of the range in the app that a range from a backup is: the same catalogue range, the same
    /// name (unless far apart), or a range close by whose name fits and whose distances don't contradict.
    static func sameRange(_ incoming: Place, among existing: [Place]) -> Int? {
        if !incoming.catalogID.isEmpty, let i = existing.firstIndex(where: { $0.catalogID == incoming.catalogID }) {
            return i
        }
        let name = normalizedName(incoming.name)
        if !name.isEmpty, let i = existing.firstIndex(where: {
            normalizedName($0.name) == name && (metres(incoming, $0) ?? 0) <= sameNameMaxMetres
        }) {
            return i
        }
        let query = parse(incoming.name)
        guard !query.tokens.isEmpty else { return nil }
        let incomingDistances = Set(incoming.distances).union(query.distances)
        return existing.indices
            .compactMap { i -> (Int, Double)? in
                guard let m = metres(incoming, existing[i]), m <= RangeCatalog.sameRangeMetres else { return nil }
                let c = Candidate(existing[i])
                guard incomingDistances.isEmpty || c.distances.isEmpty || !incomingDistances.isDisjoint(with: c.distances),
                      score(Query(tokens: query.tokens), hint: [], c) != nil else { return nil }
                return (i, m)
            }
            .min { $0.1 < $1.1 }?.0
    }

    private static func metres(_ a: Place, _ b: Place) -> Double? {
        guard let la = a.latitude, let lo = a.longitude, let lb = b.latitude, let lob = b.longitude else { return nil }
        return RangeCatalog.distance(la, lo, lb, lob)
    }
}

extension RangeMatcher.Place {
    init(_ range: ShootingRange) {
        self.init(name: range.name, place: range.place, address: range.address, distances: range.distances,
                  latitude: range.latitude, longitude: range.longitude, catalogID: range.catalogID, isExisting: true)
    }

    init(_ item: RangeCatalog.Item) {
        self.init(name: item.name, place: item.place, address: item.address ?? "", distances: item.distances,
                  latitude: item.lat, longitude: item.lon, catalogID: item.id)
    }
}

extension WeaponCategory {
    /// Distances in metres this kind of weapon is usually shot at in Switzerland; empty when it could be anything.
    var usualDistances: [Int] {
        switch self {
        case .pistol, .sportPistol, .luger, .revolver, .pcc: [25, 50]
        case .airPistol, .airgun: [10]
        case .sportRifle: [50, 300]
        case .serviceRifle, .serviceCarbine, .huntingRifle, .longRange, .machineGun: [300]
        default: []
        }
    }
}
