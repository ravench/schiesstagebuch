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

    /// As the system's pickers in the same form show their value: in the tint from iOS 26 on, grey before.
    /// (`.secondary` in a menu label is a pale tint, which read as switched off; Raven 2026-11-24.)
    private static var valueStyle: AnyShapeStyle {
        if #available(iOS 26, *) { AnyShapeStyle(.tint) } else { AnyShapeStyle(Color(uiColor: .secondaryLabel)) }
    }

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
                .foregroundStyle(Self.valueStyle)
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
