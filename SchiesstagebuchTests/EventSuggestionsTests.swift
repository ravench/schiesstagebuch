import XCTest
import SwiftData
@testable import Schiesstagebuch

final class EventSuggestionsTests: XCTestCase {
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    private func suggest(_ query: String, _ history: [(String, Int)], limit: Int = EventSuggestions.defaultLimit) -> [String] {
        EventSuggestions.suggestions(for: query, in: history.map { (event: $0.0, date: day($0.1)) }, limit: limit)
    }

    func testEmptyOrBlankQueryGivesNothing() {
        let history = [("Training", 1), ("Feldschiessen", 2)]
        XCTAssertEqual(suggest("", history), [])
        XCTAssertEqual(suggest("   ", history), [])
    }

    func testMatchingIgnoresCase() {
        let history = [("Feldschiessen", 1), ("Obligatorisches", 2)]
        XCTAssertEqual(suggest("feld", history), ["Feldschiessen"])
        XCTAssertEqual(suggest("FELD", history), ["Feldschiessen"])
        XCTAssertEqual(suggest("oBLiG", history), ["Obligatorisches"])
    }

    func testMatchingIgnoresAccents() {
        XCTAssertEqual(suggest("eve", [("Événement club", 1)]), ["Événement club"])
        XCTAssertEqual(suggest("schützen", [("Schutzenfest", 1)]), ["Schutzenfest"])
    }

    func testPrefixBeforeWordStartBeforeContains() {
        let history = [("Endschiessen", 1), ("Grosses Schiessen", 1), ("Schiessen Training", 1)]
        XCTAssertEqual(suggest("schiess", history), ["Schiessen Training", "Grosses Schiessen", "Endschiessen"])
    }

    func testMoreFrequentThenMoreRecentWins() {
        let history = [("Training A", 1), ("Training B", 2), ("Training B", 3), ("Training C", 9)]
        XCTAssertEqual(suggest("train", history), ["Training B", "Training C", "Training A"])
    }

    func testDifferentCaseCountsAsOneNameShownInLatestSpelling() {
        let history = [("training", 1), ("Training", 5), ("TRAINING", 3), ("Trainingslager", 9)]
        XCTAssertEqual(suggest("tr", history), ["Training", "Trainingslager"])
    }

    func testExactMatchIsNotSuggested() {
        let history = [("Training", 1), ("Trainingslager", 2)]
        XCTAssertEqual(suggest("training", history), ["Trainingslager"])
        XCTAssertEqual(suggest("Trainingslager", history), [])
    }

    func testBlankEventsAndWhitespaceAreIgnored() {
        XCTAssertEqual(suggest("t", [("", 1), ("  ", 2), (" Training ", 3)]), ["Training"])
    }

    func testLimit() {
        let history = (1...10).map { ("Match \($0)", $0) }
        XCTAssertEqual(suggest("match", history).count, EventSuggestions.defaultLimit)
        XCTAssertEqual(suggest("match", history, limit: 2), ["Match 10", "Match 9"])
        XCTAssertEqual(suggest("match", history, limit: 0), [])
    }

    func testNoMatch() {
        XCTAssertEqual(suggest("xyz", [("Training", 1)]), [])
    }
}

/// The event-based overload reads name and date from saved events.
final class EventSuggestionsEventTests: ModelTestCase {
    func testSuggestsFromEvents() throws {
        context.insert(ShootingEvent(date: Date(timeIntervalSince1970: 0), name: "Feldschiessen"))
        context.insert(ShootingEvent(date: Date(timeIntervalSince1970: 86_400), name: "feldschiessen"))
        context.insert(ShootingEvent(date: Date(timeIntervalSince1970: 0), name: "Training"))
        try context.save()
        let events = try context.fetch(FetchDescriptor<ShootingEvent>())
        XCTAssertEqual(EventSuggestions.suggestions(for: "FELD", in: events), ["feldschiessen"])
    }

    func testAnEventWithSeveralSticheCountsOnce() throws {
        // Three Stiche at one Schützenfest must not outrank two separate Feldschiessen.
        let fest = ShootingEvent(date: Date(timeIntervalSince1970: 172_800), name: "Schützenfest")
        context.insert(fest)
        for _ in 0..<3 {
            let stich = Entry()
            context.insert(stich)
            fest.add(stich)
        }
        for day in 0..<2 {
            context.insert(ShootingEvent(date: Date(timeIntervalSince1970: Double(day) * 86_400), name: "Schützenhaus Cup"))
        }
        try context.save()
        let events = try context.fetch(FetchDescriptor<ShootingEvent>())
        XCTAssertEqual(EventSuggestions.suggestions(for: "schütz", in: events), ["Schützenhaus Cup", "Schützenfest"])
    }
}
