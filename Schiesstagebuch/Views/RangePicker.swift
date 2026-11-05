import SwiftUI
import CoreLocation

/// The range field of the entry and event forms: opens a searchable list instead of a menu,
/// since the Swiss catalogue holds almost 2000 ranges. The list ends with «Schiessanlage hinzufügen».
struct RangePickerRow: View {
    @Binding var selection: ShootingRange?
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
        let shown = RangeSearch.results(ranges, matching: search, from: location, keeping: selection)
        List {
            if RangeSearch.words(search).isEmpty { row(nil) }
            ForEach(shown) { row($0) }
            if shown.isEmpty {
                Text("Keine passende Schiessanlage").foregroundStyle(.secondary)
            }
            // Last row, so it shows when nothing matches or at the end of the list.
            Button { adding = true } label: { Label("Schiessanlage hinzufügen", systemImage: "plus") }
        }
        .sheet(isPresented: $adding, onDismiss: { if added { dismiss() } }) {
            RangeEditorView(range: nil) { selection = $0; added = true }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Schiessanlage suchen")
        .autocorrectionDisabled()
        .navigationTitle("Schiessanlage")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ range: ShootingRange?) -> some View {
        Button {
            selection = range
            dismiss()
        } label: {
            HStack {
                PickerOption(title: range?.name ?? "–",
                             subtitle: range.flatMap { RangeSearch.subtitle(for: $0, from: location) })
                    .foregroundStyle(.primary)
                Spacer()
                if selection == range { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
