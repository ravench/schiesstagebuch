import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @Query(sort: \Weapon.name) private var weapons: [Weapon]
    @Query(sort: \ShootingRange.name) private var ranges: [ShootingRange]

    @State private var searchText = ""
    @State private var weaponFilter: Weapon?
    @State private var rangeFilter: ShootingRange?
    @State private var yearFilter: Int?
    @State private var showingNewEntry = false

    private var years: [Int] {
        Array(Set(entries.map { Calendar.current.component(.year, from: $0.date) })).sorted(by: >)
    }

    private var filtered: [Entry] {
        entries.filter { entry in
            entry.matches(searchText)
            && (weaponFilter == nil || entry.weapon == weaponFilter)
            && (rangeFilter == nil || entry.range == rangeFilter)
            && (yearFilter == nil || Calendar.current.component(.year, from: entry.date) == yearFilter)
        }
    }

    /// Entries grouped by month, newest first.
    private var sections: [(month: Date, entries: [Entry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.date))!
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    private var isFiltering: Bool { weaponFilter != nil || rangeFilter != nil || yearFilter != nil }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Einträge", systemImage: "target")
                    } description: {
                        Text("Erfasse deinen ersten Schiesstag mit +.")
                    } actions: {
                        Button("Eintrag erfassen") { showingNewEntry = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    list
                }
            }
            .navigationTitle("Schiesstagebuch")
            .searchable(text: $searchText, prompt: "Anlass, Anlage, Waffe …")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewEntry = true } label: { Label("Neuer Eintrag", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showingNewEntry) {
                EntryEditorView(entry: nil)
            }
            .navigationDestination(for: Entry.self) { EntryDetailView(entry: $0) }
        }
    }

    private var list: some View {
        List {
            if isFiltering || !searchText.isEmpty {
                Section {
                    LabeledContent("Treffer", value: "\(filtered.count) Einträge")
                    LabeledContent("Schüsse", value: filtered.reduce(0) { $0 + $1.shotCount }.formatted())
                }
            }
            ForEach(sections, id: \.month) { section in
                Section {
                    ForEach(section.entries) { entry in
                        NavigationLink(value: entry) { EntryRow(entry: entry) }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(section.entries[i]) }
                    }
                } header: {
                    HStack {
                        Text(section.month, format: .dateTime.month(.wide).year())
                        Spacer()
                        Text("\(section.entries.reduce(0) { $0 + $1.shotCount }.formatted()) Schuss")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Waffe", selection: $weaponFilter) {
                Text("Alle Waffen").tag(Weapon?.none)
                ForEach(weapons) { Text($0.name).tag(Optional($0)) }
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
                Text(entry.event.isEmpty ? "Schiessen" : entry.event)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let range = entry.range {
                        Label(range.name, systemImage: "mappin.and.ellipse")
                    }
                    if let weapon = entry.weapon {
                        Label(weapon.name, systemImage: "scope")
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

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
