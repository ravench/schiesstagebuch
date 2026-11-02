import Foundation

/// Keeps copies of exported backups in the app's own Documents folder, which the
/// Files app shows under "On My iPhone › Schiesstagebuch" (UIFileSharingEnabled).
enum BackupStore {
    static var defaultFolder: URL {
        URL.documentsDirectory.appending(path: "Backups", directoryHint: .isDirectory)
    }

    /// Number of backup copies kept; older ones are removed.
    static let keep = 10

    /// Writes `data` as `<name>.<ext>`, adding " 2", " 3" … if the name is taken.
    @discardableResult
    static func save(_ data: Data, name: String, ext: String = "json", in folder: URL = defaultFolder) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder.appending(path: "\(name).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(name) \(n).\(ext)")
            n += 1
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Backup files in the folder, newest first.
    static func list(ext: String = "json", in folder: URL = defaultFolder) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func date(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return files.filter { $0.pathExtension == ext }
            .sorted { (date($0), $0.lastPathComponent) > (date($1), $1.lastPathComponent) }
    }

    /// Files the app wrote itself: "Schiesstagebuch-2026-11-01.json", "Schiesstagebuch-2026-11-01 2.json".
    /// Anything else in the folder (a backup copied in from another device) is never pruned.
    static func isAppBackup(_ url: URL) -> Bool {
        url.lastPathComponent.range(of: #"^Schiesstagebuch-\d{4}-\d{2}-\d{2}( \d+)?\.[A-Za-z0-9]+$"#,
                                    options: .regularExpression) != nil
    }

    /// Removes all but the newest `keep` backups the app wrote; other files stay.
    static func prune(keep: Int = keep, ext: String = "json", in folder: URL = defaultFolder) {
        for url in list(ext: ext, in: folder).filter(isAppBackup).dropFirst(keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
