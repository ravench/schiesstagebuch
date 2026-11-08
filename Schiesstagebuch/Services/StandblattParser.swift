import Foundation

// Reads Standblätter (score strips from electronic target systems, e.g. SIUS at
// the SGZ ranges) from recognised text. Pure Foundation so it can be unit tested
// without Vision: `TextRecognizer` turns photos into `OCRLine`s, this file turns
// those into `ScannedStandblatt`s.
//
// A printed strip looks like this, twice side by side (the right copy ends every
// line with "K"):
//
//     Scheibe 2/50
//     11.4.2026 10:22
//     A10 Benutzerprogra
//      1 ↖ 10 92        shot number, direction arrow, ring (A10), hundredths (A100)
//      4 ↑ 10# 96       "#" marks an inner ten
//     ( 9 ↗ 10 93)      bracketed = repeated display, does not count
//     Subtota 91 866    end of a Passe: rings and hundredths
//     Total   91 866
//
// A100 strips print only the hundredths ("1 ↘ 89", "Subtota 430").

/// One piece of recognised text and where it is on the page (normalised 0…1, origin top left).
struct OCRLine: Equatable {
    var text: String
    var x: Double
    var y: Double
    var width: Double = 0.2
    var height: Double = 0.015
    var confidence: Double = 1
}

enum StandblattTarget: String, Equatable {
    case a10 = "A10", a100 = "A100"
    case p10 = "P10", p100 = "P100"

    /// Highest value of one shot.
    var maxPerShot: Int { self == .a10 || self == .p10 ? 10 : 100 }
}

/// Which printed value becomes the shot value in the entry.
enum StandblattScoring: String, CaseIterable, Identifiable {
    /// Rings 0…10 (A10 / P10).
    case rings
    /// Hundredths 0…100 (A100 / P100, also printed on A10 strips).
    case hundredths
    var id: Self { self }
    var perShot: Double { self == .rings ? 10 : 100 }
}

struct ScannedShot: Equatable {
    var number: Int
    var ring: Int?
    var hundredths: Int?
    var innerTen = false
    /// The ring and the hundredths did not agree; the ring was derived from the hundredths.
    var uncertain = false

    func value(_ scoring: StandblattScoring) -> Int? { scoring == .rings ? ring : hundredths }
}

struct ScannedPasse: Equatable {
    var shots: [ScannedShot] = []
    var printedRings: Int?
    var printedHundredths: Int?

    func printed(_ scoring: StandblattScoring) -> Int? { scoring == .rings ? printedRings : printedHundredths }
    func sum(_ scoring: StandblattScoring) -> Int { shots.compactMap { $0.value(scoring) }.reduce(0, +) }
}

struct ScannedStandblatt: Equatable {
    var title = ""
    /// Program lines under the title, e.g. "6 EF, 4 SF in 60 Sek. ab 1. Schuss".
    var details: [String] = []
    var target: StandblattTarget = .a10
    /// e.g. "2/50" from "Scheibe 2/50".
    var scheibe: String?
    var date: Date?
    var passes: [ScannedPasse] = []
    var printedRings: Int?
    var printedHundredths: Int?
    /// Bracketed repeats that were skipped.
    var repeats = 0
    /// Read from a handwritten sheet: values are suggestions.
    var handwritten = false
    /// Shots dropped because the Passe only matched its printed sum without them (see StandblattPasseCheck).
    var removedShots: [Int] = []

    var shots: [ScannedShot] { passes.flatMap(\.shots) }
    var innerTens: Int { shots.filter(\.innerTen).count }

    var availableScorings: [StandblattScoring] {
        StandblattScoring.allCases.filter { s in !shots.isEmpty && shots.allSatisfy { $0.value(s) != nil } }
    }

    /// Rings when the strip has them, else hundredths.
    var defaultScoring: StandblattScoring { availableScorings.first ?? .hundredths }

    func sum(_ scoring: StandblattScoring) -> Int { passes.map { $0.sum(scoring) }.reduce(0, +) }
    func printedTotal(_ scoring: StandblattScoring) -> Int? { scoring == .rings ? printedRings : printedHundredths }

    /// The official total when printed, else the sum of the shots.
    func total(_ scoring: StandblattScoring) -> Int { printedTotal(scoring) ?? sum(scoring) }
    func maxPoints(_ scoring: StandblattScoring) -> Double { Double(shots.count) * scoring.perShot }

