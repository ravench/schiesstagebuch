import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Preview and run the import from Schusszähler-Schiesstagebuch.
struct LegacyImportView: View {
    @Environment(\.term) private var term
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Caliber> { !$0.isArchived }, sort: \Caliber.name) private var calibers: [Caliber]

    /// Not opened automatically: presenting the picker while the sheet animates in
    /// made it reopen the same folder instead of entering it.
    @State private var picking = false
    /// Export files already in the app's own folder (Files › On My iPhone › Schiesstagebuch).
    @State private var found: [URL] = []
    @State private var plan: LegacyImport.Plan?
    @State private var loadPhotos = true
    @State private var running = false
    @State private var summary: LegacyImport.Summary?
    @State private var error: String?

    private static let types: [UTType] = [.tabSeparatedText, .plainText, .commaSeparatedText, .database]
        + [UTType(filenameExtension: "db"), UTType(filenameExtension: "tsv")].compactMap { $0 }

    var body: some View {
        NavigationStack {
            Form {
                if let summary {
                    Section {
                        Label("\(summary.entries) Einträge importiert", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        LabeledContent(term("Neue Waffen").loc, value: "\(summary.weapons)")
                        LabeledContent("Neue Schiessanlagen", value: "\(summary.ranges)")
                        LabeledContent("Neue Munition", value: "\(summary.ammo)")
                        LabeledContent("Fotos übernommen", value: "\(summary.photos)")
                        if summary.missingPhotos > 0 {
                            LabeledContent("Fotos nicht gefunden", value: "\(summary.missingPhotos)")
                        }
                    } footer: {
                        Text(term("Prüfe unter Waffen die Kategorie und die Kaliber der importierten Waffen.").loc)
                    }
                } else if let plan {
                    Section("Gefunden") {
                        LabeledContent("Einträge", value: "\(plan.rows.count)")
                        if plan.newRows.count < plan.rows.count {
                            LabeledContent("Davon schon importiert", value: "\(plan.rows.count - plan.newRows.count)")
                        }
                        LabeledContent("Schüsse", value: plan.newRows.reduce(0) { $0 + $1.shots }.formatted())
                        LabeledContent(term("Waffen").loc, value: plan.weapons.joined(separator: ", "))
                        LabeledContent("Schiessanlagen", value: "\(plan.ranges.count)")
                    }
                    let rangeRows = LegacyImport.rangeMatchRows(plan)
                    if !rangeRows.isEmpty {
                        Section {
                            ForEach(rangeRows) { row in
                                if row.options.count == 1 { rangeToggle(row) } else { rangePicker(row) }
                            }
                        } header: {
                            Text("Bekannte Schiessanlagen")
                        } footer: {
                            Text("Diese Anlagen sind schon in der App oder im Verzeichnis der Schweizer Schiessanlagen, erkannt an Name, Ort, Postleitzahl und Distanz. Schalte Zuordnungen aus, die nicht stimmen. Passen mehrere Anlagen, wähle die richtige. Ohne Zuordnung wird eine neue Anlage angelegt.")
                        }
                    }
                    if !plan.sighterSuggestions.isEmpty {
                        Section {
                            ForEach(plan.newRows.filter { plan.sighterSuggestions[$0.key] != nil }, id: \.self) { row in
                                sighterToggle(row, sighters: plan.sighterSuggestions[row.key] ?? 0)
                            }
                        } header: {
                            Text("Probeschüsse abziehen")
                        } footer: {
                            Text("Der Export enthält nur die Gesamtzahl der Schüsse. Ein Stich hat meist 10, 15–18, 20, 30 oder 60 Schüsse; was darüber liegt, wird als Probeschüsse erfasst. Schalte Einträge aus, bei denen das nicht stimmt.")
                        }
                    }
                    Section {
                        ForEach(ammoKeys(plan), id: \.self) { ammo in
                            Picker(ammo, selection: Binding(
                                get: { self.plan?.ammoCaliber[ammo] ?? "" },
                                set: { self.plan?.ammoCaliber[ammo] = $0.isEmpty ? nil : $0 })) {
                                Text("Kein Kaliber").tag("")
                                ForEach(calibers) { Text($0.name).tag($0.name) }
                                // A catalogue calibre the user does not have: created on import.
                                if let planned = self.plan?.ammoCaliber[ammo], !calibers.contains(where: { $0.name == planned }) {
                                    Text(planned).tag(planned)
                                }
                            }
                        }
                    } header: {
                        Text("Munition → Kaliber")
                    } footer: {
                        Text(term("Der Export enthält keine Kaliber. Jede Munition wird einem Kaliber zugeordnet; daraus ergeben sich die Kaliber deiner Waffen.").loc)
                    }
                    if plan.photoCount > 0 {
                        Section {
                            Toggle("Fotos aus der Fotomediathek übernehmen", isOn: $loadPhotos)
                        } footer: {
                            Text("Der Export enthält nur Verweise auf \(plan.photoCount) Fotos in deiner Mediathek. Sie werden gefunden, wenn die Fotos noch auf diesem Gerät oder in iCloud-Fotos sind.")
                        }
                    }
                    Section {
                        Button {
                            run(plan)
                        } label: {
                            if running { ProgressView() } else { Text("\(plan.newRows.count) Einträge importieren").bold() }
                        }
                        .disabled(running || plan.newRows.isEmpty)
                    }
                } else {
                    if !found.isEmpty {
                        Section("Im Ordner der App gefunden") {
                            ForEach(found, id: \.self) { url in
                                Button { load(url) } label: {
                                    Label(url.lastPathComponent, systemImage: url.pathExtension == "db" ? "cylinder.split.1x2" : "doc.text")
                                }
                            }
                        }
                    }
                    Section {
                        Button("Datei wählen …") { picking = true }
                    } footer: {
                        Text("In «\(LegacyImport.sourceAppName)» von \(LegacyImport.sourceDeveloper) unter Menü › Daten sichern / exportieren die Datei ShootCounter-Export.tsv oder data.db sichern und hier auswählen.")
                    }
                }
            }
            .navigationTitle(String(localized: "Import aus «\(LegacyImport.sourceAppName)»"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(summary == nil ? "Abbrechen".loc : "Fertig".loc) { dismiss() }.disabled(running)
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: Self.types) { result in
                switch result {
                case .success(let url): load(url)
                case .failure(let e): error = e.localizedDescription
                }
            }
            .alert("Import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
            .interactiveDismissDisabled(running)
            .onAppear { found = LegacyImport.candidates(in: URL.documentsDirectory) }
        }
    }

    private func sighterToggle(_ row: LegacyImport.Row, sighters: Int) -> some View {
        Toggle(isOn: Binding(
            get: { self.plan?.splitSighters.contains(row.key) ?? false },
            set: { on in
                if on { self.plan?.splitSighters.insert(row.key) } else { self.plan?.splitSighters.remove(row.key) }
            })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: [row.date.formatted(date: .numeric, time: .omitted), row.weapon, row.event]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                (Text("\(row.shots - sighters) Wertung + \(sighters) Probe") + Text(verbatim: " · \(row.result)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The range chosen for all keys of a preview line; nil = add a new range.
    private func rangeChoice(_ row: LegacyImport.RangeMatchRow) -> Binding<LegacyImport.RangeMatch.Target?> {
        Binding(
            get: { row.keys.lazy.compactMap { self.plan?.rangeChoice[$0] }.first },
            set: { target in for key in row.keys { self.plan?.rangeChoice[key] = target } })
    }

    private func rangeToggle(_ row: LegacyImport.RangeMatchRow) -> some View {
        let choice = rangeChoice(row)
        return Toggle(isOn: Binding(get: { choice.wrappedValue != nil },
                                    set: { choice.wrappedValue = $0 ? row.options[0].target : nil })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ([row.name] + row.weapons).joined(separator: " · "))
                Text(verbatim: "→ \(row.options[0].name)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Several ranges fit equally well: the user picks one or adds a new range.
    private func rangePicker(_ row: LegacyImport.RangeMatchRow) -> some View {
        Picker(selection: rangeChoice(row)) {
            Text("Neue Anlage anlegen").tag(LegacyImport.RangeMatch.Target?.none)
            ForEach(row.options, id: \.target) { option in
                Text(verbatim: option.name).tag(LegacyImport.RangeMatch.Target?.some(option.target))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ([row.name] + row.weapons).joined(separator: " · "))
                Text("Mehrere Anlagen passen").font(.caption).foregroundStyle(.secondary)
            }
        }
        .pickerStyle(.navigationLink)
    }

    private func ammoKeys(_ plan: LegacyImport.Plan) -> [String] {
        Array(Set(plan.rows.map(\.ammo).filter { !$0.isEmpty })).sorted()
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            plan = LegacyImport.plan(try LegacyImport.read(url), context: context)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run(_ plan: LegacyImport.Plan) {
        running = true
        Task {
            do {
                summary = try await LegacyImport.apply(plan, context: context, loadPhotos: loadPhotos)
            } catch {
                self.error = error.localizedDescription
            }
            running = false
        }
    }
}
