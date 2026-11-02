import XCTest
@testable import Schiesstagebuch

/// Fixtures are transcribed from real Standblätter (photos in the pull request). Arrows are
/// written the way OCR tends to return them: as odd symbols, letters or a stray digit.
final class StandblattParserTests: XCTestCase {

    // MARK: Fixture helpers

    /// Lays out one strip as Vision reports it: the original column at `x`, the copy column
    /// (every line ending in "K") at `x + gap`, one row every `step`.
    private func strip(_ rows: [String], x: Double, top: Double, gap: Double = 0.14, step: Double = 0.025,
                       copyK: Bool = true) -> [OCRLine] {
        var lines: [OCRLine] = []
        for (i, row) in rows.enumerated() {
            let y = top + Double(i) * step
            let indent = row.hasPrefix("Subtota") || row.hasPrefix("Total") ? -0.01 : 0
            lines.append(OCRLine(text: row, x: x + indent, y: y, width: 0.1))
            lines.append(OCRLine(text: copyK ? row + " K" : row, x: x + gap + indent, y: y, width: 0.1))
        }
        return lines
    }

    private func line(_ text: String, x: Double, y: Double, width: Double = 0.1, height: Double = 0.015,
                      confidence: Double = 0.9) -> OCRLine {
        OCRLine(text: text, x: x, y: y, width: width, height: height, confidence: confidence)
    }

    private func components(_ date: Date?) -> DateComponents? {
        date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
    }

    private func rings(_ s: ScannedStandblatt) -> [[Int]] { s.passes.map { $0.shots.compactMap(\.ring) } }
    private func hundredths(_ s: ScannedStandblatt) -> [[Int]] { s.passes.map { $0.shots.compactMap(\.hundredths) } }

    // MARK: IMG_5395 – Eröffnungsschiessen, two shooters' strips side by side

    private var eroeffnung: [OCRLine] {
        var page: [OCRLine] = []
        for (x, rows) in [(0.24, [
            "Scheibe 2/50", "11.4.2026 10:22", "A10 Benutzerprogra",
            "1 ↖ 10 92", "2 † 10 95", "3 + 9 89", "4 ✓ 7 69", "5 ← 10 95",
            "6 L 9 84", "7 y 10 93", "8 4 9 82", "9 ↙ 8 80", "10 7 9 87",
            "Subtota 91 866", "Total 91 866",
        ]), (0.54, [
            "Scheibe 2/48", "11.4.2026 09:41", "A10 Benutzerprogra",
            "1 ↗ 9 85", "2 ↘ 9 86", "3 ↑ 10 92", "4 ↑ 10# 96", "5 ↖ 9 84",
            "6 ↖ 9 87", "7 ↘ 9 82", "8 ↘ 8 77", "9 ↓ 8 79", "10 → 9 85",
            "Subtota 90 853", "Total 90 853",
        ])] {
            page += strip(rows, x: x, top: 0.375)
            page += [
                line("Gruppen-Stich 1", x: x + 0.04, y: 0.045),
                line("Schützengesellschaft der Stadt Zürich", x: x + 0.08, y: 0.11, width: 0.2, height: 0.02),
                line("Eröffnungsschiessen", x: x + 0.01, y: 0.15, width: 0.2, height: 0.022),
                line("Gruppen-Stich 1", x: x + 0.01, y: 0.175, height: 0.016),
                line("A10 / Probe Frei / 10E", x: x + 0.01, y: 0.19, width: 0.15, height: 0.016),
                line("Standard 57/03 57/02", x: x + 0.01, y: 0.21, width: 0.2, height: 0.016),
                line("Kar 90", x: x + 0.01, y: 0.225, height: 0.016),
                line("Simon Giotta", x: x + 0.03, y: 0.25, height: 0.03, confidence: 0.3),
            ]
        }
        // Handwritten sums below the right strip must not become shots.
        page += [line("84", x: 0.62, y: 0.64), line("88", x: 0.73, y: 0.64),
                 line("140 133", x: 0.6, y: 0.71), line("306 308", x: 0.6, y: 0.79)]
        return page
    }