    enum Issue: Equatable {
        /// Passe number (1-based), printed subtotal, sum of the read shots.
        case passeMismatch(Int, printed: Int, read: Int)
        case totalMismatch(printed: Int, read: Int)
        /// Shot numbers that are missing in the sequence.
        case missingShots([Int])
        /// Shot numbers whose ring did not match the hundredths.
        case uncertainShots([Int])
        /// The total is more than the strip's shots can reach: something was misread.
        case exceedsMax(total: Int, max: Int)
        /// Passe number (1-based) and its shot count, when that is not a usual Passe length.
        case unusualPasseLength(Int, shots: Int)
        /// Shots left out so that a Passe matches its printed sum.
        case removedShots([Int])
    }

    /// Checks the read shots against the printed subtotals and total.
    func issues(_ scoring: StandblattScoring) -> [Issue] {
        var result: [Issue] = []
        for (i, p) in passes.enumerated() {
            if let printed = p.printed(scoring), printed != p.sum(scoring) {
                result.append(.passeMismatch(i + 1, printed: printed, read: p.sum(scoring)))
            }
        }
        if let printed = printedTotal(scoring), printed != sum(scoring) {
            result.append(.totalMismatch(printed: printed, read: sum(scoring)))
        }
        let numbers = shots.map(\.number)
        if let first = numbers.first, let last = numbers.max(), !handwritten {
            let missing = (first...max(first, last)).filter { !numbers.contains($0) && !removedShots.contains($0) }
            if !missing.isEmpty { result.append(.missingShots(missing)) }
        }
        let uncertain = shots.filter(\.uncertain).map(\.number)
        if scoring == .rings, !uncertain.isEmpty { result.append(.uncertainShots(uncertain)) }
        result += passeLengthIssues
        let limit = maxPoints(scoring)
        if !shots.isEmpty, Double(total(scoring)) > limit {
            result.append(.exceedsMax(total: total(scoring), max: Int(limit)))
        }
        return result
    }

    /// The values of each Passe in the format of `Entry.shotValuesText` lines.
    func passTexts(_ scoring: StandblattScoring) -> [String] {
        passes.map { $0.shots.compactMap { $0.value(scoring) }.map(String.init).joined(separator: " ") }
            .filter { !$0.isEmpty }
    }
}

enum StandblattParser {
    // MARK: Entry points

    /// Parses one or more photographed pages. A page without a "Scheibe" header continues
    /// the last strip of the page before (long programs need two photos).
    static func parse(pages: [[OCRLine]]) -> [ScannedStandblatt] {
        var stream: [StreamItem] = []
        for page in pages { stream += orderedItems(page) }
        let strips = parseStream(stream)
        if !strips.isEmpty { return strips }
        return pages.flatMap(HandwrittenParser.parse)
    }

    /// Parses plain text, one line per row, already in reading order. Lines of the copy
    /// column (ending in "K") are skipped.
    static func parse(text: String) -> [ScannedStandblatt] {
        parseStream(text.split(whereSeparator: \.isNewline).map { .line(String($0)) })
    }

    // MARK: Records

    enum Record: Equatable {
        case header(scheibe: String?, copy: Bool)
        case date(Date)
        case shot(RawShot)
        case subtotal([Int], copy: Bool)
        case total([Int], copy: Bool)
        case other
    }

    struct RawShot: Equatable {
        var number: Int
        /// Numbers after the shot number; a misread arrow can add one in front.
        var values: [Int]
        var innerTen: Bool
        var bracketed: Bool
        var copy: Bool
    }

