import SwiftUI
import CoreLocation

/// The range field of the entry and event forms: opens a searchable list instead of a menu,
/// since the Swiss catalogue holds almost 2000 ranges.
struct RangePickerRow: View {
    @Binding var selection: ShootingRange?
    let ranges: [ShootingRange]
    var location: CLLocation?
    let add: () -> Void

    var body: some View {
        HStack {
            NavigationLink {
                RangePickerList(selection: $selection, ranges: ranges, location: location)
            } label: {
                LabeledContent("Schiessanlage") {
                    Text(selection?.name ?? "–").lineLimit(2).multilineTextAlignment(.trailing)
                }
            }
            Button(action: add) { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "\("Schiessanlage".loc) hinzufügen"))
        }
    }
}

struct RangePickerList: View {
    @Binding var selection: ShootingRange?
    let ranges: [ShootingRange]
    let location: CLLocation?

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        let shown = RangeSearch.results(ranges, matching: search, from: location, keeping: selection)
        List {
            if RangeSearch.words(search).isEmpty { row(nil) }
            ForEach(shown) { row($0) }
            if shown.isEmpty {
                Text("Keine passende Schiessanlage").foregroundStyle(.secondary)
            }
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
