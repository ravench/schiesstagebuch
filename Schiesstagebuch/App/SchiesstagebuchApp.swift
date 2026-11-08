import SwiftUI
import SwiftData
import CoreData

@main
struct SchiesstagebuchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Wording.sportsEquipmentKey) private var sportsEquipment = false
    let container: ModelContainer = Self.makeContainer()

    static let schema = Schema([ShootingEvent.self, Entry.self, Weapon.self, Caliber.self, Ammunition.self,
                                ShootingRange.self, MaintenanceRecord.self, EntryPhoto.self, AmmoLot.self,
                                LicenceCard.self, Barrel.self])

    /// Syncs through the iCloud container from the entitlements when the user is signed in to iCloud,
    /// otherwise SwiftData simply keeps working locally.
    static func makeContainer() -> ModelContainer {
        if ScreenshotData.isActive {
            // Screenshot runs: sample data in memory only, never the user's store or iCloud.
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            } catch {
                fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
            }
        }
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
                .environment(\.term, Terms(sportsEquipment: sportsEquipment))
                .task {
                    CaliberCatalog.seedIfNeeded(container.mainContext)
                    CaliberCatalog.deduplicate(container.mainContext)
                    RangeCatalog.deduplicate(container.mainContext)
                    if ScreenshotData.isActive { ScreenshotData.seed(container.mainContext) }
                }
                // Core Data posts this from a background queue; mainContext must only be used on the main thread.
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
                    CaliberCatalog.deduplicate(container.mainContext)
                    RangeCatalog.deduplicate(container.mainContext)
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                CaliberCatalog.deduplicate(container.mainContext)
                RangeCatalog.deduplicate(container.mainContext)
            }
        }
    }
}

struct RootView: View {
    @Environment(\.term) private var term
    @Query(filter: #Predicate<Weapon> { !$0.isArchived }) private var weapons: [Weapon]
    @Query private var licenceCards: [LicenceCard]
    @State private var showWelcome = false
    /// The release notes of this build, the first time it is opened (`Changelog`).
    @State private var whatsNew: [String] = []
    @State private var showWhatsNew = false

    private var dueCount: Int { weapons.reduce(0) { $0 + $1.dueMaintenance.count } }

    var body: some View {
        TabView {
            EntryListView()
                .tabItem { Label("Tagebuch", systemImage: "list.bullet.rectangle") }
            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.bar.xaxis") }
            WeaponsTab()
                .tabItem { Label(term("Waffen").loc, systemImage: "scope") }
                .badge(dueCount)
            // The licence card gets its own tab once one has been entered (Einstellungen › SSV-Lizenz).
            if LicenceCard.hasCard(licenceCards) {
                NavigationStack { LicenceCardScreen() }
                    .tabItem { Label("SSV-Lizenz", systemImage: "person.text.rectangle") }
            }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .task {
            showWelcome = ScreenshotData.isActive ? ScreenshotData.showsWelcome : FirstRun.shouldShow()
            guard !showWelcome else { return } // a first start shows the welcome screen; the notes wait
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
            if let notes = Changelog.toShow(build: build, language: Bundle.main.preferredLocalizations.first ?? "de") {
                whatsNew = notes
                showWhatsNew = true
            }
        }
        .sheet(isPresented: $showWelcome) { WelcomeView() }
        .sheet(isPresented: $showWhatsNew) { WhatsNewView(bullets: whatsNew) }
    }
}
