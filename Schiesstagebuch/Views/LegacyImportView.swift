import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Preview and run the import from the old Schusszähler app.
struct LegacyImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Caliber> { !$0.isArchived }, sort: \Caliber.name) private var calibers: [Caliber]

    @State private var picking = true
    @State private var plan: LegacyImport.Plan?
    @State private var loadPhotos = true
    @State private var running = false
    @State private var summary: LegacyImport.Summary?
    @State private var error: String?

    private static let types: [UTType] = [.tabSeparatedText, .plainText, .data] + [UTType(filenameExtension: "db")].compactMap { $0 }

    var body: some View {
        NavigationStack {
            Form {
                if let summary {
                    Section {
                        Label("\(summary.entries) Einträge importiert", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        LabeledContent("Neue Waffen", value: "\(summary.weapons)")
                        LabeledContent("Neue Schiessanlagen", value: "\(summary.ranges)")
                        LabeledContent("Neue Munition", value: "\(summary.ammo)")
                        LabeledContent("Fotos übernommen", value: "\(summary.photos)")
                        if summary.missingPhotos > 0 {
                            LabeledContent("Fotos nicht gefunden", value: "\(summary.missingPhotos)")
                        }
                    } footer: {
                        Text("Prüfe unter Waffen die Kategorie und die Kaliber der importierten Waffen.")
                    }
                } else if let plan {
                    Section("Gefunden") {
                        LabeledContent("Einträge", value: "\(plan.rows.count)")
                        if plan.newRows.count < plan.rows.count {
                            LabeledContent("Davon schon importiert", value: "\(plan.rows.count - plan.newRows.count)")
                        }
                        LabeledContent("Schüsse", value: plan.newRows.reduce(0) { $0 + $1.shots }.formatted())
                        LabeledContent("Waffen", value: plan.weapons.joined(separator: ", "))
                        LabeledContent("Schiessanlagen", value: "\(plan.ranges.count)")
                    }
                    Section {
                        ForEach(ammoKeys(plan), id: \.self) { ammo in
                            Picker(ammo, selection: Binding(
                                get: { self.plan?.ammoCaliber[ammo] ?? "" },
                                set: { self.plan?.ammoCaliber[ammo] = $0.isEmpty ? nil : $0 })) {
                                Text("Kein Kaliber").tag("")
                                ForEach(calibers) { Text($0.name).tag($0.name) }
                            }
                        }
                    } header: {
                        Text("Munition → Kaliber")
                    } footer: {
                        Text("Die alte App kannte keine Kaliber. Jede Munition wird einem Kaliber zugeordnet; daraus ergeben sich die Kaliber deiner Waffen.")
                    }
                    if plan.photoCount > 0 {
                        Section {
                            Toggle("Fotos aus der Fotomediathek übernehmen", isOn: $loadPhotos)
                        } footer: {
                            Text("Die alte App hat nur Verweise auf \(plan.photoCount) Fotos in deiner Mediathek gespeichert. Sie werden gefunden, wenn die Fotos noch auf diesem Gerät oder in iCloud-Fotos sind.")
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
        }
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
            summary = await LegacyImport.apply(plan, context: context, loadPhotos: loadPhotos)
            running = false
        }
    }
}
