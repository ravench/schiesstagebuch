import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    /// One exporter for both formats: SwiftUI only honours one fileExporter per view.
    @State private var exportDoc: BackupDocument?
    @State private var exportType: UTType = .json
    @State private var exportName = ""
    @State private var importing = false
    @State private var importingLegacy = false
    @State private var message: String?
    @AppStorage(ShotEntryMode.defaultsKey) private var defaultMode: ShotEntryMode = .total
    @AppStorage(DayCounting.defaultsKey) private var dayCounting: DayCounting = .fromFirstUse
    @Query private var weapons: [Weapon]
    @AppStorage(Weapon.showSerialKey) private var showSerial = true
    @AppStorage(SightSettings.showKey) private var showSport = false
    @AppStorage(NearbyRanges.enabledKey) private var rangeByLocation = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { WeaponsListView() } label: { Label("Waffen", systemImage: "scope") }
                    NavigationLink { CaliberListView() } label: { Label("Kaliber", systemImage: "circle.dotted") }
                    NavigationLink { AmmunitionListView() } label: { Label("Munition", systemImage: "shippingbox") }
                    NavigationLink { RangeListView() } label: { Label("Schiessanlagen", systemImage: "mappin.and.ellipse") }
                } header: {
                    Text("Stammdaten")
                }

                Section {
                    NavigationLink { LicenceCardScreen() } label: { Label("SSV-Lizenz", systemImage: "person.text.rectangle") }
                }

                Section {
                    Picker(selection: $defaultMode) {
                        ForEach(ShotEntryMode.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Schüsse erfassen als", systemImage: "list.number")
                    }
                    Toggle(isOn: $showSerial) {
                        Label("Seriennummer in der Waffenauswahl", systemImage: "number")
                    }
                } header: {
                    Text("Erfassung")
                } footer: {
                    Text("Gilt für neue Einträge. Pro Eintrag kannst du die Art jederzeit wechseln.")
                }

                Section {
                    Toggle(isOn: $rangeByLocation) {
                        Label("Schiessanlage nach Standort wählen", systemImage: "location")
                    }
                } footer: {
                    Text("Neue Einträge von heute wählen die Schiessanlage, bei der du gerade bist, und listen nahe Anlagen zuerst. Der Standort wird nur dafür gelesen und weder gespeichert noch gesendet.")
                }

                Section {
                    Toggle(isOn: $showSport) {
                        Label("Waffen-Einstellungen für Sportschützen erfassen", systemImage: "scope")
                    }
                    if showSport {
                        NavigationLink { FilterSettingsView() } label: {
                            Label("Filter (Mehrzahl)", systemImage: "circle.lefthalf.filled")
                        }
                    }
                } footer: {
                    Text("Zeigt in Einträgen Felder für Filter, Diopter, Ring oder Iris und Zweibein. Ausgeblendete Werte bleiben gespeichert.")
                }

                Section {
                    Picker(selection: $dayCounting) {
                        ForEach(DayCounting.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Tage zählen", systemImage: "calendar.badge.clock")
                    }
                } header: {
                    Text("Erinnerungen")
                } footer: {
                    Text("Ab wann Erinnerungen nach Tagen zählen. Pro Waffe kannst du das ändern.")
                }

                Section {
                    Button { export() } label: { Label("Backup exportieren", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Backup wiederherstellen", systemImage: "square.and.arrow.down") }
                    Button { exportCSV() } label: { Label("Tagebuch als CSV", systemImage: "tablecells") }
                    Button { importingLegacy = true } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import aus «\(LegacyImport.sourceAppName)»")
                                Text("App von \(LegacyImport.sourceDeveloper)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.doc")
                        }
                    }
                } header: {
                    Text("Daten")
                } footer: {
                    Text("Das Backup enthält alle Einträge, Fotos und Stammdaten. Beim Wiederherstellen werden vorhandene Einträge nicht doppelt angelegt. Die letzten 10 Backups liegen zusätzlich in der Dateien-App unter Auf meinem iPhone › Schiesstagebuch › Backups.")
                }

                Section {
                    NavigationLink { AppIconView() } label: { Label("App-Icon", systemImage: "app.badge") }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                }
            }
            .navigationTitle("Einstellungen")
            .onChange(of: dayCounting) { weapons.forEach { MaintenanceNotifier.refresh($0) } }
            .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                          document: exportDoc, contentType: exportType, defaultFilename: exportName) { result in
                if case .failure(let e) = result { message = e.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): restore(from: url)
                case .failure(let e): message = e.localizedDescription
                }
            }
            .sheet(isPresented: $importingLegacy) { LegacyImportView() }
            .alert("Datensicherung", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            } message: { Text(message ?? "") }
        }
    }

    private func export() {
        do {
            exportType = .json
            exportName = "Schiesstagebuch-\(Date.now.formatted(.iso8601.year().month().day()))"
            let data = try Backup.export(context)
            exportDoc = BackupDocument(data: data)
            // A copy stays in the app's folder in the Files app.
            try? BackupStore.save(data, name: exportName)
            BackupStore.prune()
        }
        catch { message = String(localized: "Export fehlgeschlagen: \(error.localizedDescription)") }
    }

    private func exportCSV() {
        exportType = .commaSeparatedText
        exportName = "Schiesstagebuch"
        exportDoc = BackupDocument(data: Backup.csv(context))
    }

    private func restore(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let summary = try Backup.restore(from: Data(contentsOf: url), into: context)
            message = summary
        } catch {
            message = String(localized: "Wiederherstellen fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}

// MARK: - Calibres

struct CaliberListView: View {
    @Query(sort: \Caliber.name) private var calibers: [Caliber]
    @State private var search = ""
    @State private var showArchived = false
    @State private var adding = false

    private var visible: [Caliber] {
        calibers.filter { (showArchived || !$0.isArchived) && $0.matches(search) }
            .sorted { a, b in
                // Calibres in use first, then alphabetical.
                let ua = !(a.weapons ?? []).isEmpty, ub = !(b.weapons ?? []).isEmpty
                return ua != ub ? ua : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    var body: some View {
        List(visible) { c in
            NavigationLink { CaliberDetailView(caliber: c) } label: {
                HStack {
                    CartridgeView(caliber: c).frame(width: 20, height: 34)
                    VStack(alignment: .leading) {
                        Text(c.name).foregroundStyle(c.isArchived ? .secondary : .primary)
                        if !c.aliasSummary.isEmpty {
                            Text(c.aliasSummary).font(.caption).foregroundStyle(.secondary)
                        }
                        let weapons = (c.weapons ?? []).map(\.name).sorted()
                        if !weapons.isEmpty { Text(weapons.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    let shots = (c.entries ?? []).totalShots
                    if shots > 0 { Text(shots.formatted()).monospacedDigit().foregroundStyle(.secondary) }
                }
            }
            .swipeActions { ArchiveButton(item: c) }
        }
        .searchable(text: $search, prompt: "Kaliber suchen")
        .navigationTitle("Kaliber")
        .toolbar {
            Toggle(isOn: $showArchived) { Label("Archivierte", systemImage: "archivebox") }.toggleStyle(.button)
            Button { adding = true } label: { Label("Hinzufügen", systemImage: "plus") }
        }
        .sheet(isPresented: $adding) { CaliberEditorView(caliber: nil) }
    }
}

struct CaliberEditorView: View {
    let caliber: Caliber?
    var initialName = ""
    var onCreate: ((Caliber) -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = CaliberCatalog.Category.other.rawValue
    @State private var isArchived = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Bezeichnung, z. B. 9x19 mm", text: $name)
                Picker("Kategorie", selection: $category) {
                    ForEach(CaliberCatalog.Category.allCases, id: \.rawValue) { Text($0.rawValue.loc).tag($0.rawValue) }
                }
                if caliber != nil { Toggle("Archiviert", isOn: $isArchived) }
            }
            .navigationTitle(caliber == nil ? "Neues Kaliber".loc : "Kaliber bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let target = caliber ?? Caliber(name: "")
                        target.name = name.trimmingCharacters(in: .whitespaces)
                        target.category = category
                        target.isArchived = isArchived
                        if caliber == nil { context.insert(target); onCreate?(target) }
                        try? context.save()
                        dismiss()
                    }
                    .bold().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = caliber?.name ?? initialName
                category = caliber?.category.isEmpty == false ? caliber!.category : category
                isArchived = caliber?.isArchived ?? false
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Ammunition

struct AmmunitionListView: View {
    @Query(sort: \Ammunition.name) private var items: [Ammunition]
    @State private var showArchived = false
    @State private var adding = false

    private var groups: [(String, [Ammunition])] {
        Dictionary(grouping: items.filter { showArchived || !$0.isArchived }) { $0.caliber?.name ?? "Ohne Kaliber".loc }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Keine Munition", systemImage: "shippingbox")
                } description: {
                    Text("Erfasse deine Munitionssorten, je mit Kaliber.")
                } actions: {
                    Button("Munition hinzufügen") { adding = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(groups, id: \.0) { group in
                        Section(group.0) {
                            ForEach(group.1) { a in
                                NavigationLink { AmmunitionDetailView(ammunition: a) } label: {
                                    AmmunitionRow(ammunition: a)
                                }
                                .swipeActions { ArchiveButton(item: a) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Munition")
        .toolbar {
            Toggle(isOn: $showArchived) { Label("Archivierte", systemImage: "archivebox") }.toggleStyle(.button)
            Button { adding = true } label: { Label("Hinzufügen", systemImage: "plus") }
        }
        .sheet(isPresented: $adding) { AmmunitionEditorView(ammunition: nil) }
    }
}

struct AmmunitionEditorView: View {
    let ammunition: Ammunition?
    var suggestedCaliber: Caliber?
    var onCreate: ((Ammunition) -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Caliber> { !$0.isArchived }, sort: \Caliber.name) private var calibers: [Caliber]
    @State private var name = ""
    @State private var caliber: Caliber?
    @State private var isArchived = false
    @State private var lots: [LotDraft] = []

    /// An editable lot row; `lot` is nil for lots added in this sheet.
    private struct LotDraft: Identifiable {
        let id = UUID()
        var lot: AmmoLot?
        var number: String
    }

    /// Calibres used by a weapon first, the rest of the catalogue below.
    private var inUse: [Caliber] { calibers.filter { !($0.weapons ?? []).isEmpty } }
    private var others: [Caliber] { calibers.filter { ($0.weapons ?? []).isEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Bezeichnung, z. B. GP 11 oder Geco FMJ 124gr", text: $name)
                Picker("Kaliber", selection: $caliber) {
                    Text("–").tag(Caliber?.none)
                    if !inUse.isEmpty {
                        Section("Deine Waffen") { ForEach(inUse) { Text($0.name).tag(Optional($0)) } }
                    }
                    Section("Alle") { ForEach(others) { Text($0.name).tag(Optional($0)) } }
                }
                .pickerStyle(.navigationLink)
                Section {
                    ForEach($lots) { $draft in
                        TextField("Losnummer", text: $draft.number)
                    }
                    .onDelete { lots.remove(atOffsets: $0) }
                    Button {
                        lots.insert(LotDraft(lot: nil, number: ""), at: 0)
                    } label: {
                        Label("Losnummer hinzufügen", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Losnummern")
                } footer: {
                    Text("Optional. Beim Erfassen eines Eintrags kannst du das Los auswählen.")
                }
                if ammunition != nil { Toggle("Archiviert", isOn: $isArchived) }
            }
            .navigationTitle(ammunition == nil ? "Neue Munition".loc : "Munition bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let target = ammunition ?? Ammunition(name: "")
                        target.name = name.trimmingCharacters(in: .whitespaces)
                        target.caliber = caliber
                        target.isArchived = isArchived
                        if ammunition == nil { context.insert(target); onCreate?(target) }
                        saveLots(to: target)
                        try? context.save()
                        dismiss()
                    }
                    .bold().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = ammunition?.name ?? ""
                caliber = ammunition?.caliber ?? suggestedCaliber
                isArchived = ammunition?.isArchived ?? false
                lots = (ammunition?.sortedLots() ?? []).map { LotDraft(lot: $0, number: $0.number) }
            }
        }
    }

    private func saveLots(to target: Ammunition) {
        let kept = Set(lots.compactMap { $0.lot?.persistentModelID })
        // Removed lots: delete unused ones, archive those already logged so old entries keep their lot.
        for old in target.sortedLots() where !kept.contains(old.persistentModelID) {
            if (old.entries ?? []).isEmpty { context.delete(old) } else { old.isArchived = true }
        }
        for draft in lots {
            let number = draft.number.trimmingCharacters(in: .whitespaces)
            if let lot = draft.lot {
                if !number.isEmpty { lot.number = number }
            } else if !number.isEmpty {
                let lot = AmmoLot(number: number)
                context.insert(lot)
                lot.ammunition = target
            }
        }
    }
}

// MARK: - Shooting ranges

struct RangeListView: View {
    @Query(sort: \ShootingRange.name) private var ranges: [ShootingRange]
    @State private var showArchived = false
    @State private var adding = false

    var body: some View {
        List(ranges.filter { showArchived || !$0.isArchived }) { r in
            NavigationLink { RangeDetailView(range: r) } label: {
                StatsLinkRow(name: r.name, subtitle: r.place, archived: r.isArchived, shots: (r.entries ?? []).totalShots)
            }
            .swipeActions { ArchiveButton(item: r) }
        }
        .overlay {
            if ranges.isEmpty {
                ContentUnavailableView("Keine Schiessanlagen", systemImage: "mappin.and.ellipse",
                                       description: Text("Füge die Anlagen hinzu, auf denen du schiesst."))
            }
        }
        .navigationTitle("Schiessanlagen")
        .toolbar {
            Toggle(isOn: $showArchived) { Label("Archivierte", systemImage: "archivebox") }.toggleStyle(.button)
            Button { adding = true } label: { Label("Hinzufügen", systemImage: "plus") }
        }
        .sheet(isPresented: $adding) { RangeEditorView(range: nil) }
    }
}

struct RangeEditorView: View {
    let range: ShootingRange?
    var onCreate: ((ShootingRange) -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var place = ""
    @State private var location: PickedLocation?
    @State private var isArchived = false
    @State private var bearing: Double?
    @State private var altitude: Double?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, z. B. Albisgüetli", text: $name)
                PlaceField(place: $place, location: $location)
                Section {
                    RangeBearingRow(bearing: $bearing)
                    LabeledContent("Höhe") {
                        TextField("m ü. M.", value: $altitude, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Optional. Mit Ort und Schussrichtung schlägt die App vor, woher die Sonne kommt.")
                }
                if range != nil { Toggle("Archiviert", isOn: $isArchived) }
            }
            .navigationTitle(range == nil ? "Neue Schiessanlage".loc : "Schiessanlage bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let target = range ?? ShootingRange(name: "")
                        target.name = name.trimmingCharacters(in: .whitespaces)
                        target.place = place.trimmingCharacters(in: .whitespaces)
                        target.address = location?.address ?? ""
                        target.latitude = location?.latitude
                        target.longitude = location?.longitude
                        target.shootingBearing = bearing.map(Compass.normalized)
                        target.altitude = altitude
                        target.isArchived = isArchived
                        if range == nil { context.insert(target); onCreate?(target) }
                        try? context.save()
                        dismiss()
                    }
                    .bold().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = range?.name ?? ""; place = range?.place ?? ""; isArchived = range?.isArchived ?? false
                location = range.flatMap(PickedLocation.init(range:))
                bearing = range?.shootingBearing; altitude = range?.altitude
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ArchiveButton<Item: ArchivableItem>: View {
    let item: Item
    var body: some View {
        Button {
            item.isArchived.toggle()
        } label: {
            Label(item.isArchived ? "Reaktivieren".loc : "Archivieren".loc,
                  systemImage: item.isArchived ? "tray.and.arrow.up" : "archivebox")
        }
        .tint(.orange)
    }
}

private struct AmmunitionRow: View {
    let ammunition: Ammunition

    var body: some View {
        HStack {
            CartridgeView(caliber: ammunition.caliber).frame(width: 18, height: 30)
            Text(ammunition.name).foregroundStyle(ammunition.isArchived ? .secondary : .primary)
            Spacer()
            Text((ammunition.entries ?? []).totalShots.formatted()).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
