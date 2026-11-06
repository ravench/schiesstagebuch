import SwiftUI
import UIKit

/// Settings › Filter: the switch for recording colour filters, and while it is on, the colour filters and
/// adjustment lenses you own (only those appear in entries) and your own ones.
struct FilterSettingsView: View {
    @AppStorage(FilterCatalog.key) private var catalogData = Data()
    @AppStorage(SportFeatures.key) private var features: SportFeatures = []
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable {
        let id = UUID()
        var original: FilterColor.Filter?
    }

    private var catalog: FilterCatalog { FilterCatalog(data: catalogData) }

    private func update(_ change: (inout FilterCatalog) -> Void) {
        var c = catalog
        change(&c)
        catalogData = c.data
    }

    /// One switch per built-in filter: on means the user owns it and it shows in the entry picker.
    private func ownToggles(_ filters: [FilterColor.Filter]) -> some View {
        ForEach(filters, id: \.name) { f in
            Toggle(isOn: Binding(get: { catalog.owns(f.name) },
                                 set: { on in update { $0.setOwned(f.name, on) } })) {
                Label { Text(f.name) } icon: { FilterSwatch(filter: f) }
            }
        }
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { features.contains(.filter) }, set: { features.set(.filter, $0) })) {
                    Label { Text("Filter erfassen") } icon: { FilterHolderIcon() }
                }
            } footer: {
                Text("Bis zu zwei pro Eintrag.")
            }

            // Like Wi-Fi in iOS Settings: the filters show while the switch is on.
            if features.contains(.filter) {
                Section {
                    ForEach(catalog.custom, id: \.name) { f in
                        Button { editing = EditTarget(original: f) } label: {
                            Label { Text(f.name).foregroundStyle(Color.primary) } icon: { FilterSwatch(filter: f) }
                        }
                    }
                    .onDelete { idx in
                        let names = idx.map { catalog.custom[$0].name }
                        update { c in names.forEach { c.remove($0) } }
                    }
                    Button { editing = EditTarget(original: nil) } label: {
                        Label("Filter hinzufügen", systemImage: "plus")
                    }
                } header: {
                    Text("Eigene Filter")
                }

                Section {
                    ownToggles(FilterColor.filters)
                } header: {
                    Text("Brillenfilter (AXIA)")
                } footer: {
                    Text("Wähle die Filter, die du besitzt. Nur diese erscheinen in der Auswahl. Bereits erfasste Einträge behalten ihren Filter.")
                }

                Section {
                    ownToggles(FilterColor.wyss)
                } header: {
                    Text("Filterrad Wyss (Stgw 90)")
                }

                Section {
                    ownToggles(FilterColor.gruenigElmiger)
                } header: {
                    Text("Filterräder Grünig + Elmiger (Stgw 90)")
                }

                Section {
                    ownToggles(FilterColor.dioptre)
                } header: {
                    Text("Korrekturlinsen")
                }
            }
        }
        .navigationTitle("Filter (Mehrzahl)")
        .sheet(item: $editing) { target in
            FilterEditorView(original: target.original, catalog: catalog) { saved in
                update { $0.save(saved, replacing: target.original?.name) }
            }
        }
    }
}

/// Add or edit one of the user's own filters: name, colour and whether it is polarised.
struct FilterEditorView: View {
    let original: FilterColor.Filter?
    let catalog: FilterCatalog
    let onSave: (FilterColor.Filter) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = Color.yellow
    @State private var polarised = false

    private var draft: FilterColor.Filter {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return FilterColor.Filter(name: name, red: Double(r), green: Double(g), blue: Double(b), polarised: polarised)
    }

    private var problem: FilterCatalog.NameProblem? { catalog.problem(with: name, replacing: original?.name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    ColorPicker("Farbe", selection: $color, supportsOpacity: false)
                    Toggle("Polarisiert", isOn: $polarised)
                } footer: {
                    if problem == .duplicate { Text("Diesen Namen gibt es schon.") }
                }
                Section {
                    HStack {
                        Spacer()
                        FilterSwatch(filter: draft, size: 64)
                        Spacer()
                    }
                }
            }
            .navigationTitle(original == nil ? "Neuer Filter".loc : "Filter bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { onSave(draft); dismiss() }.disabled(problem != nil)
                }
            }
            .onAppear {
                guard let original else { return }
                name = original.name
                color = Color(.sRGB, red: original.red, green: original.green, blue: original.blue)
                polarised = original.polarised
            }
        }
    }
}