    func testEroeffnungsschiessenTwoStripsSideBySide() throws {
        let strips = StandblattParser.parse(pages: [eroeffnung])
        XCTAssertEqual(strips.count, 2)
        let mine = try XCTUnwrap(strips.first)
        XCTAssertEqual(mine.title, "Eröffnungsschiessen")
        XCTAssertEqual(mine.details, ["Gruppen-Stich 1", "A10 / Probe Frei / 10E"])
        XCTAssertEqual(mine.scheibe, "2/50")
        XCTAssertEqual(components(mine.date), DateComponents(year: 2026, month: 4, day: 11, hour: 10, minute: 22))
        XCTAssertEqual(mine.target, .a10)
        XCTAssertEqual(rings(mine), [[10, 10, 9, 7, 10, 9, 10, 9, 8, 9]])
        XCTAssertEqual(hundredths(mine), [[92, 95, 89, 69, 95, 84, 93, 82, 80, 87]])
        XCTAssertEqual(mine.total(.rings), 91)
        XCTAssertEqual(mine.total(.hundredths), 866)
        XCTAssertEqual(mine.issues(.rings), [])
        XCTAssertEqual(mine.issues(.hundredths), [])
        XCTAssertEqual(mine.innerTens, 0)

        let other = strips[1]
        XCTAssertEqual(other.scheibe, "2/48")
        XCTAssertEqual(other.innerTens, 1)
        XCTAssertEqual(other.sum(.rings), 90)
        XCTAssertEqual(other.sum(.hundredths), 853)
        XCTAssertEqual(other.shots.count, 10, "handwritten sums under the strip are ignored")
        XCTAssertEqual(other.issues(.rings), [])
    }

    // MARK: IMG_5477 – four programs on one photo, with repeats and an A100 strip

    private var vierStiche: [OCRLine] {
        var page: [OCRLine] = []
        page += strip(["Scheibe 8/5", "2.5.2026 08:42", "A10 Benutzerprogra",
                       "1 ← 8 78", "2 ↙ 10# 98", "3 ↙ 9 87", "4 ↖ 10 92", "5 ↖ 9 82", "6 ↗ 10* 96",
                       "Subtota 56 533",
                       "7 ↗ 10 91", "8 → 9 82", "9 ↗ 10 93", "10 ↓ 10 93", "( 9 ↗ 10 93)",
                       "Subtota 39 359", "Total 95 892"], x: 0.06, top: 0.35, gap: 0.12)
        page += strip(["Scheibe 8/1", "2.5.2026 08:14", "A10 Benutzerprogra",
                       "1 ↗ 7 70", "2 ↖ 9 88", "3 ↖ 9 83", "4 ↗ 9 87", "5 ↗ 10 92", "6 ↗ 10# 99",
                       "7 ← 9 81", "8 ↘ 9 81", "9 ↗ 10 94", "10 ↙ 9 87",
                       "Subtota 91 862",
                       "11 ↖ 10# 99", "12 ↙ 7 65", "13 ← 10 92", "14 ↘ 9 87", "15 ↘ 8 75", "( 11 ↖ 10# 99)",
                       "Subtota 44 418", "Total 135 1280"], x: 0.33, top: 0.34, gap: 0.11)
        page += strip(["Scheibe 8/2", "2.5.2026 08:24", "A10 Benutzerprogra",
                       "1 ↘ 89", "2 ↗ 83", "3 ↘ 82", "4 ↘ 90", "5 → 86",
                       "Subtota 430", "Total 430"], x: 0.56, top: 0.33, gap: 0.1)
        page += strip(["Scheibe 8/4", "2.5.2026 08:35", "A10 Benutzerprogra",
                       "1 → 9 90", "2 ↘ 9 81", "3 ↗ 9 85", "4 → 8 79", "5 → 10 91", "6 ↘ 8 74", "( 5 → 10 91)",
                       "Subtota 53 500", "Total 53 500"], x: 0.79, top: 0.36, gap: 0.09)
        page += [
            line("A10", x: 0.15, y: 0.11, width: 0.03),
            line("Schützengesellschaft der Stadt Zürich", x: 0.08, y: 0.15, width: 0.2),
            line("Name: Giotta Simon", x: 0.08, y: 0.17, width: 0.2, confidence: 0.3),
            line("Sektion", x: 0.14, y: 0.21, width: 0.06, height: 0.025),
            line("Alle Waffen", x: 0.14, y: 0.23, width: 0.06),
            line("6 EF, 4 SF in 60 Sek. ab 1. Schuss", x: 0.08, y: 0.25, width: 0.2),
            line("GM-Stich", x: 0.40, y: 0.21, width: 0.07, height: 0.025),
            line("Armeewaffen", x: 0.40, y: 0.23, width: 0.07),
            line("10 EF, 5 SF in 60 Sek. ab 1. Schuss", x: 0.33, y: 0.25, width: 0.2),
            line("A100", x: 0.63, y: 0.12, width: 0.03),
            line("Kunst", x: 0.63, y: 0.21, width: 0.05, height: 0.025),
            line("Alle Waffen", x: 0.62, y: 0.23, width: 0.07),
            line("Schnellstich", x: 0.84, y: 0.24, width: 0.09, height: 0.025),
            line("Armeewaffen", x: 0.84, y: 0.26, width: 0.08),
            line("6 EF in 60 Sek. ab 1. Schuss", x: 0.80, y: 0.28, width: 0.16),
        ]
        return page
    }