    static func record(_ line: String) -> Record {
        var text = line.trimmingCharacters(in: .whitespaces)
        var copy = endsWithCopyMarker(text)
        // Both columns read as one line ("Subtota 91 866  Subtota 91 866 K"): keep the first.
        let words = text.split(separator: " ")
        if let first = words.first, first.filter(\.isLetter).count >= 3,
           let again = words.dropFirst().firstIndex(where: { $0.lowercased() == first.lowercased() }) {
            text = words[..<again].joined(separator: " ")
            copy = false
        }
        let lower = text.lowercased()
        // "Scheibe 2/50"; not the printed "Scheibe A10, 10 EF" of a form.
        if lower.range(of: #"^s?ch[ae]?i?b[e]?\s*[0-9oilzsb]"#, options: .regularExpression) != nil {
            return .header(scheibe: scheibeNumber(text), copy: copy)
        }
        let letters = lower.replacingOccurrences(of: "0", with: "o").replacingOccurrences(of: "5", with: "s")
        if letters.range(of: #"^s?[uo]?bt[o]?ta|^su[bo]t[o]?t|^subt"#, options: .regularExpression) != nil {
            return .subtotal(trailingNumbers(text), copy: copy)
        }
        if letters.range(of: #"^t[o]t[a@]?[l1i]?\b|^tota"#, options: .regularExpression) != nil {
            return .total(trailingNumbers(text), copy: copy)
        }
        if let date = date(in: text) { return .date(date) }
        if let shot = shot(text) { return .shot(shot) }
        return .other
    }

    private static func endsWithCopyMarker(_ text: String) -> Bool {
        guard let last = text.split(separator: " ").last else { return false }
        return last == "K" || last == "k" || (last.count > 1 && last.hasSuffix("K") && Int(last.dropLast()) != nil)
    }

    private static func scheibeNumber(_ text: String) -> String? {
        guard let r = text.range(of: #"\d+\s*/\s*\d+"#, options: .regularExpression) else { return nil }
        return text[r].replacingOccurrences(of: " ", with: "")
    }

    /// Numbers after the label word: "Subtota 91 866 K" → [91, 866].
    private static func trailingNumbers(_ text: String) -> [Int] {
        text.split(separator: " ").dropFirst().compactMap { number(String($0)) }
    }

    // swiftlint:disable:next force_try
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"(\d{1,2})\s?[.,]\s?(\d{1,2})\s?[.,]\s?(\d{4})(?:\s+(\d{1,2})\s?[:.;,'‘’]?\s?(\d{2}))?"#)

    static func date(in text: String) -> Date? {
        let ns = text as NSString
        guard let m = dateRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> Int? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : Int(ns.substring(with: r))
        }
        guard let d = group(1), let mo = group(2), let y = group(3),
              (1...31).contains(d), (1...12).contains(mo), (1990...2100).contains(y) else { return nil }
        var c = DateComponents(year: y, month: mo, day: d)
        if let h = group(4), let mi = group(5), h < 24, mi < 60 { c.hour = h; c.minute = mi } else { c.hour = 12 }
        // The strip prints Gregorian dates, whatever calendar the phone is set to.
        return Calendar(identifier: .gregorian).date(from: c)
    }

    /// OCR reads the thermal font's digits with a few typical mix-ups.
    static func number(_ token: String) -> Int? {
        let swaps: [Character: Character] = ["O": "0", "o": "0", "D": "0", "I": "1", "l": "1", "|": "1", "i": "1",
                                           "S": "5", "s": "5", "B": "8", "Z": "2", "z": "2", "g": "9", "q": "9"]
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;"))
        guard !cleaned.isEmpty, cleaned.count <= 5, cleaned.contains(where: \.isNumber) else { return nil }
        let digits = String(cleaned.map { swaps[$0] ?? $0 })
        return digits.allSatisfy(\.isNumber) ? Int(digits) : nil
    }

    /// "10#", "10*", "10‡" … – a ten followed by a marker, or a three digit "10x" misread.
    private static func innerTen(_ token: String) -> Bool {
        guard token.hasPrefix("10"), token.count == 3, let last = token.last else { return false }
        return !last.isNumber || Int(token).map { $0 > 100 } == true
    }

    static func shot(_ line: String) -> RawShot? {
        let bracketed = line.contains("(") || line.contains(")")
        let cleaned = line.replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " ")
        var tokens = cleaned.split(separator: " ").map(String.init)
        var copy = false
        if let last = tokens.last, last == "K" || last == "k" {
            tokens.removeLast(); copy = true
        } else if let last = tokens.last, last.count > 1, last.hasSuffix("K"), Int(last.dropLast()) != nil {
            tokens[tokens.count - 1] = String(last.dropLast()); copy = true
        }
        // Text with real words is not a shot row ("6 EF, 4 SF in 60 Sek.", "1996 OP 9" is caught below).
        if tokens.contains(where: { $0.filter(\.isLetter).count >= 3 }) { return nil }
        guard tokens.count >= 2, let shotNumber = number(tokens[0]), (1...200).contains(shotNumber) else { return nil }

