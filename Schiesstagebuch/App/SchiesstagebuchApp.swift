import SwiftUI
import SwiftData

@main
struct SchiesstagebuchApp: App {
    let container: ModelContainer = {
        do {
            return try ModelContainer(for: Entry.self, Weapon.self, Caliber.self, Ammunition.self,
                                      ShootingRange.self, MaintenanceRecord.self, EntryPhoto.self)
        } catch {
            fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    CaliberCatalog.seedIfNeeded(container.mainContext)
                }
        }
        .modelContainer(container)
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