    func testFourProgramsOnOnePhoto() throws {
        let strips = StandblattParser.parse(pages: [vierStiche])
        XCTAssertEqual(strips.map(\.title), ["Sektion", "GM-Stich", "Kunst", "Schnellstich"])

        let sektion = strips[0]
        XCTAssertEqual(sektion.details, ["Alle Waffen", "6 EF, 4 SF in 60 Sek. ab 1. Schuss"])
        XCTAssertEqual(rings(sektion), [[8, 10, 9, 10, 9, 10], [10, 9, 10, 10]])
        XCTAssertEqual(sektion.passes.map(\.printedRings), [56, 39])
        XCTAssertEqual(sektion.passes.map(\.printedHundredths), [533, 359])
        XCTAssertEqual(sektion.repeats, 1, "the bracketed repeat of shot 9 does not count")
        XCTAssertEqual(sektion.innerTens, 2)
        XCTAssertEqual(sektion.total(.rings), 95)
        XCTAssertEqual(sektion.total(.hundredths), 892)
        XCTAssertEqual(sektion.issues(.rings), [])
        XCTAssertEqual(components(sektion.date), DateComponents(year: 2026, month: 5, day: 2, hour: 8, minute: 42))

        let gm = strips[1]
        XCTAssertEqual(gm.passes.map(\.shots.count), [10, 5])
        XCTAssertEqual(gm.repeats, 1)
        XCTAssertEqual(gm.sum(.rings), 135)
        XCTAssertEqual(gm.sum(.hundredths), 1280)
        XCTAssertEqual(gm.issues(.hundredths), [])

        let kunst = strips[2]
        XCTAssertEqual(kunst.target, .a100)
        XCTAssertEqual(kunst.availableScorings, [.hundredths])
        XCTAssertEqual(kunst.defaultScoring, .hundredths)
        XCTAssertEqual(hundredths(kunst), [[89, 83, 82, 90, 86]])
        XCTAssertEqual(kunst.total(.hundredths), 430)
        XCTAssertEqual(kunst.maxPoints(.hundredths), 500)
        XCTAssertEqual(kunst.issues(.hundredths), [])

        let schnell = strips[3]
        XCTAssertEqual(rings(schnell), [[9, 9, 9, 8, 10, 8]])
        XCTAssertEqual(schnell.repeats, 1)
        XCTAssertEqual(schnell.total(.rings), 53)
        XCTAssertEqual(schnell.issues(.rings), [])
    }

    // MARK: IMG_5900 + IMG_5901 – 60 shots over two photos