        var values: [Int] = []
        var ten = false
        var cut = false
        for token in tokens.dropFirst() {
            // Two columns read as one line: stop where the copy's shot number starts.
            if let n = number(token), n == shotNumber,
               values.count >= 2 || (values.count == 1 && values[0] > 10) {
                cut = true
                break
            }
            if innerTen(token) {
                values.append(10); ten = true
            } else if let n = number(token) {
                values.append(n)
            } else if (token == "#" || token == "*") && values.last == 10 {
                ten = true
            }
        }
        if cut { copy = false }
        guard let last = values.last, last <= 100 else { return nil }
        return RawShot(number: shotNumber, values: values, innerTen: ten, bracketed: bracketed, copy: copy)
    }

    /// The ring a hundredths value belongs to: 81…90 → 9, 91…100 → 10.
    static func ring(forHundredths h: Int) -> Int { min(10, max(0, Int((Double(h) / 10).rounded(.up)))) }

    // MARK: Stream

    enum StreamItem: Equatable {
        case line(String)
        case meta(title: String, details: [String])
    }

    private struct Draft {
        var strip = ScannedStandblatt()
        var current = ScannedPasse()
        var raw: [RawShot] = []
        var subtotals: [[Int]] = []
        var total: [Int]?
        var seen = Set<Int>()
        /// After the Total nothing belongs to the strip any more (handwritten notes below it).
        var closed = false

        var isEmpty: Bool { raw.isEmpty && strip.scheibe == nil && strip.date == nil }

        mutating func closePasse(_ numbers: [Int]?) {
            guard !current.shots.isEmpty else { return }
            subtotals.append(numbers ?? [])
            strip.passes.append(current)
            current = ScannedPasse()
        }
    }

    static func parseStream(_ items: [StreamItem]) -> [ScannedStandblatt] {
        var drafts: [Draft] = []
        var draft = Draft()
        var pendingMeta: (title: String, details: [String])?

        func finish() {
            draft.closePasse(nil)
            drafts.append(draft)
            draft = Draft()
        }

        for item in items {
            switch item {
            case let .meta(title, details):
                pendingMeta = (title, details)
            case let .line(text):
                switch record(text) {
                case let .header(scheibe, copy):
                    guard !copy else { continue }
                    if !draft.isEmpty { finish() }
                    draft.strip.scheibe = scheibe ?? ""
                    if let meta = pendingMeta {
                        draft.strip.title = meta.title; draft.strip.details = meta.details; pendingMeta = nil
                    }
                case let .date(date):
                    if draft.strip.date == nil { draft.strip.date = date }
                case let .shot(shot):
                    // Only rows under a "Scheibe" header (or continuing one) count.
                    guard !shot.copy, !draft.closed, draft.strip.scheibe != nil else { continue }
                    // A number far beyond the last shot is not a shot row (e.g. handwritten sums).
                    if let highest = draft.seen.max(), shot.number > highest + 3 { continue }
                    if shot.bracketed || draft.seen.contains(shot.number) {
                        draft.strip.repeats += 1
                        continue
                    }
                    draft.seen.insert(shot.number)
                    draft.raw.append(shot)
                    draft.current.shots.append(ScannedShot(number: shot.number))
                case let .subtotal(numbers, copy):
                    guard !copy, !draft.closed, !draft.current.shots.isEmpty else { continue }
                    draft.closePasse(numbers)
                case let .total(numbers, copy):
                    // A Total before any "Scheibe" header (a printed box, a handwritten sum in the
                    // margin) belongs to no strip; closing the empty draft would swallow the first one.
                    guard !copy, !draft.closed, draft.strip.scheibe != nil else { continue }
                    draft.closePasse(nil)
                    draft.total = numbers
                    draft.closed = true
                case .other:
                    break
                }
            }
        }
        finish()
        return drafts.compactMap(resolve)
    }

    /// Decides between A10 and A100 and fills in the shot values.
    private static func resolve(_ draft: Draft) -> ScannedStandblatt? {
        guard !draft.raw.isEmpty else { return nil }
        var strip = draft.strip
        let sums = draft.subtotals.filter { !$0.isEmpty } + (draft.total.map { [$0] } ?? [])
        let consistent = draft.raw.filter { $0.values.count >= 2 && $0.values[$0.values.count - 2] == ring(forHundredths: $0.values.last!) }.count
        let isA10: Bool
        if sums.contains(where: { $0.count >= 2 }) { isA10 = true }
        else if !sums.isEmpty { isA10 = false }
        else { isA10 = consistent * 2 >= draft.raw.count }
        strip.target = isA10 ? .a10 : .a100

        var index = 0
        for p in strip.passes.indices {
            for s in strip.passes[p].shots.indices {
                let raw = draft.raw[index]; index += 1
                var shot = ScannedShot(number: raw.number, hundredths: raw.values.last, innerTen: raw.innerTen)
                if isA10, let h = raw.values.last {
                    let expected = ring(forHundredths: h)
                    // The ring is printed before the hundredths; when it was misread, the hundredths decide.
                    shot.ring = expected
                    // A10 rows print ring and hundredths: one value read means the other was lost.
                    shot.uncertain = raw.values.count < 2 || raw.values[raw.values.count - 2] != expected
                    if shot.innerTen && shot.ring != 10 { shot.innerTen = false }
                }
                strip.passes[p].shots[s] = shot
            }
            let numbers = p < draft.subtotals.count ? draft.subtotals[p] : []
            let passe = strip.passes[p]
            let printed = split(numbers, isA10: isA10, sums: (passe.sum(.rings), passe.sum(.hundredths)))
            strip.passes[p].printedRings = printed.rings
            strip.passes[p].printedHundredths = printed.hundredths
        }
        let printed = split(draft.total ?? [], isA10: isA10, sums: (strip.sum(.rings), strip.sum(.hundredths)))
        strip.printedRings = printed.rings
        strip.printedHundredths = printed.hundredths
        strip.dropExtraShots()
        return strip
    }

    /// "91 866" on A10 strips, "430" on A100 strips. A single number on an A10 strip (one was
    /// not read) goes to whichever sum it is closer to.
    private static func split(_ numbers: [Int], isA10: Bool,
                              sums: (rings: Int, hundredths: Int)) -> (rings: Int?, hundredths: Int?) {
        if isA10 && numbers.count >= 2 { return (numbers[numbers.count - 2], numbers.last) }
        guard let last = numbers.last else { return (nil, nil) }
        if isA10 && abs(last - sums.rings) <= abs(last - sums.hundredths) { return (last, nil) }
        return (nil, last)
    }

    // MARK: Layout

    /// Puts the lines of one photo into reading order: one strip column after the other,
    /// skipping the duplicate copy columns, with each strip's title before its header.
    static func orderedItems(_ page: [OCRLine]) -> [StreamItem] {
        let headers = page.filter { if case .header = record($0.text) { return true }; return false }
        let copyHeaders = copyFlags(headers)
        var groups: [[OCRLine]] = Array(repeating: [], count: headers.count)
        var loose: [OCRLine] = []

        for line in page where !headers.contains(line) {
            let candidates = headers.indices.filter { headers[$0].y - 0.02 <= line.y }
            guard let best = candidates.min(by: { a, b in
                let da = abs(headers[a].x - line.x), db = abs(headers[b].x - line.x)
                return da != db ? da < db : headers[a].y > headers[b].y
            }), abs(headers[best].x - line.x) < 0.2 else {
                loose.append(line)
                continue
            }
            groups[best].append(line)
        }

        var items = looseItems(loose)
        let order = headers.indices.filter { !copyHeaders[$0] }.sorted { (headers[$0].x, headers[$0].y) < (headers[$1].x, headers[$1].y) }
        for i in order {
            let header = headers[i]
            let partner = headers.indices.filter { copyHeaders[$0] && abs(headers[$0].y - header.y) < 0.04 && headers[$0].x > header.x }
                .min { headers[$0].x < headers[$1].x }
            let right = partner.map { headers[$0].x + headers[$0].width } ?? header.x + header.width * 2
            if let meta = titleMeta(page, above: header, from: header.x - 0.08, to: right + 0.08) { items.append(meta) }
            items.append(.line(header.text))
            items += groups[i].sorted { $0.y < $1.y }.map { .line($0.text) }
        }
        return items
    }

    /// Copy headers end in "K"; when OCR lost the K, the right one of two headers on a row is the copy.
    private static func copyFlags(_ headers: [OCRLine]) -> [Bool] {
        var flags = headers.map { endsWithCopyMarker($0.text) }
        var bands: [[Int]] = []
        for i in headers.indices.sorted(by: { headers[$0].y < headers[$1].y }) {
            if let b = bands.indices.last, let first = bands[b].first, abs(headers[first].y - headers[i].y) < 0.04 {
                bands[b].append(i)
            } else {
                bands.append([i])
            }
        }
        for band in bands where !band.contains(where: { flags[$0] }) && band.count.isMultiple(of: 2) {
            let sorted = band.sorted { headers[$0].x < headers[$1].x }
            for (n, i) in sorted.enumerated() where n % 2 == 1 { flags[i] = true }
        }
        return flags
    }

    /// Lines that belong to no header (a continuation photo): cluster them into columns by x and
    /// drop the copy columns.
    private static func looseItems(_ lines: [OCRLine]) -> [StreamItem] {
        let rows = lines.filter {
            switch record($0.text) {
            case .shot, .subtotal, .total: return true
            default: return false
            }
        }
        guard !rows.isEmpty else { return [] }
        var columns: [[OCRLine]] = []
        for line in rows.sorted(by: { $0.x < $1.x }) {
            if let last = columns.last?.last, line.x - last.x < 0.06 { columns[columns.count - 1].append(line) }
            else { columns.append([line]) }
        }
        var keep = columns.map { col in col.filter { endsWithCopyMarker($0.text) }.count * 2 <= col.count }
        if keep.allSatisfy({ $0 }) && columns.count >= 2 && columns.count.isMultiple(of: 2) {
            keep = columns.indices.map { $0 % 2 == 0 }
        }
        return columns.indices.filter { keep[$0] }.flatMap { columns[$0].sorted { $0.y < $1.y } }.map { .line($0.text) }
    }

    // swiftlint:disable:next force_try
    private static let junk = try! NSRegularExpression(
        pattern: #"sch[üu]tzen|der stadt|name|standard|kar\b|exemplar|benutzer|^\d[\d\s()]*$|^a10+$|^[□☐☑✓xX\s]+$|57\s*/\s*0"#,
        options: .caseInsensitive)
    // swiftlint:disable:next force_try
    private static let detailHint = try! NSRegularExpression(
        pattern: #"\b\d+\s*(EF|SF)\b|stich|waffen|sek\.|schuss|meisterschaft|match|probe|cible|coups"#,
        options: .caseInsensitive)

    /// The largest printed text above a strip is its program title, e.g. "Sektion".
    private static func titleMeta(_ page: [OCRLine], above header: OCRLine, from: Double, to: Double) -> StreamItem? {
        let candidates = page.filter { line in
            let ns = line.text as NSString
            let range = NSRange(location: 0, length: ns.length)
            return line.y < header.y - 0.01 && line.y > header.y - 0.5
                && (from...to).contains(line.x + line.width / 2)
                && line.confidence >= 0.4
                && line.text.filter(\.isLetter).count >= 3
                && record(line.text) == .other
                && junk.firstMatch(in: line.text, range: range) == nil
        }
        guard let title = candidates.max(by: { $0.height < $1.height }) else { return nil }
        let details = candidates.filter { line in
            let ns = line.text as NSString
            return line != title && line.y > title.y
                && detailHint.firstMatch(in: line.text, range: NSRange(location: 0, length: ns.length)) != nil
        }
        .sorted { $0.y < $1.y }.map(\.text)
        return .meta(title: title.text.trimmingCharacters(in: .whitespaces), details: details)
    }
}

