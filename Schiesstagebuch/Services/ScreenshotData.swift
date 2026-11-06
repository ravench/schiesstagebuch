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
        // Catalogue calibres show their cartridge drawing; a seeded catalogue already holds them.
        let gp11 = caliber("7.5x55 mm Swiss (GP 11)", in: context)
        let luger = caliber("9x19 mm", in: context)
        let rifle = Weapon(name: "Stgw 90")
        rifle.category = .serviceRifle
        rifle.serialNumber = "A 123456"
        let pistol = Weapon(name: "SIG P226")
        pistol.category = .pistol
        let ammo = Ammunition(name: "GP 11", caliber: gp11)
        context.insert(range)
        context.insert(rifle)
        context.insert(pistol)
        context.insert(ammo)
        rifle.ensureBarrel(for: gp11, in: context)
        pistol.ensureBarrel(for: luger, in: context)

        let samples = [
            Sample(daysAgo: 2, event: "Obligatorisch", weapon: rifle, shots: 20, result: "78"),
            Sample(daysAgo: 9, event: "Feldschiessen", weapon: rifle, shots: 18, result: "62"),
            Sample(daysAgo: 16, event: "Training", weapon: pistol, shots: 50, result: "441"),
            Sample(daysAgo: 30, event: "Bundesprogramm", weapon: rifle, shots: 20, result: "81"),
            Sample(daysAgo: 44, event: "Training", weapon: pistol, shots: 60, result: "512"),
            Sample(daysAgo: 61, event: "Vereinsstich", weapon: rifle, shots: 10, result: "92"),
        ]
        for s in samples {
            let date = Calendar.current.date(byAdding: .day, value: -s.daysAgo, to: now) ?? now
            let caliber = s.weapon.calibers.first
            let event = ShootingEvent(date: date, name: s.event, range: range)
            context.insert(event)
            let entry = Entry(date: date, weapon: s.weapon, caliber: caliber,
                              shotCount: s.shots, ammunition: caliber === gp11 ? ammo : nil, result: s.result)
            context.insert(entry)
            event.add(entry)
        }
        try? context.save()
    }

    /// The calibre with this catalogue id, inserted if the catalogue is not seeded.
    @MainActor
    private static func caliber(_ catalogID: String, in context: ModelContext) -> Caliber {
        let all = (try? context.fetch(FetchDescriptor<Caliber>())) ?? []
        if let existing = all.first(where: { $0.catalogID == catalogID }) { return existing }
        let c = Caliber(name: CaliberCatalog.item(id: catalogID)?.name ?? catalogID)
        c.catalogID = catalogID
        context.insert(c)
        return c
    }

    private struct Sample {
        let daysAgo: Int
        let event: String
        let weapon: Weapon
        let shots: Int
        let result: String
    }
}