    private let match1to30 = [
        "1 ↙ 10 95", "2 ↖ 10 95", "3 ↙ 10 92", "4 ↗ 8 79", "5 ← 10# 98",
        "6 ↗ 10# 96", "7 ↑ 10# 97", "8 ↗ 9 88", "9 → 9 87", "10 → 9 84", "Subtota 95 911",
        "11 ↗ 10 94", "12 ↑ 8 75", "13 ← 10 94", "14 ↑ 8 77", "15 ↖ 9 88",
        "16 ↗ 8 80", "17 ↗ 9 85", "18 ↗ 8 74", "19 ↗ 9 83", "20 ↗ 10# 99", "Subtota 89 849",
        "21 ↙ 9 86", "22 ↖ 9 88", "23 ↗ 7 63", "24 ↗ 8 72", "25 ↗ 9 85",
        "26 ↗ 8 73", "27 ↗ 9 84", "28 → 7 66", "29 ↗ 6 53", "30 ↗ 10# 97", "Subtota 82 767",
    ]
    private let match31to60 = [
        "31 ↙ 10# 96", "32 ↗ 10 92", "33 ↗ 8 75", "34 ↙ 10# 97", "35 ↗ 9 88",
        "36 ↘ 10 95", "37 ↘ 9 84", "38 ↘ 7 67", "39 ↘ 9 87", "40 ↑ 9 82", "Subtota 91 863",
        "41 ↓ 8 78", "42 ↖ 10# 97", "43 ↓ 10 94", "44 ↘ 1O 94", "45 ↙ 9 89",
        "46 ↘ 10 95", "47 ↙ 9 87", "48 ↘ 9 84", "49 ↙ 9 90", "50 ↘ 8 76", "Subtota 92 884",
        "51 ↘ 10# 98", "52 ↙ 10 94", "53 ↖ 10 95", "54 ↘ 10 95", "55 ↘ 9 90",
        "56 ↖ 10 91", "57 ↖ 9 89", "58 ↙ 9 89", "59 → 10# 97", "60 ↘ 9 89", "Subtota 96 927",
        "Total 545 5201",
    ]

    func testGesellschaftsmatchOverTwoPhotos() throws {
        var first = strip(["Scheibe 9/8", "11.7.2026 10:07", "A10 Benutzerprogra"] + match1to30, x: 0.31, top: 0.28, gap: 0.16)
        first += [
            line("60001000873443", x: 0.43, y: 0.08),
            line("Schützengesellschaft der Stadt Zürich", x: 0.32, y: 0.1, width: 0.3),
            line("Gesellschaftsmatch", x: 0.36, y: 0.17, width: 0.2, height: 0.022),
            line("Armeewaffen", x: 0.42, y: 0.19, width: 0.1),
            line("Liegend-Meisterschaft", x: 0.37, y: 0.205, width: 0.19, height: 0.016),
        ]
        var second = strip(match31to60, x: 0.34, top: 0.25, gap: 0.18)
        // OCR lost one K in the copy column: the column is still recognised as the copy.
        if let i = second.firstIndex(where: { $0.text == "47 ↙ 9 87 K" }) { second[i].text = "47 ↙ 9 87" }

        let strips = StandblattParser.parse(pages: [first, second])
        XCTAssertEqual(strips.count, 1)
        let match = try XCTUnwrap(strips.first)
        XCTAssertEqual(match.title, "Gesellschaftsmatch")
        XCTAssertEqual(match.details, ["Armeewaffen", "Liegend-Meisterschaft"])
        XCTAssertEqual(match.shots.map(\.number), Array(1...60))
        XCTAssertEqual(match.passes.count, 6)
        XCTAssertEqual(match.passes.map(\.printedRings), [95, 89, 82, 91, 92, 96])
        XCTAssertEqual(match.innerTens, 10)
        XCTAssertEqual(match.total(.rings), 545)
        XCTAssertEqual(match.total(.hundredths), 5201)
        XCTAssertEqual(match.maxPoints(.rings), 600)
        XCTAssertEqual(match.issues(.rings), [])
        XCTAssertEqual(match.issues(.hundredths), [])
        XCTAssertEqual(components(match.date), DateComponents(year: 2026, month: 7, day: 11, hour: 10, minute: 7))
    }

    // MARK: IMG_6093 – Säulimatch strip next to an SSM card

