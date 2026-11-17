import SwiftUI
import SwiftData

/// Settings › Scheiben: the user's targets, each with a name and how a shot is scored.
struct TargetListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShootingTarget.name) private var targets: [ShootingTarget]
    @State private var editing: ShootingTarget?
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
                    }
                    .onDelete { offsets in offsets.map { targets[$0] }.forEach { context.delete($0) } }
                }
            }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(target.name)
            Text(verbatim: "\(target.mode.title.loc) · \(target.scoringSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The bundled templates (Targets.json) by group; tapping one adds it to the user's targets.
struct TargetTemplateList: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var targets: [ShootingTarget]

    var body: some View {
        NavigationStack {
            List {
                ForEach(TargetCatalog.grouped(), id: \.group) { group in
                    Section(group.group.loc) {
                        ForEach(group.items) { item in
                            let added = targets.contains { $0.templateID == item.id }
                            Button {
                                context.insert(TargetCatalog.target(from: item))
                                dismiss()
                            } label: {
                                HStack {
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
                }
            }
            .navigationTitle("Vorlagen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
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
                            TextField("10,9", value: $maxValue, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    case .values:
                        TextField("10 9 8 7 6 5 4 3 2 1 0", text: $valuesText)
                            .keyboardType(.numbersAndPunctuation)
                    }
                } footer: {
                    switch mode {
                    case .range:
                        Text("Einzelschüsse tippst du mit der Zahlentastatur, Werte ausserhalb des Bereichs werden rot markiert. Zum Beispiel 0 bis 10,9 für Zehntelwertung oder 0 bis 100 für A100.")
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
        t.scoring = scoring
        dismiss()
    }
}
