import XCTest
@testable import Schiesstagebuch

final class BackupStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "BackupStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testSaveCreatesFolderAndFile() throws {
        let url = try BackupStore.save(Data("{}".utf8), name: "Schiesstagebuch-2026-11-01", in: folder)
        XCTAssertEqual(url.lastPathComponent, "Schiesstagebuch-2026-11-01.json")
        XCTAssertEqual(try Data(contentsOf: url), Data("{}".utf8))
    }

    func testSameNameGetsANumber() throws {
        let a = try BackupStore.save(Data("1".utf8), name: "Backup", in: folder)
        let b = try BackupStore.save(Data("2".utf8), name: "Backup", in: folder)
        let c = try BackupStore.save(Data("3".utf8), name: "Backup", in: folder)
        XCTAssertEqual([a, b, c].map(\.lastPathComponent), ["Backup.json", "Backup 2.json", "Backup 3.json"])
        XCTAssertEqual(try Data(contentsOf: a), Data("1".utf8), "an existing backup is never overwritten")
    }

    func testListIsNewestFirstAndOnlyBackups() throws {
        let old = try BackupStore.save(Data(), name: "old", in: folder)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.path)
        let new = try BackupStore.save(Data(), name: "new", in: folder)
        try BackupStore.save(Data(), name: "export", ext: "csv", in: folder)
        XCTAssertEqual(BackupStore.list(in: folder), [new, old])
    }

    func testPruneKeepsNewest() throws {
        for i in 0..<5 {
            let url = try BackupStore.save(Data(), name: "Schiesstagebuch-2026-10-0\(i + 1)", in: folder)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: Double(i - 10) * 60)],
                                                  ofItemAtPath: url.path)
        }
        BackupStore.prune(keep: 2, in: folder)
        XCTAssertEqual(BackupStore.list(in: folder).map(\.lastPathComponent), ["Schiesstagebuch-2026-10-05.json", "Schiesstagebuch-2026-10-04.json"])
    }

    func testPruneLeavesFilesTheAppDidNotWrite() throws {
        for i in 0..<3 {
            let url = try BackupStore.save(Data(), name: "Schiesstagebuch-2026-11-0\(i + 1)", in: folder)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: Double(i - 10) * 60)],
                                                  ofItemAtPath: url.path)
        }
        let foreign = try BackupStore.save(Data(), name: "vom-iPad", in: folder)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: foreign.path)
        BackupStore.prune(keep: 1, in: folder)
        XCTAssertEqual(Set(BackupStore.list(in: folder).map(\.lastPathComponent)), ["Schiesstagebuch-2026-11-03.json", "vom-iPad.json"])
    }

    func testAppBackupNames() {
        XCTAssertTrue(BackupStore.isAppBackup(URL(filePath: "/x/Schiesstagebuch-2026-11-01.json")))
        XCTAssertTrue(BackupStore.isAppBackup(URL(filePath: "/x/Schiesstagebuch-2026-11-01 2.json")))
        XCTAssertFalse(BackupStore.isAppBackup(URL(filePath: "/x/Schiesstagebuch.json")))
        XCTAssertFalse(BackupStore.isAppBackup(URL(filePath: "/x/vom-iPad.json")))
    }

    func testListOfMissingFolderIsEmpty() {
        XCTAssertTrue(BackupStore.list(in: folder).isEmpty)
    }

    func testAppFolderIsVisibleInFilesApp() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(info["UIFileSharingEnabled"] as? Bool, true)
        XCTAssertEqual(info["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
    }
}