    func testSaeulimatchAndSektionsmeisterschaft() throws {
        var page = strip(["Scheibe 4/9", "13.8.2026 17:47", "A10 Benutzerprogra",
                          "1 ≠ 9 85", "2 \\ 10 91", "3 ≠ 10# 98", "4 ↖ 10 92", "5 \\ 9 90",
                          "6 ↖ 10# 99", "7 ≠ 10 91", "8 ≠ 9 85", "9 \\ 8 75", "10 ≠ 9 85", "Subtota 94 891",
                          "11 \\ 8 75", "12 ↑ 9 89", "13 ↖ 8 72", "14 ≠ 10 91", "15 ≠ 10 94",
                          "16 ↓ 10 91", "17 ↖ 9 81", "18 ↖ 8 76", "19 ↖ 10 92", "20 ↖ 10 93", "Subtota 92 854",
                          "21 \\ 9 90", "22 ≠ 10 95", "23 \\ 9 85", "24 \\ 10 91", "25 \\ 8 74",
                          "26 \\ 9 86", "27 ↖ 9 89", "28 ≠ 10# 97", "29 \\ 10 94", "30 \\ 8 78", "Subtota 92 879",
                          "Total 278 2624"], x: 0.21, top: 0.27, gap: 0.15, step: 0.0135)
        page += strip(["Scheibe 4/8", "13.8.2026 17:28", "A10 Benutzerprogra",
                       "1 \\ 8 78", "2 ↖ 10 92", "3 ≠ 9 84", "4 ↓ 10 94", "5 ≠ 10 94",
                       "6 \\ 8 80", "7 \\ 9 88", "8 → 8 80", "9 \\ 8 75", "10 ≠ 9 90",
                       "Subtota 89 855", "Total 89 855"], x: 0.51, top: 0.30, gap: 0.15, step: 0.0135)
        page += [
            line("7000050003098191242б6(12)", x: 0.22, y: 0.085, width: 0.2),
            line("Säulimatch", x: 0.22, y: 0.15, width: 0.1, height: 0.02),
            line("Stich", x: 0.22, y: 0.178, width: 0.04),
            line("A10 / 30 EF", x: 0.32, y: 0.178, width: 0.09),
            line("Doppel", x: 0.22, y: 0.19, width: 0.05),
            line("Fr. 5.00", x: 0.32, y: 0.19, width: 0.06),
            line("Schweizer Sektionsmeisterschaft 300m", x: 0.56, y: 0.17, width: 0.22, height: 0.015),
            line("Championnat suisse de sections 300m", x: 0.56, y: 0.185, width: 0.22, height: 0.014),
            line("Scheibe A10, 10 EF, einzeln gezeigt", x: 0.51, y: 0.21, width: 0.25, height: 0.012),
            line("Cible A10, 10 coups, c.p.c., marqués individuellement", x: 0.51, y: 0.22, width: 0.25, height: 0.012),
            line("Lizenznummer", x: 0.52, y: 0.61, width: 0.1),
            line("Datum", x: 0.52, y: 0.70, width: 0.05),
        ]

        let strips = StandblattParser.parse(pages: [page])
        XCTAssertEqual(strips.map(\.title), ["Säulimatch", "Schweizer Sektionsmeisterschaft 300m"])

        let saeuli = strips[0]
        XCTAssertTrue(saeuli.details.contains("A10 / 30 EF"))
        XCTAssertEqual(saeuli.passes.map(\.shots.count), [10, 10, 10])
        XCTAssertEqual(saeuli.innerTens, 3)
        XCTAssertEqual(saeuli.total(.rings), 278)
        XCTAssertEqual(saeuli.total(.hundredths), 2624)
        XCTAssertEqual(saeuli.issues(.rings), [])

        let ssm = strips[1]
        XCTAssertEqual(ssm.details, ["Scheibe A10, 10 EF, einzeln gezeigt", "Cible A10, 10 coups, c.p.c., marqués individuellement"])
        XCTAssertEqual(ssm.scheibe, "4/8")
        XCTAssertEqual(components(ssm.date), DateComponents(year: 2026, month: 8, day: 13, hour: 17, minute: 28))
        XCTAssertEqual(rings(ssm), [[8, 10, 9, 10, 10, 8, 9, 8, 8, 9]])
        XCTAssertEqual(ssm.total(.rings), 89)
        XCTAssertEqual(ssm.issues(.hundredths), [])
    }

    // MARK: IMG_6194 – handwritten Rehalp sheet

