import SwiftUI
import SwiftData
import CoreData

@main
struct SchiesstagebuchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer = Self.makeContainer()

    static let schema = Schema([Entry.self, Weapon.self, Caliber.self, Ammunition.self,
                                ShootingRange.self, MaintenanceRecord.self, EntryPhoto.self])

    /// Syncs through the iCloud container from the entitlements when the user is signed in to iCloud,
    /// otherwise SwiftData simply keeps working locally.
    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic))
        } catch {
            // e.g. missing iCloud entitlement in a debug build: fall back to a local store.
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
            } catch {
                fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    CaliberCatalog.seedIfNeeded(container.mainContext)
                    CaliberCatalog.deduplicate(container.mainContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                    CaliberCatalog.deduplicate(container.mainContext)
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { CaliberCatalog.deduplicate(container.mainContext) }
        }
    }
}

struct RootView: View {
    @Query(filter: #Predicate<Weapon> { !$0.isArchived }) private var weapons: [Weapon]

    private var dueCount: Int { weapons.reduce(0) { $0 + $1.dueMaintenance.count } }

    var body: some View {
        TabView {
            EntryListView()
                .tabItem { Label("Tagebuch", systemImage: "list.bullet.rectangle") }
            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.bar.xaxis") }
            WeaponsTab()
                .tabItem { Label("Waffen", systemImage: "scope") }
                .badge(dueCount)
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
    }
}