/// Best effort for handwritten score sheets: each "… Scheibe P-10" heading followed by a row of
/// boxed values, the last box (above the per-shot maximum) being the total.
enum HandwrittenParser {
    // swiftlint:disable:next force_try
    private static let section = try! NSRegularExpression(
        pattern: #"scheibe\s*([AP])\s*-?\s*(100|10)\b"#, options: .caseInsensitive)

    static func parse(_ page: [OCRLine]) -> [ScannedStandblatt] {
        let sections = page.compactMap { line -> (line: OCRLine, target: StandblattTarget)? in
            let ns = line.text as NSString
            guard let m = section.firstMatch(in: line.text, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let letter = ns.substring(with: m.range(at: 1)).uppercased()
            let hundred = ns.substring(with: m.range(at: 2)) == "100"
            let target: StandblattTarget = letter == "A" ? (hundred ? .a100 : .a10) : (hundred ? .p100 : .p10)
            return (line, target)
        }
        .sorted { $0.line.y < $1.line.y }
        let headline = page.filter { line in line.text.filter(\.isLetter).count >= 4 && !sections.contains { $0.line == line } }
            .max { $0.height < $1.height }?.text

        var result: [ScannedStandblatt] = []
        for (i, s) in sections.enumerated() {
            let bottom = i + 1 < sections.count ? sections[i + 1].line.y - 0.005 : s.line.y + 0.15
            let row = page.filter { line in
                let digits = line.text.filter(\.isNumber).count
                return line.y > s.line.y + 0.015 && line.y < bottom
                    && digits > 0 && digits * 2 >= line.text.filter { !$0.isWhitespace }.count
            }
            .sorted { $0.x < $1.x }
            let tokens = row.flatMap { $0.text.split(whereSeparator: { !$0.isNumber }).map(String.init) }
            guard !tokens.isEmpty else { continue }
            let (values, total) = split(tokens, max: s.target.maxPerShot)
            guard !values.isEmpty else { continue }

            var strip = ScannedStandblatt()
            strip.handwritten = true
            strip.target = s.target
            strip.title = name(of: s.line.text)
            if let headline, headline != s.line.text { strip.details = [headline] }
            let shots = values.enumerated().map { n, v in
                s.target.maxPerShot == 10 ? ScannedShot(number: n + 1, ring: v) : ScannedShot(number: n + 1, hundredths: v)
            }
            strip.passes = [ScannedPasse(shots: shots)]
            if s.target.maxPerShot == 10 { strip.printedRings = total } else { strip.printedHundredths = total }
            result.append(strip)
        }
        return result
    }

    /// "Vereinsstich EF Scheibe P-10" → "Vereinsstich EF".
    static func name(of heading: String) -> String {
        guard let r = heading.range(of: "scheibe", options: .caseInsensitive) else { return heading }
        return heading[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
    }

    /// Splits digit groups into shot values (OCR often merges neighbouring boxes: "1010" → 10, 10).
    /// A last group above the per-shot maximum is the total.
    static func split(_ tokens: [String], max: Int) -> (values: [Int], total: Int?) {
        var tokens = tokens
        var total: Int?
        if let last = tokens.last, let n = Int(last), n > max, tokens.count > 1 {
            total = n; tokens.removeLast()
        }
        var values: [Int] = []
        for token in tokens {
            var rest = Substring(token)
            while !rest.isEmpty {
                let take: Int
                if max == 10 { take = rest.hasPrefix("10") ? 2 : 1 }
                else { take = rest.hasPrefix("100") ? 3 : min(2, rest.count) }
                if let v = Int(rest.prefix(take)), v <= max { values.append(v) }
                rest = rest.dropFirst(take)
            }
        }
        return (values, total)
    }
}

/// What a scanned strip fills into the entry editor.
struct StandblattImport: Equatable {
    var event: String
    var date: Date?
    /// One line per Passe, as `Entry.shotValuesText` stores them.
    var passes: [String]
    var result: String
    var maxPoints: Double
    var notes: String
    /// Set when the read shots don't match the printed sums or could not be checked; it heads the notes.
    var sumWarning: String?

    init(_ strip: ScannedStandblatt, scoring: StandblattScoring, event: String? = nil) {
        self.event = (event ?? strip.title).trimmingCharacters(in: .whitespaces)
        date = strip.date
        passes = strip.passTexts(scoring)
        result = String(strip.total(scoring))
        maxPoints = strip.maxPoints(scoring)

        var parts = strip.details
        if let scheibe = strip.scheibe, !scheibe.isEmpty { parts.append("\("Scheibe".loc) \(scheibe)") }
        parts.append(strip.target.rawValue)
        if strip.innerTens > 0 { parts.append(String(localized: "Innenzehner: \(strip.innerTens.formatted())")) }
        // Keep the other scale in the notes: the A100 total of an A10 strip, or the other way round.
        let other: StandblattScoring = scoring == .rings ? .hundredths : .rings
        if strip.availableScorings.contains(other) {
            let label = other == .rings ? "A10" : "A100"
            parts.append("\(label): \(strip.total(other))")
        }
        sumWarning = strip.sumWarning(scoring)
        notes = ([sumWarning] + [parts.joined(separator: " · ")]).compactMap { $0 }.joined(separator: "\n")
    }
}