    func testHandwrittenRehalpSheet() throws {
        let page = [
            line("SSG Neumünster Zürich", x: 0.46, y: 0.12, width: 0.4, height: 0.02),
            line("Rehalp-Schiessen 2026", x: 0.45, y: 0.19, width: 0.42, height: 0.025),
            line("Simon Giotta", x: 0.39, y: 0.31, width: 0.14),
            line("34363", x: 0.22, y: 0.36, width: 0.07),
            line("1996 OP 9", x: 0.39, y: 0.40, width: 0.12),
            line("Fr. 36.00", x: 0.77, y: 0.40, width: 0.1),
            line("Übungskehr EF Scheibe P-10", x: 0.15, y: 0.53, width: 0.33, height: 0.016),
            line("9", x: 0.16, y: 0.58, width: 0.03, confidence: 0.5),
            line("10", x: 0.21, y: 0.58, width: 0.04, confidence: 0.5),
            line("Vereinsstich EF Scheibe P-10", x: 0.14, y: 0.64, width: 0.33, height: 0.016),
            line("Auszeichnung ab 85 P. [ ] KA [ ] KK", x: 0.52, y: 0.645, width: 0.4),
            line("10 6 10 8 2 10", x: 0.14, y: 0.70, width: 0.33, confidence: 0.4),
            line("7 10.10 9", x: 0.5, y: 0.70, width: 0.2, confidence: 0.4),
            line("82", x: 0.75, y: 0.70, width: 0.06, confidence: 0.5),
            line("Auszahlungsstich EF Scheibe P-100", x: 0.13, y: 0.75, width: 0.4, height: 0.016),
            line("Auszahlung ab 330 P.", x: 0.67, y: 0.76, width: 0.25),
            line("8692 89 93", x: 0.12, y: 0.81, width: 0.25, confidence: 0.4),
            line("360", x: 0.38, y: 0.81, width: 0.08, confidence: 0.5),
            line("Exemplar für Schütze", x: 0.65, y: 0.95, width: 0.25),
        ]
        let strips = StandblattParser.parse(pages: [page])
        XCTAssertEqual(strips.map(\.title), ["Übungskehr EF", "Vereinsstich EF", "Auszahlungsstich EF"])
        XCTAssertTrue(strips.allSatisfy(\.handwritten))
        XCTAssertEqual(strips[0].details, ["Rehalp-Schiessen 2026"])

        XCTAssertEqual(rings(strips[0]), [[9, 10]])
        XCTAssertNil(strips[0].printedRings)

        let verein = strips[1]
        XCTAssertEqual(verein.target, .p10)
        XCTAssertEqual(rings(verein), [[10, 6, 10, 8, 2, 10, 7, 10, 10, 9]])
        XCTAssertEqual(verein.printedRings, 82)
        XCTAssertEqual(verein.issues(.rings), [])

        let auszahlung = strips[2]
        XCTAssertEqual(auszahlung.target, .p100)
        XCTAssertEqual(auszahlung.defaultScoring, .hundredths)
        XCTAssertEqual(hundredths(auszahlung), [[86, 92, 89, 93]], "merged boxes are split again")
        XCTAssertEqual(auszahlung.total(.hundredths), 360)
        XCTAssertEqual(auszahlung.issues(.hundredths), [])
    }

    // MARK: Plain text and single rows

    func testPlainTextWithMergedColumns() throws {
        // Both columns on one line, as OCR sometimes returns them.
        let text = """
        Scheibe 8/4      Scheibe 8/4 K
        2.5.2026 08:35   2.5.2026 08:35 K
        1 → 9 90   1 → 9 90 K
        2 ↘ 9 81   2 ↘ 9 81 K
        3 ↗ 9 85   3 ↗ 9 85 K
        4 → 8 79   4 → 8 79 K
        5 → 10 91  5 → 10 91 K
        6 ↘ 8 74   6 ↘ 8 74 K
        ( 5 → 10 91)  ( 5 → 10 91) K
        Subtota 53 500  Subtota 53 500 K
        Total 53 500  Total 53 500 K
        """
        let strips = StandblattParser.parse(text: text)
        XCTAssertEqual(strips.count, 1)
        XCTAssertEqual(rings(strips[0]), [[9, 9, 9, 8, 10, 8]])
        XCTAssertEqual(strips[0].repeats, 1)
        XCTAssertEqual(strips[0].printedRings, 53)
        XCTAssertEqual(strips[0].printedHundredths, 500)
    }

    func testPlainTextSkipsCopyLines() {
        let text = """
        Scheibe 8/2
        Scheibe 8/2 K
        1 ↘ 89
        1 ↘ 89 K
        2 ↗ 83
        2 ↗ 83 K
        Subtota 172
        Subtota 172 K
        Total 172
        """
        let strips = StandblattParser.parse(text: text)
        XCTAssertEqual(strips.count, 1)
        XCTAssertEqual(hundredths(strips[0]), [[89, 83]])
        XCTAssertEqual(strips[0].target, .a100)
    }

