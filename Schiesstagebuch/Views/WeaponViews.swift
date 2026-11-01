import SwiftUI
import SwiftData

struct WeaponsTab: View {
    var body: some View { NavigationStack { WeaponsListView() } }
}

/// Weapons overview with maintenance status at a glance. Used as a tab and from Einstellungen.
struct WeaponsListView: View {
    @Query(sort: \Weapon.name) private var weapons: [Weapon]
    @State private var adding = false
    @State private var showArchived = false

    private var visible: [Weapon] { weapons.filter { showArchived || !$0.isArchived } }

    var body: some View {
        Group {
                if weapons.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Waffen", systemImage: "scope")
                    } description: {
                        Text("Lege deine Waffen mit ihren Kalibern an.")
                    } actions: {
                        Button("Waffe hinzufügen") { adding = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List(visible) { w in
                        NavigationLink { WeaponDetailView(weapon: w) } label: { WeaponRow(weapon: w) }
                    }
                }
            }
            .navigationTitle("Waffen")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $showArchived) { Label("Archivierte zeigen", systemImage: "archivebox") }
                        .toggleStyle(.button)
                    Button { adding = true } label: { Label("Waffe hinzufügen", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $adding) { WeaponEditorView(weapon: nil) }
    }
}

struct WeaponRow: View {
    let weapon: Weapon

