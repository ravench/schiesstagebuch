import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.term) private var term
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @Query private var events: [ShootingEvent]
    @Query(sort: \Weapon.name) private var weapons: [Weapon]
    @Query(sort: \ShootingRange.name) private var ranges: [ShootingRange]

    @State private var searchText = ""
    @State private var weaponFilter: Weapon?
    @AppStorage(Weapon.showSerialKey) private var showSerial = true
    @State private var rangeFilter: ShootingRange?
    @State private var yearFilter: Int?
    @State private var showingNewEvent = false
    /// The event just recorded: the journal opens it once its sheet is down, for the first Stich.
    @State private var created: ShootingEvent?
    @State private var path = NavigationPath()

    private var years: [Int] {
        Array(Set((entries.map(\.date) + events.map(\.date)).map { Calendar.current.component(.year, from: $0) })).sorted(by: >)
    }

    private var filtered: [Entry] {
        entries.filter { entry in
            entry.matches(searchText)
            && (weaponFilter == nil || entry.weapon == weaponFilter)
            && (rangeFilter == nil || entry.range == rangeFilter)
            && (yearFilter == nil || Calendar.current.component(.year, from: entry.date) == yearFilter)
        }
    }

    /// Events recorded without a Stich so far; a weapon filter cannot match them.
    private var emptyEvents: [ShootingEvent] {
        events.filter { event in
            event.stichCount == 0 && weaponFilter == nil && event.matches(searchText)
            && (rangeFilter == nil || event.range == rangeFilter)
            && (yearFilter == nil || Calendar.current.component(.year, from: event.date) == yearFilter)
        }
    }

    /// Events grouped by month, newest first.
    private var sections: [(month: Date, items: [JournalItem])] {
        let cal = Calendar.current
        let items = JournalItem.group(filtered, emptyEvents: emptyEvents)
        let grouped = Dictionary(grouping: items) {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.date))!
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    private var isFiltering: Bool { weaponFilter != nil || rangeFilter != nil || yearFilter != nil }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if entries.isEmpty && events.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Einträge", systemImage: "target")
                    } description: {
                        Text("Erfasse deinen ersten Schiesstag mit +.")
                    } actions: {
                        Button("Anlass erfassen") { showingNewEvent = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty && emptyEvents.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    list
                }
            }
            .navigationTitle("Schiesstagebuch")
            .searchable(text: $searchText, prompt: term("Anlass, Anlage, Waffe …").loc)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewEvent = true } label: { Label("Neuer Anlass", systemImage: "plus") }
                }
            }
            // The event first (date, range, Anlass); its Stiche are added on its screen, which opens next.
            .sheet(isPresented: $showingNewEvent, onDismiss: {
                if let created { path.append(created); self.created = nil }
            }, content: {
                EventEditorView(event: nil) { created = $0 }
            })
            .navigationDestination(for: Entry.self) { EntryDetailView(entry: $0) }
            .navigationDestination(for: ShootingEvent.self) { EventDetailView(event: $0) }
        }
    }

    private var list: some View {
        List {
            if isFiltering || !searchText.isEmpty {
                Section {
                    LabeledContent("Treffer", value: String(localized: "\(filtered.count) Einträge"))
                    LabeledContent("Schüsse", value: filtered.reduce(0) { $0 + $1.shotCount }.formatted())
                }
            }
            ForEach(sections, id: \.month) { section in
                Section {
                    ForEach(section.items) { item in
                        if item.isSingle, let entry = item.entries.first {
                            NavigationLink(value: entry) { EntryRow(entry: entry) }
                        } else if let event = item.event {
                            NavigationLink(value: event) { EventRow(event: event, entries: item.entries) }
                        }
                    }
                    .onDelete { offsets in
                        // Only the Stiche shown: a filter may hide others of the same event.
                        let items = offsets.map { section.items[$0] }
                        try? Deletion.delete(items.flatMap(\.entries), in: context)
                        for event in items.filter(\.entries.isEmpty).compactMap(\.event) { try? Deletion.delete(event, in: context) }
                    }
                } header: {
                    HStack {
                        Text(section.month, format: .dateTime.month(.wide).year())
                        Spacer()
                        Text("\(section.items.reduce(0) { $0 + $1.totalShots }.formatted()) Schuss")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var filterMenu: some View {
        Menu {
            Picker(term("Waffe").loc, selection: $weaponFilter) {
                Text(term("Alle Waffen").loc).tag(Weapon?.none)
                ForEach(weapons) { w in
                    PickerOption(title: w.name, subtitle: w.pickerSerial(show: showSerial)).tag(Optional(w))
                }
            }
            Picker("Schiessanlage", selection: $rangeFilter) {
                Text("Alle Anlagen").tag(ShootingRange?.none)
                ForEach(ranges) { Text($0.name).tag(Optional($0)) }
            }
            Picker("Jahr", selection: $yearFilter) {
                Text("Alle Jahre").tag(Int?.none)
                ForEach(years, id: \.self) { Text(String($0)).tag(Optional($0)) }
            }
            if isFiltering {
                Button("Filter zurücksetzen", role: .destructive) {
                    weaponFilter = nil; rangeFilter = nil; yearFilter = nil
                }
            }
        } label: {
            Label("Filter", systemImage: isFiltering
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }
}

struct EntryRow: View {
    let entry: Entry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 0) {
                Text(entry.date, format: .dateTime.day())
                    .font(.title3.bold().monospacedDigit())
                Text(entry.date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let range = entry.range {
                        Label(range.name, systemImage: "mappin.and.ellipse")
                    }
                    if let weapon = entry.weapon {
                        Label {
                            Text(weapon.name)
                        } icon: {
                            WeaponIcon(category: weapon.category).frame(width: 26, height: 10)
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.shotCount.formatted())
                    .font(.headline.monospacedDigit())
                Text("Schuss").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A list row for an event with several Stiche.
struct EventRow: View {
    let event: ShootingEvent
    /// The Stiche to count, e.g. those matching a search.
    let entries: [Entry]

    private var weapons: [Weapon] {
        var seen = Set<PersistentIdentifier>()
        return entries.compactMap(\.weapon).filter { seen.insert($0.persistentModelID).inserted }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 0) {
                Text(event.date, format: .dateTime.day())
                    .font(.title3.bold().monospacedDigit())
                Text(event.date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.name.isEmpty ? "Schiessen".loc : event.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(String(localized: "\(entries.count) Stiche"), systemImage: "list.number")
                    if let range = event.range {
                        Label(range.name, systemImage: "mappin.and.ellipse")
                    }
                    if weapons.count == 1, let weapon = weapons.first {
                        Label {
                            Text(weapon.name)
                        } icon: {
                            WeaponIcon(category: weapon.category).frame(width: 26, height: 10)
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(entries.totalShots.formatted())
                    .font(.headline.monospacedDigit())
                Text("Schuss").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
