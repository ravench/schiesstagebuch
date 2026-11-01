import Foundation
import SwiftData

// Finds the lot number (Losnummer) on a photo of an ammunition box.
//
// Pure Swift, so it can be tested without Vision: `TextRecognizer` and `BarcodeReader`
// turn the photo into text lines and barcode payloads, this file ranks what could be
// the lot. Everything that depends on how real boxes look is in `LotNumberParser.Rules`,
// so it can be tuned as more boxes are photographed.

/// A barcode found on the photo, independent of Vision.
struct ScannedBarcode: Equatable {
    enum Kind: Equatable {
        /// Retail product codes (EAN-8/13, UPC, ITF-14): they name the product, never the lot.
        case product
        /// GS1-128, GS1 DataMatrix, GS1 DataBar: element strings that may carry AI (10) = lot.
        case gs1
        /// Anything else (Code 128, Code 39, QR, DataMatrix …): the payload might be the lot.
        case other
    }

    var payload: String
    var kind: Kind
}

/// One possible lot number, with where it came from.
struct LotCandidate: Equatable, Identifiable {
    enum Source: Equatable {
        /// GS1 application identifier (10) in a barcode or in printed "(10) …" text.
        case gs1
        /// Text after a label such as "LOT", "Los-Nr." or "Lotto".
        case label
        /// The whole payload of a non-retail barcode.
        case barcode
        /// Text that looks like a lot number but has no label next to it.
        case guess
    }

    var number: String
    var source: Source
    /// 0…1, higher is more likely.
    var score: Double

    var id: String { LotNumber.normalized(number) }
}

