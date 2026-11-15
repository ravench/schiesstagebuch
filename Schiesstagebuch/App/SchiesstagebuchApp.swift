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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab = "diary"
    @State private var showWelcome = false
    /// The release notes of this build, the first time it is opened (`Changelog`).
    @State private var whatsNew: [String] = []
    @State private var showWhatsNew = false

    private var dueCount: Int { weapons.reduce(0) { $0 + $1.dueMaintenance.count } }
    /// With a licence card there are six tabs, one too many for a narrow tab bar. The system's own «Mehr»
    /// puts a second navigation bar on each of its pages, so the ranges and the settings share this one.
    private var crowded: Bool { sizeClass == .compact && LicenceCard.hasCard(licenceCards) }

    var body: some View {
        TabView(selection: $tab) {
            EntryListView()
                .tabItem { Label("Tagebuch", systemImage: "list.bullet.rectangle") }
                .tag("diary")
            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.bar.xaxis") }
                .tag("stats")
            WeaponsTab()
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
                        NavigationLink { RangeListView() } label: { Label("Schiessanlagen", systemImage: "target") }
                        NavigationLink { SettingsView(inMore: true) } label: { Label("Einstellungen", systemImage: "gearshape") }
                    }
                    .navigationTitle("Mehr")
                }
                .tabItem { Label("Mehr", systemImage: "ellipsis") }
                .tag("more")
            } else {
                // «Anlagen», not the page's «Schiessanlagen»: five German labels do not fit an iPhone otherwise.
                NavigationStack { RangeListView() }
                    .tabItem { Label("Anlagen", systemImage: "target") }
                    .tag("ranges")
                SettingsView()
                    .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                    .tag("settings")
            }
        }
        // The tab the user is on goes away when the first card is saved or the last one deleted:
        // show the new card, or the settings the card was deleted from, instead of jumping to the diary.
        .onChange(of: crowded) { _, now in
            if now, tab == "ranges" || tab == "settings" { tab = "card" }
            if !now, tab == "more" { tab = "settings" }
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
}
