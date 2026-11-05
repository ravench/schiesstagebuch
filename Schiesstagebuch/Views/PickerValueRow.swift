import SwiftUI

/// A form row with a title, a one-line picker value and an «add new» item at the end of its menu.
///
/// A plain `Picker` in a `Form` switches to a two-line layout when its value is too long
/// (e.g. "GP90 · 5.6 mm GP 90"): the value drops below the title and the row gets
/// clipped. This row keeps title, value and chevrons on one line and truncates the value instead.
struct PickerValueRow<Options: View>: View {
    let title: String
    /// The current selection's label, or nil for no selection.
    let value: String?
    /// The text of the last menu item, e.g. «Waffe hinzufügen» (already localized).
    let addTitle: String
    let add: () -> Void
    @ViewBuilder let options: () -> Options

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Menu {
                options()
                Divider()
                Button(action: add) { Label(addTitle, systemImage: "plus") }
            } label: {
                HStack(spacing: 4) {
                    Text(PickerValueLabel.text(value))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .foregroundStyle(.secondary)
            }
            // Keep «add new» at the bottom even when the menu opens upwards.
            .menuOrder(.fixed)
            .accessibilityLabel(title)
            .accessibilityValue(PickerValueLabel.text(value))
        }
    }
}

enum PickerValueLabel {
    /// What the closed row shows: the selection's label, or "–" when nothing is picked.
    static func text(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return "–" }
        return value
    }
}
