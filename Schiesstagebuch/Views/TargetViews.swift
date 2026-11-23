import SwiftUI
import SwiftData

/// Settings › Scheiben: the user's targets, each with a name and how a shot is scored.
struct TargetListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShootingTarget.name) private var targets: [ShootingTarget]
    @State private var editing: ShootingTarget?
    @State private var deleting: ShootingTarget?
    @State private var adding = false
    @State private var choosingTemplate = false

    var body: some View {
        Group {
            if targets.isEmpty {
                ContentUnavailableView {
                    Label("Keine Scheiben", systemImage: "target")
                } description: {
                    Text("Erfasse die Scheiben, auf die du schiesst. Beim Stich wählst du dann die Scheibe, und bei den Einzelschüssen bietet die App nur ihre Werte an.")
                } actions: {
                    Button("Aus Vorlage hinzufügen") { choosingTemplate = true }.buttonStyle(.borderedProminent)
                    Button("Eigene Scheibe") { adding = true }
                }
            } else {
                List {
                    ForEach(targets) { target in
                        Button { editing = target } label: { TargetRow(target: target) }
                            .foregroundStyle(.primary)
                            .swipeActions(allowsFullSwipe: false) {
                                Button {
                                    // Only a target with Stiche asks first: they lose it and the maximum it gave them.
                                    if (target.entries ?? []).isEmpty { context.delete(target) } else { deleting = target }
                                } label: { Label("Löschen", systemImage: "trash") }.tint(.red)
                            }
                    }
                }
            }
        }
        .confirmationDialog("Scheibe löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { target in
            Button("Löschen", role: .destructive) { context.delete(target) }
        } message: { _ in
            Text("Die Stiche mit dieser Scheibe bleiben erhalten, haben dann aber keine Scheibe und kein daraus berechnetes Maximum mehr.")
        }
        .navigationTitle("Scheiben")
        .toolbar {
            Menu {
                Button("Aus Vorlage hinzufügen", systemImage: "list.bullet") { choosingTemplate = true }
                Button("Eigene Scheibe", systemImage: "square.and.pencil") { adding = true }
            } label: {
                Label("Hinzufügen", systemImage: "plus")
            }
        }
        .sheet(isPresented: $adding) { TargetEditorView(target: nil) }
        .sheet(item: $editing) { TargetEditorView(target: $0) }
        .sheet(isPresented: $choosingTemplate) { TargetTemplateList() }
    }
}

struct TargetRow: View {
    let target: ShootingTarget

    var body: some View {
        HStack(spacing: 12) {
            TargetFaceView(face: TargetCatalog.face(of: target))
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                Text(verbatim: "\(target.mode.title.loc) · \(target.scoringSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The bundled templates (Targets.json) by group; tapping one adds it to the user's targets.
/// Swiss and ISSF templates are listed open; the other countries sit closed under «Weitere Länder»
/// so the list stays short (Raven 2026-11-23). A search shows every matching template, open.
struct TargetTemplateList: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var targets: [ShootingTarget]
    @State private var search = ""
    @State private var openCountries: Set<String> = []

    var body: some View {
        NavigationStack {
            let groups = TargetCatalog.grouped(matching: search)
            let searching = !search.trimmingCharacters(in: .whitespaces).isEmpty
            let main = groups.filter { searching || TargetCatalog.mainGroups.contains($0.group) }
            let others = searching ? [] : groups.filter { !TargetCatalog.mainGroups.contains($0.group) }
            List {
                ForEach(main, id: \.group) { group in
                    Section(group.group.loc) {
                        ForEach(group.items) { row($0) }
                    }
                }
                if !others.isEmpty {
                    Section("Weitere Länder") {
                        ForEach(others, id: \.group) { group in
                            DisclosureGroup(isExpanded: Binding(
                                get: { openCountries.contains(group.group) },
                                set: { if $0 { openCountries.insert(group.group) } else { openCountries.remove(group.group) } })) {
                                ForEach(group.items) { row($0) }
                            } label: {
                                LabeledContent(group.group.loc) { Text(verbatim: "\(group.items.count)") }
                            }
                        }
                    }
                }
            }
            .overlay {
                if groups.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Scheibe, Land oder Distanz")
            .navigationTitle("Vorlagen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }

    private func row(_ item: TargetCatalog.Item) -> some View {
        let added = targets.contains { $0.templateID == item.id }
        return Button {
            context.insert(TargetCatalog.target(from: item))
            dismiss()
        } label: {
            HStack(spacing: 12) {
                TargetFaceView(face: item.face)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                    Text(verbatim: item.targetScoring.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if added { Image(systemName: "checkmark").foregroundStyle(.secondary) }
            }
        }
        .foregroundStyle(.primary)
        .disabled(added)
    }
}

/// Add or edit a target: its name and either a range (min to max) or a list of fixed values.
struct TargetEditorView: View {
    let target: ShootingTarget?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var mode: ShootingTarget.Mode = .values
    @State private var minValue: Double? = 0
    @State private var maxValue: Double? = 10.9
    @State private var valuesText = "10 9 8 7 6 5 4 3 2 1 0"
    @State private var didLoad = false

    private var scoring: TargetScoring? {
        switch mode {
        case .range:
            guard let minValue, let maxValue, minValue >= 0, minValue < maxValue else { return nil }
            return .range(min: minValue, max: maxValue)
        case .values:
            return TargetScoring.parseValues(valuesText).map(TargetScoring.values)
        }
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && scoring != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Wertungsmodus", selection: $mode) {
                        ForEach(ShootingTarget.Mode.allCases) { Text($0.title.loc).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    switch mode {
                    case .range:
                        LabeledContent("Minimum") {
                            TextField("0", value: $minValue, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Maximum") {
                            TextField("10.9", value: $maxValue, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    case .values:
                        TextField("10 9 8 7 6 5 4 3 2 1 0", text: $valuesText)
                            .keyboardType(.numbersAndPunctuation)
                    }
                } footer: {
                    switch mode {
                    case .range:
                        Text("Einzelschüsse tippst du mit der Zahlentastatur, Werte ausserhalb des Bereichs werden rot markiert. Zum Beispiel 0 bis 10.9 für Zehntelwertung oder 0 bis 100 für A100.")
                    case .values:
                        Text("Die möglichen Werte eines Schusses, durch Leerzeichen getrennt, der beste zuerst, z. B. «5 4 3 2 1 0». Bei den Einzelschüssen erscheinen sie als Tasten, und nach jedem Tipp geht es zum nächsten Schuss.")
                    }
                }
            }
            .navigationTitle(target == nil ? "Neue Scheibe".loc : "Scheibe bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() }.bold().disabled(!canSave) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad, let target else { return }
        didLoad = true
        name = target.name
        mode = target.mode
        minValue = target.minValue; maxValue = target.maxValue
        if !target.valuesText.isEmpty { valuesText = target.valuesText }
    }

    private func save() {
        guard let scoring else { return }
        let t = target ?? ShootingTarget(name: "", scoring: scoring)
        if target == nil { context.insert(t) }
        t.name = name.trimmingCharacters(in: .whitespaces)
        t.edit(scoring: scoring)
        dismiss()
    }
}
