import SwiftUI
import CoreLocation

/// The range field of the entry and event forms: opens a searchable list of the user's ranges and,
/// after them, the Swiss catalogue's almost 2000. The list ends with «Schiessanlage hinzufügen».
/// A catalogue range picked here is not saved yet: the form saves it with the Anlass (`saved(in:)`).
struct RangePickerRow: View {
    @Binding var selection: ShootingRange?
    /// All of the user's ranges, archived ones too: they hide their catalogue entries.
    let ranges: [ShootingRange]
    var location: CLLocation?

    var body: some View {
        NavigationLink {
            RangePickerList(selection: $selection, ranges: ranges, location: location)
        } label: {
            LabeledContent("Schiessanlage") {
                Text(selection?.name ?? "–").lineLimit(2).multilineTextAlignment(.trailing)
            }
        }
    }
}

struct RangePickerList: View {
    @Binding var selection: ShootingRange?
    let ranges: [ShootingRange]
    let location: CLLocation?

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var adding = false
    @State private var added = false

    var body: some View {
        let shown = RangeSearch.results(RangeChoice.all(ranges), matching: search, from: location, keeping: selection)
        List {
            Section {
                if RangeSearch.words(search).isEmpty { row(nil) }
                ForEach(shown) { row($0) }
                if shown.isEmpty {
                    Text("Keine passende Schiessanlage").foregroundStyle(.secondary)
                }
            } footer: {
                if shown.contains(where: { $0.item != nil }) { Text(RangeCatalog.attribution) }
            }
            // Last row, so it shows when nothing matches or at the end of the list.
            Button { adding = true } label: { Label("Schiessanlage hinzufügen", systemImage: "plus") }
        }
        .sheet(isPresented: $adding, onDismiss: closeIfAdded) {
            RangeEditorView(range: nil) { selection = $0; added = true }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Schiessanlage suchen")
        .autocorrectionDisabled()
        .navigationTitle("Schiessanlage")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Back to the form once a new range was saved; it is already the selection.
    private func closeIfAdded() {
        if added { dismiss() }
    }

    private func row(_ choice: RangeChoice?) -> some View {
        Button {
            selection = choice?.range()
            dismiss()
        } label: {
            HStack {
                PickerOption(title: choice?.name ?? "–",
                             subtitle: choice.flatMap { RangeSearch.subtitle(for: $0, from: location) })
                    .foregroundStyle(.primary)
                Spacer()
                if choice?.stands(for: selection) ?? (selection == nil) { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
