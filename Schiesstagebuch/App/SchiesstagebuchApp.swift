import SwiftUI
import SwiftData
import CoreData
import UserNotifications

@main
struct SchiesstagebuchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Wording.sportsEquipmentKey) private var sportsEquipment = false
    let container: ModelContainer = Self.makeContainer()
    /// Kept for the app's lifetime: the notification center holds its delegate weakly.
    private let notificationDelegate = MaintenanceNotificationDelegate()

    init() {
        // Before the launch finishes, so a tap that starts the app reaches the delegate too.
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

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
                    CaliberCatalog.followRenames(container.mainContext)
                    CaliberCatalog.removeUnused(container.mainContext)
                    CaliberCatalog.deduplicate(container.mainContext)
                    RangeCatalog.deduplicate(container.mainContext)
                    if WeatherRecord.moveToStiche(in: container.mainContext) { try? container.mainContext.save() }
                    if ScreenshotData.isActive { ScreenshotData.seed(container.mainContext) }
                }
                // Core Data posts this from a background queue; mainContext must only be used on the main thread.
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
                    CaliberCatalog.followRenames(container.mainContext)
                    CaliberCatalog.deduplicate(container.mainContext)
                    RangeCatalog.deduplicate(container.mainContext)
                    if WeatherRecord.moveToStiche(in: container.mainContext) { try? container.mainContext.save() }
                    // A cleaning recorded on another device cancels the reminder pending here.
                    MaintenanceNotifier.refreshAll(in: container.mainContext)
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                CaliberCatalog.deduplicate(container.mainContext)
                RangeCatalog.deduplicate(container.mainContext)
                MaintenanceNotifier.refreshAll(in: container.mainContext)
            }
        }
    }
}

struct RootView: View {
    enum Tab: Hashable { case journal, stats, weapons, licence, settings }

    @Environment(\.term) private var term
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Weapon> { !$0.isArchived }) private var weapons: [Weapon]
    @Query private var licenceCards: [LicenceCard]
    @State private var tab = Tab.journal
    /// The Waffen tab's navigation path: a tapped reminder puts its firearm there. Type-erased, since
    /// the firearm's page pushes its statistics with a view link, which a typed path cannot hold.
    @State private var weaponPath = NavigationPath()
    @State private var showWelcome = false
    /// The release notes of this build, the first time it is opened (`Changelog`).
    @State private var whatsNew: [String] = []
    @State private var showWhatsNew = false

    private var dueCount: Int { weapons.reduce(0) { $0 + $1.dueMaintenance.count } }

    var body: some View {
        TabView(selection: $tab) {
            EntryListView()
                .tabItem { Label("Tagebuch", systemImage: "list.bullet.rectangle") }
                .tag(Tab.journal)
            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.bar.xaxis") }
                .tag(Tab.stats)
            WeaponsTab(path: $weaponPath)
                .tabItem { Label(term("Waffen").loc, systemImage: "scope") }
                .badge(dueCount)
                .tag(Tab.weapons)
            // The card gets its own tab once one has been entered, to show at the range; entering and
            // editing it stays in Einstellungen › SSV-Lizenzkarte (Raven 2026-11-14).
            if LicenceCard.hasCard(licenceCards) {
                NavigationStack { LicenceCardScreen(editable: false) }
                    .tabItem { Label("Lizenzkarte", systemImage: "person.text.rectangle") }
                    .tag(Tab.licence)
            }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // A tapped Pflege reminder; `initial`, since the tap may have started the app.
        .onChange(of: ReminderTap.shared.weaponID, initial: true) { _, id in
            guard let id else { return }
            open(weaponID: id)
            ReminderTap.shared.weaponID = nil
        }
        .task {
            showWelcome = ScreenshotData.isActive ? ScreenshotData.showsWelcome : FirstRun.shouldShow()
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
            guard !showWelcome else {
                // A first start shows the welcome screen; the notes of this build are not news to a new user.
                UserDefaults.standard.set(build, forKey: Changelog.shownBuildKey)
                return
            }
            if let notes = Changelog.toShow(build: build, language: Bundle.main.preferredLocalizations.first ?? "de") {
                whatsNew = notes
                showWhatsNew = true
            }
        }
        .sheet(isPresented: $showWelcome) { WelcomeView() }
        .sheet(isPresented: $showWhatsNew) { WhatsNewView(bullets: whatsNew) }
    }

    /// The firearm's page in the Waffen tab; the list alone when the firearm no longer exists.
    private func open(weaponID id: UUID) {
        tab = .weapons
        let found = try? context.fetch(FetchDescriptor<Weapon>(predicate: #Predicate { $0.id == id })).first
        weaponPath = found.map { NavigationPath([$0]) } ?? NavigationPath()
    }
}
