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
    @State private var message: String?

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
                    Button { export() } label: { Label("Backup exportieren", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Backup wiederherstellen", systemImage: "square.and.arrow.down") }
                    Button { exportCSV() } label: { Label("Tagebuch als CSV", systemImage: "tablecells") }
                } header: {
                    Text("Daten")
                } footer: {
                    Text("Das Backup enthält alle Einträge, Fotos und Stammdaten. Beim Wiederherstellen werden vorhandene Einträge nicht doppelt angelegt.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                }
            }
            .navigationTitle("Einstellungen")
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
            .alert("Datensicherung", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            } message: { Text(message ?? "") }
        }
    }

    private func export() {
        do {
            exportType = .json
            exportName = "Schiesstagebuch-\(Date.now.formatted(.iso8601.year().month().day()))"
            exportDoc = BackupDocument(data: try Backup.export(context))
        }
        catch { message = "Export fehlgeschlagen: \(error.localizedDescription)" }
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
            message = "Wiederherstellen fehlgeschlagen: \(error.localizedDescription)"
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
        calibers.filter { (showArchived || !$0.isArchived) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
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
    var onCreate: ((Caliber) -> Void)? = nil
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
                    ForEach(CaliberCatalog.Category.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                if caliber != nil { Toggle("Archiviert", isOn: $isArchived) }
            }
            .navigationTitle(caliber == nil ? "Neues Kaliber" : "Kaliber bearbeiten")
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
        Dictionary(grouping: items.filter { showArchived || !$0.isArchived }) { $0.caliber?.name ?? "Ohne Kaliber" }
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
                                    HStack {
                                        CartridgeView(caliber: a.caliber).frame(width: 18, height: 30)
                                        Text(a.name).foregroundStyle(a.isArchived ? .secondary : .primary)
                                        Spacer()
                                        Text(a.totalShots.formatted()).monospacedDigit().foregroundStyle(.secondary)
                                    }
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
    var suggestedCaliber: Caliber? = nil
    var onCreate: ((Ammunition) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Caliber> { !$0.isArchived }, sort: \Caliber.name) private var calibers: [Caliber]
    @State private var name = ""
    @State private var caliber: Caliber?
    @State private var isArchived = false

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
                if ammunition != nil { Toggle("Archiviert", isOn: $isArchived) }
            }
            .navigationTitle(ammunition == nil ? "Neue Munition" : "Munition bearbeiten")
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
    var onCreate: ((ShootingRange) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var place = ""
    @State private var isArchived = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, z. B. Albisgüetli", text: $name)
                TextField("Ort (optional)", text: $place)
                if range != nil { Toggle("Archiviert", isOn: $isArchived) }
            }
            .navigationTitle(range == nil ? "Neue Schiessanlage" : "Schiessanlage bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let target = range ?? ShootingRange(name: "")
                        target.name = name.trimmingCharacters(in: .whitespaces)
                        target.place = place.trimmingCharacters(in: .whitespaces)
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
            }
        }
        .presentationDetents([.medium])
    }
}

struct ArchiveButton<Item: ArchivableItem>: View {
    let item: Item
    var body: some View {
        Button {
            item.isArchived.toggle()
        } label: {
            Label(item.isArchived ? "Reaktivieren" : "Archivieren",
                  systemImage: item.isArchived ? "tray.and.arrow.up" : "archivebox")
        }
        .tint(.orange)
    }
}
