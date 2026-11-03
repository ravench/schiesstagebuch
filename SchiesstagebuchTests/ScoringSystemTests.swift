import XCTest
import SwiftData
@testable import Schiesstagebuch

final class ScoringSystemTests: ModelTestCase {
    private var defaults: UserDefaults!
    private let suite = "ScoringSystemTests"

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        try await super.tearDown()
    }

    // MARK: Switching systems on and off

    func testOnlyPointsAreOnByDefault() {
        XCTAssertEqual(ScoringSystem.stored(in: defaults), [.rings])
        XCTAssertEqual(ScoringSystem.enabled(from: ""), [.rings])
        XCTAssertEqual(ScoringSystem.enabled(from: "darts,,"), [.rings], "unknown names are dropped")
    }

    func testStoredListKeepsDeclarationOrder() {
        XCTAssertEqual(ScoringSystem.enabled(from: "ipsc,rings"), [.rings, .ipsc])
        XCTAssertEqual(ScoringSystem.raw([.ipsc, .rings]), "rings,ipsc")
        defaults.set("ipsc", forKey: ScoringSystem.enabledKey)
        XCTAssertEqual(ScoringSystem.stored(in: defaults), [.ipsc])
    }

    func testSwitchingOnAndOff() {
        var raw = ""
        raw = ScoringSystem.setting(.ipsc, true, in: raw)
        XCTAssertEqual(ScoringSystem.enabled(from: raw), [.rings, .ipsc])
        raw = ScoringSystem.setting(.ipsc, true, in: raw)
        XCTAssertEqual(ScoringSystem.enabled(from: raw), [.rings, .ipsc], "switching on twice changes nothing")
        raw = ScoringSystem.setting(.rings, false, in: raw)
        XCTAssertEqual(ScoringSystem.enabled(from: raw), [.ipsc])
    }

    func testTheLastSystemStaysOn() {
        XCTAssertEqual(ScoringSystem.enabled(from: ScoringSystem.setting(.rings, false, in: "")), [.rings])
        XCTAssertEqual(ScoringSystem.enabled(from: ScoringSystem.setting(.ipsc, false, in: "ipsc")), [.ipsc])
    }

    func testNewEventsStartWithTheFirstSystemSwitchedOn() {
        XCTAssertEqual(ScoringSystem.forNewEvent(enabled: [.rings, .ipsc]), .rings)
        XCTAssertEqual(ScoringSystem.forNewEvent(enabled: [.ipsc]), .ipsc)
        XCTAssertEqual(ScoringSystem.forNewEvent(enabled: []), .rings)
    }

    func testEditorOffersAnEventsOwnSystemEvenWhenSwitchedOff() {
        XCTAssertEqual(ScoringSystem.choices(enabled: [.rings], current: .rings), [.rings], "no choice: picker hidden")
        XCTAssertEqual(ScoringSystem.choices(enabled: [.rings], current: .ipsc), [.rings, .ipsc])
        XCTAssertEqual(ScoringSystem.choices(enabled: [.rings, .ipsc], current: .rings), [.rings, .ipsc])
    }

    func testEachSystemHasTitleDetailAndIcon() {
        for system in ScoringSystem.allCases {
            XCTAssertFalse(system.title.isEmpty)
            XCTAssertFalse(system.detail.isEmpty)
            XCTAssertFalse(system.systemImage.isEmpty)
        }
    }

    // MARK: Events

    func testEventsAreScoredInPointsUnlessSetOtherwise() throws {
        let e = addEntry(nil, on: day(1), shots: 10)
        let event = try XCTUnwrap(e.shootingEvent)
        XCTAssertEqual(event.scoringSystem, .rings)
        XCTAssertEqual(e.scoringSystem, .rings)
        XCTAssertEqual(event.ipscPowerFactor, .minor)
        XCTAssertNil(event.ipscPoints)
        XCTAssertNil(e.hitFactor)

        event.scoringSystem = .ipsc
        XCTAssertEqual(event.scoringSystemRaw, "ipsc")
        XCTAssertEqual(e.scoringSystem, .ipsc, "a Stich follows its event")
        event.scoringSystemRaw = "unknown"
        XCTAssertEqual(event.scoringSystem, .rings)
    }

    func testMinorOnlyDivisionsNeverScoreMajor() throws {
        let event = try XCTUnwrap(addEntry(nil, on: day(1), shots: 10).shootingEvent)
        event.setIPSC(division: "Standard", powerFactor: .major)
        XCTAssertEqual(event.ipscDivision, "Standard")
        XCTAssertEqual(event.ipscPowerFactor, .major)
        event.setIPSC(division: "Production", powerFactor: .major)
        XCTAssertEqual(event.ipscPowerFactor, .minor)
        for division in IPSCDivision.minorOnly {
            XCTAssertTrue(IPSCDivision.all.contains(division))
            XCTAssertFalse(IPSCDivision.allowsMajor(division))
        }
        XCTAssertTrue(IPSCDivision.allowsMajor(""), "no division entered: both are possible")
        XCTAssertEqual(IPSCDivision.fitted(.major, to: "Open"), .major)
        XCTAssertEqual(IPSCDivision.fitted(.major, to: "PCC"), .minor)
    }

    func testStageDataIsStoredOnTheEntry() throws {
        let e = addEntry(nil, on: day(1), shots: 26)
        XCTAssertNil(e.ipscStage)
        e.ipscStage = IPSCStage(time: 18.434, a: 20, c: 3, d: 1, procedurals: 1)
        XCTAssertNotNil(e.ipscData)
        XCTAssertEqual(e.ipscStage, IPSCStage(time: 18.43, a: 20, c: 3, d: 1, procedurals: 1), "time in hundredths")

        e.ipscStage = IPSCStage()
        XCTAssertNil(e.ipscData, "an empty stage stores nothing")
        e.ipscStage = IPSCStage(a: 1)
        e.ipscStage = nil
        XCTAssertNil(e.ipscData)
    }

    func testHitFactorUsesTheEventsPowerFactor() throws {
        let event = ShootingEvent(date: day(1), name: "Club Match")
        context.insert(event)
        event.scoringSystem = .ipsc
        let stage1 = addStich(to: event, nil, shots: 26, stich: "Stage 1")
        stage1.ipscStage = IPSCStage(time: 20, a: 20, c: 3, d: 1, procedurals: 1)
        let stage2 = addStich(to: event, nil, shots: 12, stich: "Stage 2")
        stage2.ipscStage = IPSCStage(time: 10, a: 10, c: 2)
        addStich(to: event, nil, shots: 6, stich: "Stage 3")

        // Minor: 100 + 9 + 1 − 10 = 100 and 50 + 6 = 56.
        XCTAssertEqual(try XCTUnwrap(stage1.hitFactor), 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(stage2.hitFactor), 5.6, accuracy: 1e-9)
        XCTAssertEqual(event.ipscPoints, 156)

        // Major: 100 + 12 + 2 − 10 = 104 and 50 + 8 = 58.
        event.setIPSC(division: "Standard", powerFactor: .major)
        XCTAssertEqual(try XCTUnwrap(stage1.hitFactor), 5.2, accuracy: 1e-9)
        XCTAssertEqual(event.ipscPoints, 162)

        event.scoringSystem = .rings
        XCTAssertNil(stage1.hitFactor, "hidden while the event is scored in points")
        XCTAssertNil(event.ipscPoints)
        XCTAssertNotNil(stage1.ipscStage, "but the stage data stays")
    }

    func testNewMatchStartsWithTheLastDivision() {
        let old = ShootingEvent(date: day(1)); context.insert(old)
        old.scoringSystem = .ipsc; old.setIPSC(division: "Production", powerFactor: .minor)
        let recent = ShootingEvent(date: day(9)); context.insert(recent)
        recent.scoringSystem = .ipsc; recent.setIPSC(division: "Open", powerFactor: .major)
        let noDivision = ShootingEvent(date: day(12)); context.insert(noDivision)
        noDivision.scoringSystem = .ipsc
        let points = ShootingEvent(date: day(15)); context.insert(points)
        points.ipscDivision = "Classic"

        let last = ShootingEvent.lastIPSC(in: [old, recent, noDivision, points])
        XCTAssertEqual(last?.ipscDivision, "Open")
        XCTAssertEqual(last?.ipscPowerFactor, .major)
        XCTAssertNil(ShootingEvent.lastIPSC(in: [points]))
    }

    // MARK: Backup and CSV

    func testBackupKeepsScoringAndStages() throws {
        let event = ShootingEvent(date: day(3), name: "Swiss Open"); context.insert(event)
        event.scoringSystem = .ipsc
        event.setIPSC(division: "Classic", powerFactor: .major)
        let stage = addStich(to: event, nil, shots: 24, stich: "Stage 4")
        stage.ipscStage = IPSCStage(time: 21.07, a: 18, c: 4, d: 1, misses: 1, noShoots: 1)
        let points = addEntry(nil, on: day(4), shots: 20)
        points.result = "185"
        try context.save()

        let data = try Backup.export(context)
        let container = try ModelContainer(for: SchiesstagebuchApp.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(container)
        try Backup.restore(from: data, into: target)

        let entries = try target.fetch(FetchDescriptor<Entry>())
        let restored = try XCTUnwrap(entries.first { $0.stich == "Stage 4" })
        XCTAssertEqual(restored.scoringSystem, .ipsc)
        XCTAssertEqual(restored.shootingEvent?.ipscDivision, "Classic")
        XCTAssertEqual(restored.shootingEvent?.ipscPowerFactor, .major)
        XCTAssertEqual(restored.ipscStage, IPSCStage(time: 21.07, a: 18, c: 4, d: 1, misses: 1, noShoots: 1))
        let other = try XCTUnwrap(entries.first { $0.result == "185" })
        XCTAssertEqual(other.scoringSystem, .rings)
        XCTAssertNil(other.ipscStage)
    }

    func testBackupFromBeforeScoringSystemsLoadsAsPoints() throws {
        let json = """
        {"version": 2, "exportedAt": "2026-03-01T12:00:00Z", "calibers": [], "weapons": [], "ammunition": [],
         "ranges": [], "maintenance": [],
         "events": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "date": "2026-03-01T12:00:00Z", "name": "Training",
                     "createdAt": "2026-03-01T12:00:00Z"}],
         "entries": [{"id": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "date": "2026-03-01T12:00:00Z", "shotCount": 20,
                      "result": "180", "notes": "", "eventID": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "photos": []}]}
        """
        try Backup.restore(from: Data(json.utf8), into: context)
        let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(entry.scoringSystem, .rings)
        XCTAssertEqual(entry.shootingEvent?.ipscPowerFactor, .minor)
        XCTAssertNil(entry.ipscStage)
    }

    func testCSVHasTheIPSCColumns() throws {
        let event = ShootingEvent(date: day(3), name: "Club Match"); context.insert(event)
        event.scoringSystem = .ipsc
        event.setIPSC(division: "Production", powerFactor: .minor)
        addStich(to: event, nil, shots: 26).ipscStage = IPSCStage(time: 20, a: 20, c: 3, d: 1, procedurals: 1)
        try context.save()

        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        let header = try XCTUnwrap(lines.first).components(separatedBy: ";")
        let cols = lines[1].components(separatedBy: ";")
        XCTAssertEqual(header.count, cols.count)
        func value(_ column: String) throws -> String {
            let index = try XCTUnwrap(header.firstIndex(of: column.loc))
            return cols[index]
        }
        XCTAssertEqual(try value("Wertungsart"), "IPSC".loc)
        XCTAssertEqual(try value("Division"), "Production")
        XCTAssertEqual(try value("Treffer und Fehler"), "20 A · 3 C · 1 D · 1 PE")
        XCTAssertEqual(try value("Hitfaktor"), IPSCFormat.hitFactor(5))
        XCTAssertEqual(try value("Zeit (s)"), IPSCFormat.time(20))
    }
}