    var body: some View {
        HStack(spacing: 12) {
            WeaponIcon(category: weapon.category)
                .frame(width: 56, height: 22)
                .foregroundStyle(weapon.isArchived ? .secondary : .primary)
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(weapon.name).font(.headline)
                if weapon.isArchived { Image(systemName: "archivebox").foregroundStyle(.secondary).imageScale(.small) }
                Spacer()
                Text("\((weapon.entries ?? []).totalShots.formatted()) Schuss")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            if !weapon.caliberSummary.isEmpty {
                Text(weapon.caliberSummary).font(.subheadline).foregroundStyle(.secondary)
            }
            if !weapon.serialNumber.isEmpty {
                Text("\("Nr.".loc) \(weapon.serialNumber)").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(MaintenanceKind.allCases) { kind in
                    let s = weapon.status(kind)
                    if s.hasReminder { MaintenanceBadge(status: s) }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct MaintenanceBadge: View {
    let status: MaintenanceStatus

    private var color: Color { status.isDue ? .red : status.isDueSoon ? .orange : .green }

    var body: some View {
        Label(status.kind.title, systemImage: status.isDue ? "exclamationmark.triangle.fill" : status.kind.icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Maintenance block shown on the weapon detail screen.
struct MaintenanceSection: View {
    @Bindable var weapon: Weapon
    @Environment(\.modelContext) private var context
    @State private var logging: MaintenanceKind?
    @State private var showHistory = false

    var body: some View {
        Section {
            ForEach(MaintenanceKind.allCases) { kind in
                let s = weapon.status(kind)
                HStack(alignment: .top) {
                    Image(systemName: kind.icon).frame(width: 24).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(kind.title).font(.headline)
                            if s.hasReminder { MaintenanceBadge(status: s).labelStyle(.iconOnly) }
                        }
                        Text(s.summary).font(.subheadline).foregroundStyle(.secondary)
                        if let due = s.dueText {
                            Text(due).font(.subheadline).foregroundStyle(s.isDue ? .red : .secondary)
                        }
                    }
                    Spacer()
                    Button("Erfassen") { logging = kind }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            if !(weapon.maintenance ?? []).isEmpty {
                Button("Verlauf anzeigen") { showHistory = true }
            }
        } header: {
            Text("Pflege")
        } footer: {
            Text("Erinnerungen stellst du unter Bearbeiten ein.")
        }
        .sheet(item: $logging) { kind in MaintenanceEditorView(weapon: weapon, kind: kind) }
        .sheet(isPresented: $showHistory) { MaintenanceHistoryView(weapon: weapon) }
    }
}

struct MaintenanceEditorView: View {
    let weapon: Weapon
    let kind: MaintenanceKind
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Datum", selection: $date, in: ...Date.now, displayedComponents: .date)
                TextField("Notizen (optional)", text: $notes, axis: .vertical).lineLimit(2...5)
            }
            .navigationTitle("\(kind.title) erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        context.insert(MaintenanceRecord(kind: kind, date: date, notes: notes, weapon: weapon))
                        // A service usually includes a cleaning.
                        if kind == .service {
                            context.insert(MaintenanceRecord(kind: .cleaning, date: date, notes: "Mit Service".loc, weapon: weapon))
                        }
                        try? context.save()
                        MaintenanceNotifier.refresh(weapon)
                        dismiss()
                    }.bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct MaintenanceHistoryView: View {
    let weapon: Weapon
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var records: [MaintenanceRecord] { (weapon.maintenance ?? []).sorted { $0.date > $1.date } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { r in
                    VStack(alignment: .leading) {
                        Label(r.kind.title, systemImage: r.kind.icon)
                        Text(r.date, format: .dateTime.day().month().year()).font(.subheadline).foregroundStyle(.secondary)
                        if !r.notes.isEmpty { Text(r.notes).font(.subheadline) }
                    }
                }
                .onDelete { idx in
                    idx.map { records[$0] }.forEach(context.delete)
                    try? context.save()
                    MaintenanceNotifier.refresh(weapon)
                }
            }
            .navigationTitle("Pflegeverlauf")
            .toolbar { Button("Fertig") { dismiss() } }
        }
    }
}

struct WeaponEditorView: View {
    let weapon: Weapon?
    var onCreate: ((Weapon) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Caliber> { !$0.isArchived }, sort: \Caliber.name) private var allCalibers: [Caliber]

    @State private var name = ""
    @State private var serialNumber = ""
    @State private var category: WeaponCategory = .other
    @State private var calibers: Set<Caliber> = []
    @State private var defaultCaliber: Caliber?
    @State private var isArchived = false
    @State private var cleaningShots = 0
    @State private var cleaningDays = 0
    @State private var serviceShots = 0
    @State private var serviceDays = 0
    @State private var dayCountingRaw = ""
    @State private var choosingCalibers = false
    @State private var confirmDelete = false
    @State private var didLoad = false

    private var sortedSelection: [Caliber] { calibers.sorted { $0.name < $1.name } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, z. B. SIG P210", text: $name)
                    TextField("Seriennummer (optional)", text: $serialNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker(selection: $category) {
                        ForEach(WeaponCategory.allCases) { c in
                            HStack(spacing: 12) {
                                WeaponIcon(category: c).frame(width: 48, height: 18)
                                Text(c.title)
                            }
                            .tag(c)
                        }
                    } label: {
                        HStack {
                            Text("Kategorie")
                            Spacer()
                            WeaponIcon(category: category).frame(width: 48, height: 18).foregroundStyle(.secondary)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Button { choosingCalibers = true } label: {
                        LabeledContent("Kaliber", value: calibers.isEmpty ? "Wählen".loc : "\(calibers.count)")
                    }
                    if calibers.count > 1 {
                        Picker("Standard", selection: $defaultCaliber) {
                            ForEach(sortedSelection) { Text($0.name).tag(Optional($0)) }
                        }
                    }
                    ForEach(sortedSelection) { c in
                        HStack {
                            CartridgeView(caliber: c).frame(width: 18, height: 30)
                            Text(c.name)
                            Spacer()
                            if c == defaultCaliber { Text("Standard").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                } header: {
                    Text("Kaliber")
                } footer: {
                    Text("Beim Erfassen werden nur diese Kaliber angeboten. Das Standardkaliber ist vorausgewählt.")
                }

                intervalSection(.cleaning, shots: $cleaningShots, days: $cleaningDays)
                intervalSection(.service, shots: $serviceShots, days: $serviceDays)

                Section {
                    Picker("Tage zählen", selection: $dayCountingRaw) {
                        Text(String(localized: "Standard (\(DayCounting.appDefault.title))")).tag("")
                        ForEach(DayCounting.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } footer: {
                    Text("Eine Reinigung setzt Schüsse und Tage der Reinigung zurück, ein Service zusätzlich die des Service.")
                }

                if weapon != nil {
                    Section {
                        Toggle("Archiviert", isOn: $isArchived)
                        Button("Waffe löschen", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Archivierte Waffen erscheinen nicht mehr bei neuen Einträgen, bleiben aber in Tagebuch und Statistik.")
                    }
                }
            }
            .navigationTitle(weapon == nil ? "Neue Waffe".loc : "Waffe bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save).bold()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $choosingCalibers) {
                CaliberMultiPicker(all: allCalibers, selection: $calibers,
                                   preferred: category.preferredCaliberCategories)
            }
            .onChange(of: calibers) { _, new in
                if let d = defaultCaliber, new.contains(d) { return }
                defaultCaliber = new.sorted { $0.name < $1.name }.first
            }
            .confirmationDialog("Waffe löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let weapon { context.delete(weapon); try? context.save() }
                    dismiss()
                }
            } message: {
                Text("Einträge bleiben erhalten, verlieren aber die Waffe. Archivieren behält alles.")
            }
            .onAppear(perform: load)
        }
    }

    private func intervalSection(_ kind: MaintenanceKind, shots: Binding<Int>, days: Binding<Int>) -> some View {
        Section {
            NumberStepperRow(title: "Nach Schüssen", value: shots, range: 0...20_000,
                             step: kind == .cleaning ? 50 : 500, zeroLabel: "Aus")
            NumberStepperRow(title: "Nach Tagen", value: days, range: 0...730,
                             step: kind == .cleaning ? 7 : 30, zeroLabel: "Aus")
        } header: {
            Label("Erinnerung \(kind.title)", systemImage: kind.icon)
        } footer: {
            Text("Erinnert, sobald eine der beiden Grenzen seit der letzten \(kind.title) erreicht ist.")
        }
    }

    private func load() {
        guard !didLoad, let weapon else { didLoad = true; return }
        name = weapon.name
        serialNumber = weapon.serialNumber
        category = weapon.category
        calibers = Set(weapon.calibers ?? [])
        defaultCaliber = weapon.defaultCaliber
        isArchived = weapon.isArchived
        cleaningShots = weapon.cleaningIntervalShots; cleaningDays = weapon.cleaningIntervalDays
        serviceShots = weapon.serviceIntervalShots; serviceDays = weapon.serviceIntervalDays
        dayCountingRaw = weapon.dayCountingRaw
        didLoad = true
    }

    private func save() {
        let target = weapon ?? Weapon(name: "")
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.serialNumber = serialNumber.trimmingCharacters(in: .whitespaces)
        target.category = category
        target.calibers = Array(calibers)
        target.defaultCaliber = defaultCaliber.flatMap { calibers.contains($0) ? $0 : nil }
        target.isArchived = isArchived
        target.cleaningIntervalShots = cleaningShots; target.cleaningIntervalDays = cleaningDays
        target.serviceIntervalShots = serviceShots; target.serviceIntervalDays = serviceDays
        target.dayCountingRaw = dayCountingRaw
        if weapon == nil { context.insert(target); onCreate?(target) }
        try? context.save()
        if cleaningShots + cleaningDays + serviceShots + serviceDays > 0 {
            Task {
                await MaintenanceNotifier.requestAuthorization()
                MaintenanceNotifier.refresh(target)
            }
        } else {
            MaintenanceNotifier.refresh(target)
        }
        dismiss()
    }
}

/// Searchable, grouped multi-select over the calibre catalogue.
struct CaliberMultiPicker: View {
    let all: [Caliber]
    @Binding var selection: Set<Caliber>
    /// Catalogue groups shown first (e.g. handgun calibres for a pistol).
    var preferred: [String] = []
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var adding = false

    private var groups: [(String, [Caliber])] {
        let matches = all.filter { $0.matches(search) }
        let order = preferred + CaliberCatalog.Category.allCases.map(\.rawValue).filter { !preferred.contains($0) }
        return Dictionary(grouping: matches) { $0.category.isEmpty ? CaliberCatalog.Category.other.rawValue : $0.category }
            .sorted { (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99) }
            .map { ($0.key, $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selection.isEmpty && search.isEmpty {
                    Section("Ausgewählt") {
                        ForEach(selection.sorted { $0.name < $1.name }) { row($0) }
                    }
                }
                ForEach(groups, id: \.0) { group in
                    Section(group.0.loc) { ForEach(group.1) { row($0) } }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kaliber suchen")
            .navigationTitle("Kaliber wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { adding = true } label: { Label("Eigenes Kaliber", systemImage: "plus") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.bold() }
            }
            .sheet(isPresented: $adding) {
                CaliberEditorView(caliber: nil, initialName: search) { selection.insert($0) }
            }
        }
    }

    private func row(_ c: Caliber) -> some View {
        Button {
            if selection.contains(c) { selection.remove(c) } else { selection.insert(c) }
        } label: {
            HStack {
                CartridgeView(caliber: c).frame(width: 18, height: 30)
                VStack(alignment: .leading) {
                    Text(c.name).foregroundStyle(.primary)
                    if !c.aliasSummary.isEmpty {
                        Text(c.aliasSummary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selection.contains(c) { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
