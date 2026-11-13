import SwiftUI

/// One option of a `SearchablePicker`.
struct PickerChoice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var subtitle: String?
    /// Header of the group it is listed under, if the list has groups.
    var section: String?
    /// Left out until the search has text (the rare calibres of the catalogue).
    var searchOnly = false
    /// Replaces the comparison with title and subtitle, e.g. to find a calibre by its other names.
    var matches: ((String) -> Bool)?

    var id: Value { value }
}

extension PickerChoice {
    /// The choices of an optional selection: `none` first (if given), `items`, then `current` where it
    /// is not one of them (archived, or it no longer fits), so an old entry keeps showing its value.
    static func optional<T>(_ items: [T], keeping current: T? = nil, none: String? = "–",
                            title: (T) -> String, subtitle: (T) -> String? = { _ in nil }) -> [PickerChoice] where Value == T? {
        let all = items + (current.map { items.contains($0) ? [] : [$0] } ?? [])
        return (none.map { [PickerChoice(value: nil, title: $0)] } ?? [])
            + all.map { PickerChoice(value: $0, title: title($0), subtitle: subtitle($0)) }
    }
}

enum PickerSearch {
    /// A list with more choices than this gets a search field.
    static let limit = 10

    /// The choices that contain every word of `query` in their title or subtitle, in their order.
    static func results<V>(_ choices: [PickerChoice<V>], matching query: String) -> [PickerChoice<V>] {
        let words = query.split(whereSeparator: \.isWhitespace).map(folded)
        guard !words.isEmpty else { return choices.filter { !$0.searchOnly } }
        return choices.filter { c in
            if let matches = c.matches { return matches(query) }
            let text = folded(c.title + " " + (c.subtitle ?? ""))
            return words.allSatisfy(text.contains)
        }
    }

    /// Neighbouring choices with the same section, as the groups of the list.
    static func grouped<V>(_ choices: [PickerChoice<V>]) -> [(title: String?, choices: [PickerChoice<V>])] {
        choices.reduce(into: []) { groups, c in
            if let last = groups.indices.last, groups[last].title == c.section {
                groups[last].choices.append(c)
            } else {
                groups.append((c.section, [c]))
            }
        }
    }

    private static func folded(_ text: some StringProtocol) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// A form row that picks one of `choices`: the usual picker up to ten of them, a page with a
/// search field beyond that.
struct SearchablePicker<Value: Hashable, Row: View>: View {
    let title: String
    @Binding var selection: Value
    let choices: [PickerChoice<Value>]
    @ViewBuilder var row: (PickerChoice<Value>) -> Row

    var body: some View {
        if choices.count > PickerSearch.limit {
            NavigationLink {
                SearchablePickerList(title: title, selection: $selection, choices: choices, row: row)
            } label: {
                LabeledContent(title) {
                    Text(PickerValueLabel.text(choices.first { $0.value == selection }?.title)).lineLimit(1)
                }
            }
        } else {
            Picker(title, selection: $selection) {
                ForEach(choices) { row($0).tag($0.value) }
            }
        }
    }
}

extension SearchablePicker where Row == PickerOption {
    init(title: String, selection: Binding<Value>, choices: [PickerChoice<Value>]) {
        self.init(title: title, selection: selection, choices: choices) { PickerOption(title: $0.title, subtitle: $0.subtitle) }
    }
}

/// The page of a `SearchablePicker`: the choices under a search field; a tap picks one and goes back.
struct SearchablePickerList<Value: Hashable, Row: View>: View {
    let title: String
    @Binding var selection: Value
    let choices: [PickerChoice<Value>]
    @ViewBuilder var row: (PickerChoice<Value>) -> Row
    /// «Add new» as the last row, like in the menu this page stands in for.
    var add: (title: String, action: () -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        let groups = PickerSearch.grouped(PickerSearch.results(choices, matching: search))
        List {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group.choices) { choiceRow($0) }
                } header: {
                    if let title = group.title { Text(title) }
                }
            }
            if groups.isEmpty { Text("Keine Treffer").foregroundStyle(.secondary) }
            if let add {
                // Back to the form first: what gets added is the selection there.
                Button { dismiss(); add.action() } label: { Label(add.title, systemImage: "plus") }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Suchen")
        .autocorrectionDisabled()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choiceRow(_ choice: PickerChoice<Value>) -> some View {
        Button {
            selection = choice.value
            dismiss()
        } label: {
            HStack {
                row(choice).foregroundStyle(.primary)
                Spacer()
                if selection == choice.value { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}

extension SearchablePickerList where Row == PickerOption {
    init(title: String, selection: Binding<Value>, choices: [PickerChoice<Value>], add: (title: String, action: () -> Void)? = nil) {
        self.init(title: title, selection: selection, choices: choices,
                  row: { PickerOption(title: $0.title, subtitle: $0.subtitle) }, add: add)
    }
}