    func testShotRows() throws {
        let plain = try XCTUnwrap(StandblattParser.shot("4 ↑ 10# 96"))
        XCTAssertEqual(plain.number, 4)
        XCTAssertEqual(plain.values, [10, 96])
        XCTAssertTrue(plain.innerTen)
        XCTAssertFalse(plain.copy)

        // Arrow misread as a digit, OCR letter-for-digit swaps.
        XCTAssertEqual(StandblattParser.shot("8 4 9 82")?.values, [4, 9, 82])
        XCTAssertEqual(StandblattParser.shot("l2 ↙ 7 6S")?.number, 12)
        XCTAssertEqual(StandblattParser.shot("l2 ↙ 7 6S")?.values, [7, 65])

        XCTAssertTrue(try XCTUnwrap(StandblattParser.shot("( 9 ↗ 10 93)")).bracketed)
        XCTAssertTrue(try XCTUnwrap(StandblattParser.shot("1 ↖ 10 92 K")).copy)
        XCTAssertTrue(try XCTUnwrap(StandblattParser.shot("1 ↖ 10 92K")).copy)
        XCTAssertTrue(try XCTUnwrap(StandblattParser.shot("6 ↗ 10 # 96")).innerTen)

        let merged = try XCTUnwrap(StandblattParser.shot("10 ↗ 10 95   10 ↗ 10 95 K"))
        XCTAssertEqual(merged.values, [10, 95])
        XCTAssertFalse(merged.copy)

        XCTAssertNil(StandblattParser.shot("6 EF, 4 SF in 60 Sek. ab 1. Schuss"))
        XCTAssertNil(StandblattParser.shot("1996 OP 9"))
        XCTAssertNil(StandblattParser.shot("Fr. 36.00"))
        XCTAssertNil(StandblattParser.shot("57/03 57/02"))
    }

    func testRecordKinds() {
        XCTAssertEqual(StandblattParser.record("Scheibe 2/50"), .header(scheibe: "2/50", copy: false))
        XCTAssertEqual(StandblattParser.record("Scheibe 2/50 K"), .header(scheibe: "2/50", copy: true))
        XCTAssertEqual(StandblattParser.record("Scheibe A10, 10 EF, einzeln gezeigt"), .other)
        XCTAssertEqual(StandblattParser.record("Subtota 91 866"), .subtotal([91, 866], copy: false))
        XCTAssertEqual(StandblattParser.record("5ubtota 9l 866 K"), .subtotal([91, 866], copy: true))
        XCTAssertEqual(StandblattParser.record("Total 135 1280"), .total([135, 1280], copy: false))
        XCTAssertEqual(StandblattParser.record("A10 Benutzerprogra"), .other)
    }

    func testDates() {
        XCTAssertEqual(components(StandblattParser.date(in: "13.8.2026 17:47")),
                       DateComponents(year: 2026, month: 8, day: 13, hour: 17, minute: 47))
        XCTAssertEqual(components(StandblattParser.date(in: "2.5.2026 08.14 K")),
                       DateComponents(year: 2026, month: 5, day: 2, hour: 8, minute: 14))
        XCTAssertEqual(components(StandblattParser.date(in: "11.4.2026"))?.day, 11)
        XCTAssertNil(StandblattParser.date(in: "45.13.2026 10:00"))
    }

    func testRingFromHundredths() {
        XCTAssertEqual(StandblattParser.ring(forHundredths: 100), 10)
        XCTAssertEqual(StandblattParser.ring(forHundredths: 91), 10)
        XCTAssertEqual(StandblattParser.ring(forHundredths: 90), 9)
        XCTAssertEqual(StandblattParser.ring(forHundredths: 81), 9)
        XCTAssertEqual(StandblattParser.ring(forHundredths: 80), 8)
        XCTAssertEqual(StandblattParser.ring(forHundredths: 53), 6)
        XCTAssertEqual(StandblattParser.ring(forHundredths: 0), 0)
    }

