import SwiftUI

/// A form row with a title, a one-line picker value and an optional trailing button.
///
/// A plain `Picker` in a `Form` switches to a two-line layout when its value is too long
/// (e.g. "GP90 · 5.6 mm GP 90 (Swiss)"): the value drops below the title, a trailing
/// button floats out of line and the row gets clipped. This row keeps title, value,
/// chevrons and button on one line and truncates the value instead.
struct PickerValueRow<Options: View, Trailing: View>: View {
    let title: String
    /// The current selection's label, or nil for no selection.
    let value: String?
    @ViewBuilder let options: () -> Options
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Menu {
                options()
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
            .accessibilityLabel(title)
            .accessibilityValue(PickerValueLabel.text(value))
            trailing()
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
