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

    /// Removes all but the newest `keep` backups.
    static func prune(keep: Int = keep, ext: String = "json", in folder: URL = defaultFolder) {
        for url in list(ext: ext, in: folder).dropFirst(keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