    func testMisreadRingIsFlaggedAndSumsDisagree() throws {
        let text = """
        Scheibe 1/1
        1 ↖ 10 92
        2 ↖ 8 95
        3 ↖ 9 89
        Subtota 29 276
        Total 29 266
        """
        let s = try XCTUnwrap(StandblattParser.parse(text: text).first)
        XCTAssertEqual(rings(s), [[10, 10, 9]], "the hundredths decide the ring")
        XCTAssertEqual(s.issues(.rings), [.uncertainShots([2])])
        XCTAssertEqual(s.issues(.hundredths), [.totalMismatch(printed: 266, read: 276)])
    }

    func testMissingShotIsReported() throws {
        let text = """
        Scheibe 1/1
        1 ↖ 10 92
        3 ↖ 9 89
        Total 19 181
        """
        let s = try XCTUnwrap(StandblattParser.parse(text: text).first)
        XCTAssertEqual(s.issues(.rings), [.missingShots([2])])
    }

    func testCopyHeadersWithoutK() {
        // OCR lost every K: the right one of each pair of headers on a row is the copy.
        var page = strip(["Scheibe 8/1", "1 ↗ 7 70", "2 ↖ 9 88", "Total 16 158"], x: 0.1, top: 0.3, copyK: false)
        page += strip(["Scheibe 8/2", "1 ↘ 89", "2 ↗ 83", "Total 172"], x: 0.5, top: 0.3, copyK: false)
        let strips = StandblattParser.parse(pages: [page])
        XCTAssertEqual(strips.map(\.shots.count), [2, 2])
        XCTAssertEqual(strips.map(\.target), [.a10, .a100])
    }

    func testNoStripGivesNothing() {
        XCTAssertEqual(StandblattParser.parse(pages: [[line("Einkaufsliste", x: 0.1, y: 0.1)]]), [])
        XCTAssertEqual(StandblattParser.parse(text: "1 ↖ 10 92\n2 ↖ 10 95"), [], "rows need a Scheibe header")
    }

    func testHandwrittenSplit() {
        XCTAssertEqual(HandwrittenParser.split(["10", "6", "1010", "9", "82"], max: 10).values, [10, 6, 10, 10, 9])
        XCTAssertEqual(HandwrittenParser.split(["10", "6", "1010", "9", "82"], max: 10).total, 82)
        XCTAssertEqual(HandwrittenParser.split(["8692", "100", "360"], max: 100).values, [86, 92, 100])
        XCTAssertNil(HandwrittenParser.split(["9", "10"], max: 10).total)
    }

    // MARK: Import into the editor

    func testImportUsesRingsOrHundredths() throws {
        let sektion = StandblattParser.parse(pages: [vierStiche])[0]

        let rings = StandblattImport(sektion, scoring: .rings)
        XCTAssertEqual(rings.event, "Sektion")
        XCTAssertEqual(rings.passes, ["8 10 9 10 9 10", "10 9 10 10"])
        XCTAssertEqual(rings.result, "95")
        XCTAssertEqual(rings.maxPoints, 100)
        XCTAssertNotNil(rings.date)
        XCTAssertTrue(rings.notes.contains("8/5"))
        XCTAssertTrue(rings.notes.contains("A100: 892"))

        let hundredths = StandblattImport(sektion, scoring: .hundredths, event: " Sektionsstich ")
        XCTAssertEqual(hundredths.event, "Sektionsstich")
        XCTAssertEqual(hundredths.passes, ["78 98 87 92 82 96", "91 82 93 93"])
        XCTAssertEqual(hundredths.result, "892")
        XCTAssertEqual(hundredths.maxPoints, 1000)
        XCTAssertTrue(hundredths.notes.contains("A10: 95"))

        // The imported passes read back as the same score in the entry.
        let score = Score(result: rings.result, maxPoints: rings.maxPoints,
                          shotValuesText: Score.joinPasses(rings.passes), scoredShots: 10)
        XCTAssertEqual(score.shotValues.reduce(0, +), 95)
        XCTAssertEqual(score.percentage!, 0.95, accuracy: 1e-9)
    }

    func testTotalAboveMaximumIsReported() throws {
        let text = """
        Scheibe 1/1
        1 ↖ 10 92
        2 ↖ 9 89
        Total 29 181
        """
        let s = try XCTUnwrap(StandblattParser.parse(text: text).first)
        XCTAssertEqual(s.issues(.rings), [.totalMismatch(printed: 29, read: 19), .exceedsMax(total: 29, max: 20)])
        XCTAssertEqual(s.issues(.hundredths), [])
    }
}