enum LotNumber {
    /// Form used to compare lot numbers: upper case, without spaces, dashes, dots and slashes,
    /// so "a-2391", "A 2391" and "A2391" are the same lot.
    static func normalized(_ number: String) -> String {
        String(number.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// The existing lot with the same number, ignoring case and separators.
    static func match(_ number: String, in lots: [AmmoLot]) -> AmmoLot? {
        let key = normalized(number)
        guard !key.isEmpty else { return nil }
        return lots.first { normalized($0.number) == key }
    }

    /// The lot of this ammo with this number; created when the ammo doesn't have it yet.
    /// An archived lot that is scanned again becomes active again.
    static func lot(_ number: String, for ammunition: Ammunition, in context: ModelContext) -> AmmoLot {
        if let existing = match(number, in: ammunition.lots ?? []) {
            existing.isArchived = false
            return existing
        }
        let lot = AmmoLot(number: number.trimmingCharacters(in: .whitespaces))
        context.insert(lot)
        lot.ammunition = ammunition
        return lot
    }

    /// The pattern of a lot number: digits become 9, letters A, separators stay ("1903/44" → "9999/99").
    static func shape(_ number: String) -> String {
        String(number.uppercased().map { $0.isNumber ? "9" : $0.isLetter ? "A" : $0 })
    }
}

enum LotNumberParser {
    /// Everything that depends on how real boxes are printed. Tune these, not the code below.
    enum Rules {
        /// Labels in front of a lot number (DE, EN, FR, IT, ES, CZ), as regular expressions,
        /// matched case-insensitively. Longer variants first.
        static let labels: [String] = [
            #"N[°ºO]\.?\s*DE\s+LOT"#,          // FR: N° de lot
            #"FERTIGUNGS-?LOS"#,
            #"LOS-?NUMMER"#,
            #"LOT-?NUMBER"#,
            #"NUMERO\s+DI\s+LOTTO"#,
            #"LOTTO"#,
            #"LOTE"#,
            #"LOT"#,
            #"LOS"#,
            #"CHARGE"#,
            #"CH\.?-?B\."#,                     // Chargenbezeichnung
            #"BATCH"#,
            #"ŠARŽE"#,
            #"L(?=\s*-\s*\d)"#,                // Magtech: "L-6483"
        ]

        /// What may follow a label before the value: "No.", "Nr.", "n.", "#", ":".
        static let labelSuffix = #"\s*[-.]?\s*(?:(?:NO|NR|NUM|N[°º]|N)\b\.?\s*)?[:.#-]?\s*"#

        /// Characters of a lot number. Lots are letters and digits, sometimes with - / .
        static let valueCharacters = #"[A-Z0-9][A-Z0-9\-/.]*"#

        /// Shortest and longest lot number, without separators.
        static let minLength = 3
        static let maxLength = 20

        /// How far below a label (in label heights) its value may be, when it is on its own line.
        static let maxLinesBelow = 2.5

        /// Unlabelled lot formats of known manufacturers, with their score.
        static let knownFormats: [(pattern: String, score: Double)] = [
            (#"^\d{3,5}[/-]\d{2}$"#, 0.7),                     // Sellier & Bellot dot matrix: "1903/44", "1168/60"
            (#"^CBC\d{3,4}/\d{2}$"#, 0.8),                    // Magtech (CBC), top flap: "CBC546/24"
        ]

        /// Lines of only digits and slashes: dot-matrix print, which OCR often spaces out
        /// ("1 9 0 3 / 4 4"). Their spaces are removed before matching.
        static let dotMatrixLine = #"^[\d\s/∕⁄]+$"#

        /// Unlabelled text that is clearly something else: calibres, bullet weights, counts,
        /// velocities, dates' month names and box marketing.
        static let notALot: [String] = [
            #"^\d+([.,]\d+)?X\d+([.,]\d+)?[A-Z]*$"#,     // 9X19, 7.5X55, 5,56X45R
            #"^\d+([.,]\d+)?(MM|GR|GRS|GRAIN|G|M/S|FPS|J|RDS|STK|CART|CAL)$"#,
            #"^(CAL|KAL)\.?\d"#,
            #"^\d{1,3}$"#,                               // shot counts
            #"^\d{8}$|^\d{12,14}$"#,                     // EAN/UPC printed under a barcode
            #"^(D|A|CH|F|I|CZ)-\d{4,5}$"#,              // postal codes: "D-97228"
            #"^(FMJ|JHP|HP|SP|TMJ|FMJFN|LRN|WC|SWC|HPBT|BTHP)\d*$"#,
        ]

        /// Scores per source. A labelled value on the same line beats one on the next line.
        static let gs1Score = 0.95
        static let labelSameLineScore = 0.9
        static let labelNextLineScore = 0.75
        static let barcodeScore = 0.5
        static let guessScore = 0.2
        /// Added when a candidate has the same shape as a lot already saved for this ammo.
        static let sameShapeBonus = 0.3
    }

    /// Ranked lot number candidates, best first, without duplicates. `knownLots` are the lots
    /// already saved for this ammo: candidates of the same shape ("9999/99") rank higher.
    static func candidates(lines: [OCRLine], barcodes: [ScannedBarcode] = [], knownLots: [String] = []) -> [LotCandidate] {
        var found: [LotCandidate] = []
        for code in barcodes {
            found += fromBarcode(code)
        }
        for line in lines {
            if let lot = GS1.lot(inPrinted: line.text) {
                found.append(LotCandidate(number: lot, source: .gs1, score: Rules.gs1Score))
            }
        }
        found += labelled(lines)
        found += guesses(lines)
        let shapes = Set(knownLots.map(LotNumber.shape))
        if !shapes.isEmpty {
            for i in found.indices where shapes.contains(LotNumber.shape(found[i].number)) {
                found[i].score = min(0.99, found[i].score + Rules.sameShapeBonus)
            }
        }
        return ranked(found)
    }

    // MARK: Barcodes

    private static func fromBarcode(_ code: ScannedBarcode) -> [LotCandidate] {
        switch code.kind {
        case .product:
            return []
        case .gs1:
            return GS1.elements(code.payload)["10"].flatMap(cleaned).map {
                [LotCandidate(number: $0, source: .gs1, score: Rules.gs1Score)]
            } ?? []
        case .other:
            // GS1-128 is often reported as plain Code 128. Only trust it with a product number
            // (AI 01) too, so a plain "10…" article code isn't read as a lot.
            let elements = GS1.elements(code.payload)
            if elements["01"] != nil, let lot = elements["10"].flatMap(cleaned) {
                return [LotCandidate(number: lot, source: .gs1, score: Rules.gs1Score)]
            }
            let payload = code.payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let lot = cleaned(payload), !isProductNumber(lot) else { return [] }
            return [LotCandidate(number: lot, source: .barcode, score: Rules.barcodeScore)]
        }
    }

    private static func isProductNumber(_ s: String) -> Bool {
        s.range(of: #"^\d{8}$|^\d{12,14}$"#, options: .regularExpression) != nil
    }

    // MARK: Labels

    private static let labelPattern = "(?:" + Rules.labels.joined(separator: "|") + ")"

    /// "LOT: A2391" on one line, or "LOT" with the value to its right or just below.
    private static func labelled(_ lines: [OCRLine]) -> [LotCandidate] {
        var found: [LotCandidate] = []
        let sameLine = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}])"# + labelPattern + #"(?![A-Z]{3})"# + Rules.labelSuffix + "(" + Rules.valueCharacters + #"(?:\s[A-Z0-9][A-Z0-9\-/.]*)?)"#,
            options: [.caseInsensitive])
        let labelOnly = try? NSRegularExpression(
            pattern: #"^\W*"# + labelPattern + #"(?![A-Z]{3})"# + Rules.labelSuffix + #"$"#, options: [.caseInsensitive])

        for line in lines {
            let text = line.text.uppercased()
            let range = NSRange(text.startIndex..., in: text)
            if labelOnly?.firstMatch(in: text, range: range) != nil {
                if let value = valueNear(line, in: lines) {
                    found.append(LotCandidate(number: value, source: .label, score: Rules.labelNextLineScore))
                }
                continue
            }
            for match in sameLine?.matches(in: text, range: range) ?? [] {
                guard let r = Range(match.range(at: 1), in: text), let value = labelValue(String(text[r])) else { continue }
                found.append(LotCandidate(number: value, source: .label, score: Rules.labelSameLineScore))
            }
        }
        return found
    }

    /// The value after a label: the first word, plus a second one when the first has no digit
    /// ("AB 1234") or is a short prefix ("21 0715").
    private static func labelValue(_ raw: String) -> String? {
        let words = raw.split(separator: " ").map(String.init)
        guard let first = words.first else { return nil }
        if words.count > 1, !first.contains(where: \.isNumber) || first.count <= 2,
           let joined = cleaned(first + " " + words[1]) {
            return joined
        }
        return cleaned(first).flatMap { $0.contains(where: \.isNumber) ? $0 : nil }
    }

    /// The text right of a lone label on the same row, else the nearest line just below it.
    private static func valueNear(_ label: OCRLine, in lines: [OCRLine]) -> String? {
        let height = max(label.height, 0.005)
        let right = lines
            .filter { $0 != label && abs($0.y - label.y) < height * 0.7 && $0.x > label.x + label.width * 0.5 }
            .min { $0.x < $1.x }
        let below = lines
            .filter { $0 != label && $0.y > label.y && $0.y - label.y <= height * Rules.maxLinesBelow
                && $0.x < label.x + label.width + 0.05 && $0.x + $0.width > label.x - 0.05 }
            .min { $0.y < $1.y }
        for line in [right, below].compactMap({ $0 }) {
            if let value = labelValue(line.text.uppercased()) { return value }
        }
        return nil
    }

    // MARK: Guesses

    /// Unlabelled text in a known format ("1903/44"), or words with letters and digits mixed
    /// ("A2391", "21G0715").
    private static func guesses(_ lines: [OCRLine]) -> [LotCandidate] {
        lines.flatMap { line -> [LotCandidate] in
            // Dot-matrix slashes come back as various Unicode slashes, with stray spaces.
            var text = line.text.uppercased()
            if text.range(of: Rules.dotMatrixLine, options: .regularExpression) != nil {
                text = text.filter { !$0.isWhitespace }
            }
            text = text.replacingOccurrences(of: #"\s*[/∕⁄]\s*"#, with: "/", options: .regularExpression)
            return text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" }).compactMap { word -> LotCandidate? in
                guard let value = cleaned(String(word)) else { return nil }
                if let format = Rules.knownFormats.first(where: { value.range(of: $0.pattern, options: .regularExpression) != nil }) {
                    // Not scaled by confidence: dot-matrix print is read with low confidence.
                    return LotCandidate(number: value, source: .guess, score: format.score)
                }
                guard value.contains(where: \.isNumber), value.contains(where: \.isLetter),
                      LotNumber.normalized(value).count >= 4,
                      !Rules.notALot.contains(where: { value.range(of: $0, options: .regularExpression) != nil })
                else { return nil }
                return LotCandidate(number: value, source: .guess, score: Rules.guessScore * line.confidence)
            }
        }
    }

    // MARK: Helpers

    /// Trims punctuation around a value and checks its length; nil if it can't be a lot.
    static func cleaned(_ raw: String) -> String? {
        let trimmed = raw.uppercased()
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let length = LotNumber.normalized(trimmed).count
        guard length >= Rules.minLength, length <= Rules.maxLength,
              trimmed.range(of: #"^[A-Z0-9][A-Z0-9\-/. ]*$"#, options: .regularExpression) != nil
        else { return nil }
        return trimmed
    }

    /// Keeps the best score per lot; ties keep the earlier (more specific) source.
    private static func ranked(_ found: [LotCandidate]) -> [LotCandidate] {
        var best: [String: LotCandidate] = [:]
        var order: [String] = []
        for candidate in found {
            let key = candidate.id
            guard !key.isEmpty else { continue }
            if let existing = best[key] {
                if candidate.score > existing.score { best[key] = candidate }
            } else {
                best[key] = candidate
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element)
    }
}

/// Minimal reader for GS1 element strings ("01…10…" with GS separators).
enum GS1 {
    /// Group separator (FNC1 inside the data).
    static let separator: Character = "\u{1D}"

    /// Fixed data lengths of the AIs found on packaging; all others are variable (up to GS).
    private static let fixedLengths: [String: Int] = [
        "00": 18, "01": 14, "02": 14, "11": 6, "12": 6, "13": 6, "15": 6, "16": 6, "17": 6, "20": 2,
    ]

    /// AI → value. Empty when the payload is not a GS1 element string.
    static func elements(_ payload: String) -> [String: String] {
        var s = Substring(payload)
        for prefix in ["]C1", "]d2", "]e0", "]Q3"] where s.hasPrefix(prefix) { s = s.dropFirst(prefix.count) }
        while s.first == separator { s = s.dropFirst() }
        guard let first = s.first, first.isNumber else { return [:] }
        var result: [String: String] = [:]
        while !s.isEmpty {
            let ai: String
            if let two = fixedLengths.keys.first(where: { s.hasPrefix($0) }) {
                ai = two
            } else if s.hasPrefix("10") || s.hasPrefix("21") || s.hasPrefix("22") || s.hasPrefix("30") || s.hasPrefix("37") {
                ai = String(s.prefix(2))
            } else if s.hasPrefix("240") || s.hasPrefix("241") {
                ai = String(s.prefix(3))
            } else if s.prefix(4).range(of: #"^3[1-6]\d\d$"#, options: .regularExpression) != nil {
                // Measures: a 4-digit AI followed by 6 digits.
                let measure = String(s.prefix(4))
                s = s.dropFirst(4)
                guard s.count >= 6 else { return [:] }
                result[measure] = String(s.prefix(6))
                s = s.dropFirst(6)
                while s.first == separator { s = s.dropFirst() }
                continue
            } else {
                return result["01"] == nil && result["10"] == nil ? [:] : result
            }
            s = s.dropFirst(ai.count)
            let value: Substring
            if let length = fixedLengths[ai] {
                guard s.count >= length else { return [:] }
                value = s.prefix(length); s = s.dropFirst(length)
            } else {
                let end = s.firstIndex(of: separator) ?? s.endIndex
                value = s[..<end]; s = s[end...]
            }
            result[ai] = String(value)
            while s.first == separator { s = s.dropFirst() }
        }
        return result
    }

    /// The lot from printed human-readable GS1 text such as "(01)07612345678900(10)A2391".
    static func lot(inPrinted text: String) -> String? {
        guard let range = text.range(of: #"\(\s*10\s*\)\s*([A-Za-z0-9\-/.]+)"#, options: .regularExpression) else { return nil }
        let value = text[range].replacingOccurrences(of: #"^\(\s*10\s*\)\s*"#, with: "", options: .regularExpression)
        return LotNumberParser.cleaned(value)
    }
}
