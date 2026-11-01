import Foundation
import SwiftData

/// Commonly used calibres, seeded once on first launch. Users can archive,
/// rename or add their own in Einstellungen › Kaliber.
enum CaliberCatalog {
    enum Category: String, CaseIterable {
        case rimfire = "Randfeuer"
        case handgun = "Kurzwaffe"
        case rifle = "Langwaffe"
        case shotgun = "Flinte"
        case other = "Andere"
    }

    static let all: [(Category, [String])] = [
        (.rimfire, [
            ".22 Short", ".22 LR", ".22 WMR", ".17 HMR", ".17 Mach 2",
        ]),
        (.handgun, [
            "6.35 mm Browning (.25 ACP)", "7.65 mm Browning (.32 ACP)", "7.65 mm Parabellum",
            ".32 S&W Long", ".32 H&R Magnum", "7.62x25 mm Tokarev", "9 mm Browning kurz (.380 ACP)",
            "9x18 mm Makarov", "9x19 mm", "9x21 mm IMI", ".357 SIG", ".38 Special",
            ".357 Magnum", ".38 Super", "10 mm Auto", ".40 S&W", ".41 Magnum", ".44 Special",
            ".44 Magnum", ".45 ACP", ".45 Colt", ".45 GAP", ".454 Casull", ".460 S&W Magnum",
            ".500 S&W Magnum", "5.7x28 mm", "4.6x30 mm",
        ]),
        (.rifle, [
            ".204 Ruger", ".222 Remington", ".223 Remington", "5.56x45 mm NATO",
            "5.6 mm GP 90 (Swiss)", ".22-250 Remington", ".243 Winchester", "6 mm BR Norma",
            "6 mm ARC", "6.5 mm Creedmoor", "6.5x55 mm Swedish", "6.5x47 mm Lapua", "6.5 PRC",
            ".260 Remington", ".270 Winchester", "7 mm-08 Remington", "7x57 mm Mauser",
            "7x64 mm", "7 mm Remington Magnum", "7 mm PRC", "7.5x55 mm Swiss (GP 11)",
            "7.5x54 mm French", "7.62x39 mm", ".300 AAC Blackout", "7.62x51 mm NATO",
            ".308 Winchester", ".30-06 Springfield", ".30-30 Winchester", ".300 Winchester Magnum",
            ".300 PRC", ".300 Norma Magnum", ".303 British", "7.62x54 mm R", "8x57 mm IS",
            "8x68 mm S", "9.3x62 mm", "9.3x74 mm R", ".338 Lapua Magnum", ".375 H&H Magnum",
            ".416 Rigby", ".45-70 Government", ".50 BMG",
        ]),
        (.shotgun, [
            "12/70", "12/76", "12/89", "16/70", "20/70", "20/76", "28/70", ".410/76",
        ]),
        (.other, [
            "4.5 mm Luftdruck (.177)", "5.5 mm Luftdruck (.22)",
        ]),
    ]

    private static let seededKey = "caliberCatalogSeeded.v1"

    /// Inserts the catalogue once. Skips names that already exist (e.g. after a restore).
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let existing = Set(((try? context.fetch(FetchDescriptor<Caliber>())) ?? []).map { Caliber.normalized($0.name) })
        for (category, names) in all {
            for name in names where !existing.contains(Caliber.normalized(name)) {
                context.insert(Caliber(name: name, category: category.rawValue))
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }
}
