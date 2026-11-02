import Foundation
import SwiftData

/// Sample diary for screenshots (the iPad screen check in CI). Started with the launch
/// argument `-screenshotData`, the app then uses a throwaway in-memory store and never
/// touches the user's data or iCloud.
enum ScreenshotData {
    static let launchArgument = "-screenshotData"

    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    /// Fills an empty store with a small, realistic diary. Does nothing if entries exist.
    @MainActor
    static func seed(_ context: ModelContext, now: Date = .now) {
        let existing = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard existing == 0 else { return }

        let range = ShootingRange(name: "Schiessanlage Ostermundigen", place: "Ostermundigen")
        let gp11 = Caliber(name: "7.5x55 Swiss")
        let luger = Caliber(name: "9mm Luger")
        let rifle = Weapon(name: "Stgw 90")
        rifle.category = .serviceRifle
        rifle.calibers = [gp11]
        rifle.serialNumber = "A 123456"
        let pistol = Weapon(name: "SIG P226")
        pistol.category = .pistol
        pistol.calibers = [luger]
        let ammo = Ammunition(name: "GP 11", caliber: gp11)
        [range, gp11, luger, rifle, pistol, ammo].forEach { context.insert($0) }

        let samples: [(daysAgo: Int, event: String, weapon: Weapon, shots: Int, result: String)] = [
            (2, "Obligatorisch", rifle, 20, "78"),
            (9, "Feldschiessen", rifle, 18, "62"),
            (16, "Training", pistol, 50, "441"),
            (30, "Bundesprogramm", rifle, 20, "81"),
            (44, "Training", pistol, 60, "512"),
            (61, "Vereinsstich", rifle, 10, "92"),
        ]
        for s in samples {
            let date = Calendar.current.date(byAdding: .day, value: -s.daysAgo, to: now) ?? now
            let caliber = s.weapon.calibers?.first
            let entry = Entry(date: date, range: range, event: s.event, weapon: s.weapon, caliber: caliber,
                              shotCount: s.shots, ammunition: caliber === gp11 ? ammo : nil, result: s.result)
            context.insert(entry)
        }
        try? context.save()
    }
}
