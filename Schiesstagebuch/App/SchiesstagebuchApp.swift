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
                                LicenceCard.self, Barrel.self, ShootingTarget.self])

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
                    // Nothing here may delete or empty a record for what it lacks: during a first iCloud
                    // import records arrive before their links (review 2026-11-27).
                    CaliberCatalog.followRenames(container.mainContext)
                    CaliberCatalog.removeUnused(container.mainContext)
                    CaliberCatalog.deduplicate(container.mainContext)
                    RangeCatalog.deduplicate(container.mainContext)
                    TargetCatalog.deduplicate(container.mainContext)
                    if ScreenshotData.isActive { ScreenshotData.seed(container.mainContext) }
                }
                // Core Data posts this from a background queue; mainContext must only be used on the main thread.
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
                    CaliberCatalog.followRenames(container.mainContext)
                    CaliberCatalog.deduplicate(container.mainContext)
                    RangeCatalog.deduplicate(container.mainContext)
                    TargetCatalog.deduplicate(container.mainContext)
                    // A cleaning recorded on another device cancels the reminder pending here.
                    MaintenanceNotifier.refreshAll(in: container.mainContext)
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                CaliberCatalog.deduplicate(container.mainContext)
                RangeCatalog.deduplicate(container.mainContext)
                TargetCatalog.deduplicate(container.mainContext)
                MaintenanceNotifier.refreshAll(in: container.mainContext)
            }
        }
    }
}

struct RootView: View {
    @Environment(\.term) private var term
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Weapon> { !$0.isArchived }) private var weapons: [Weapon]
    @Query private var licenceCards: [LicenceCard]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab = "diary"
    /// The Waffen tab's navigation path: a tapped reminder puts its firearm there. Type-erased, since
    /// the firearm's page pushes its statistics with a view link, which a typed path cannot hold.
    @State private var weaponPath = NavigationPath()
    @State private var showWelcome = false
    /// The release notes of this build, the first time it is opened (`Changelog`).
    @State private var whatsNew: [String] = []
    @State private var showWhatsNew = false

    /// Read so that the tab's number is worked out again when the app comes to the front (a reminder may have
    /// become due meanwhile) and when «Tage zählen» changes; neither touches the firearms the query watches.
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(DayCounting.defaultsKey) private var dayCounting: DayCounting = .fromFirstUse

    private var dueCount: Int {
        _ = (scenePhase, dayCounting)
        return MaintenanceNotifier.dueCount(weapons)
    }
    /// With a licence card there are six tabs, one too many for a narrow tab bar. The system's own «Mehr»
    /// puts a second navigation bar on each of its pages, so the ranges and the settings share this one.
    private var crowded: Bool { sizeClass == .compact && LicenceCard.hasCard(licenceCards) }

    /// The tab to show once the tab bar has changed: the first card saved shows the new card, a window
    /// made narrow (iPad) stays with the ranges and settings in «Mehr», the last card deleted or the
    /// window wide again shows the settings.
    static func tab(_ tab: String, crowded: Bool, newCard: Bool) -> String {
        if crowded, tab == "ranges" || tab == "settings" { return newCard ? "card" : "more" }
        if !crowded, tab == "more" { return "settings" }
        return tab
    }

    var body: some View {
        TabView(selection: $tab) {
            EntryListView()
                .tabItem { Label("Tagebuch", systemImage: "list.bullet.rectangle") }
                .tag("diary")
            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.bar.xaxis") }
                .tag("stats")
            WeaponsTab(path: $weaponPath)
                .tabItem { Label(term("Waffen").loc, systemImage: "scope") }
                .badge(dueCount)
                .tag("weapons")
            // The card gets its own tab once one has been entered, to show at the range; entering and
            // editing it stays in Einstellungen › SSV-Lizenzkarte (Raven 2026-11-14).
            if LicenceCard.hasCard(licenceCards) {
                NavigationStack { LicenceCardScreen(editable: false) }
                    .tabItem { Label("Lizenzkarte", systemImage: "person.text.rectangle") }
                    .tag("card")
            }
            // Firearms and ranges are tabs only, no longer also under Einstellungen (Raven 2026-11-15).
            if crowded {
                NavigationStack {
                    List {
                        NavigationLink { RangeListView() } label: { Label("Schiessanlagen", systemImage: RangeListView.icon) }
                        NavigationLink { SettingsView(inMore: true) } label: { Label("Einstellungen", systemImage: "gearshape") }
                    }
                    .navigationTitle("Mehr")
                }
                .tabItem { Label("Mehr", systemImage: "ellipsis") }
                .tag("more")
            } else {
                // «Anlagen», not the page's «Schiessanlagen»: five German labels do not fit an iPhone otherwise.
                NavigationStack { RangeListView() }
                    .tabItem { Label("Anlagen", systemImage: RangeListView.icon) }
                    .tag("ranges")
                SettingsView()
                    .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                    .tag("settings")
            }
        }
        // The tab the user is on goes away when the tab bar changes, instead of jumping to the diary:
        .onChange(of: [sizeClass == .compact, LicenceCard.hasCard(licenceCards)]) { old, new in
            tab = Self.tab(tab, crowded: new[0] && new[1], newCard: !old[1] && new[1])
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
        tab = "weapons"
        let found = try? context.fetch(FetchDescriptor<Weapon>(predicate: #Predicate { $0.id == id })).first
        weaponPath = found.map { NavigationPath([$0]) } ?? NavigationPath()
    }
}
