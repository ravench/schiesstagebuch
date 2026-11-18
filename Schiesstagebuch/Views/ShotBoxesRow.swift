import SwiftUI

/// One Passe (or the sighters) in the entry editor: a box per shot with the shot number above it,
/// the total on the right unless `showsTotal` is off.
/// How a shot is entered follows the Stich's target (`scoring`, Raven 2026-11-16):
/// - fixed values (A5, B4, rapid fire …): tapping a box shows the target's values as buttons below
///   the row; a tap fills the box and moves on to the next shot. Like a keyboard they belong to one
///   box at a time: they close when another row opens its own or a text field is edited (tester 2026-11-17);
/// - a range or no target: the boxes take numbers on the number pad; «Weiter» above it (a space, ";",
///   "+" or the Next key on a full keyboard) moves on to the next box. A value outside the target's
///   range is marked red.
/// The empty box for the next shot only shows while one of this Passe's boxes is being edited.
struct ShotBoxesRow: View {
    let title: Text
    @Binding var boxes: ShotBoxes
    var showsTotal = true
    var scoring: TargetScoring?
    @FocusState private var focused: Int?
    /// Fixed values: the box the value buttons fill.
    @State private var selected: Int?
    /// Tells the rows apart in `keysOpened`.
    @State private var id = UUID()
    /// Posted by the row that opens its value buttons (object: its `id`).
    private static let keysOpened = Notification.Name("ShotBoxesRow.keysOpened")

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 6)]

    private var fixedValues: [Double]? {
        if case let .values(list) = scoring { return list }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                title.foregroundStyle(.secondary)
                Spacer()
                let shots = Score.parseShots(boxes.text)
                if showsTotal, !shots.isEmpty {
                    Text(ScoreFormat.points(shots.reduce(0, +))).monospacedDigit().bold()
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(0..<boxes.visibleCount(editing: focused != nil || selected != nil), id: \.self) { box($0) }
            }
            if let values = fixedValues, let i = selected {
                ShotValueButtons(values: values, clear: boxes.values.indices.contains(i) && !boxes.values[i].isEmpty) { value in
                    if let value {
                        selected = boxes.set(TargetScoring.valuesText([value]) + " ", at: i)
                    } else {
                        boxes.set("", at: i)
                    }
                } done: {
                    selected = nil
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: focused) { _, now in
            if now == nil, selected == nil { boxes.removeEmptyBoxes() }
        }
        .onChange(of: selected) { _, now in
            guard now != nil else { return boxes.removeEmptyBoxes() }
            NotificationCenter.default.post(name: Self.keysOpened, object: id)
            // The value buttons replace the keyboard of the field edited until now.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.keysOpened)) { note in
            if note.object as? UUID != id { selected = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)
            .merge(with: NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification))) { _ in
            selected = nil
        }
        // Another Scheibe hides the value buttons: close them, so the empty boxes go too.
        .onChange(of: scoring) { selected = nil }
        // The number pad has no Next key.
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                if let i = focused { Button("Weiter") { next(after: i) } }
            }
        }
    }

    private func next(after i: Int) {
        focused = i + 1 < boxes.values.count ? i + 1 : nil
    }

    private func isAllowed(_ value: String) -> Bool {
        guard let scoring else { return true }
        return scoring.allowsAll(value)
    }

    @ViewBuilder
    private func box(_ i: Int) -> some View {
        let value = boxes.values.indices.contains(i) ? boxes.values[i] : ""
        let active = focused == i || selected == i
        let border = active ? Color.accentColor : isAllowed(value) ? Color.secondary.opacity(0.5) : Color.red
        VStack(spacing: 2) {
            Text((i + 1).formatted())
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Group {
                if fixedValues != nil {
                    Button { selected = selected == i ? nil : i } label: {
                        Text(verbatim: value.isEmpty ? " " : value)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    ShotField(value: Binding(get: { value }, set: { if let next = boxes.set($0, at: i) { focused = next } }))
                        .keyboardType(.decimalPad)
                        .submitLabel(.next)
                        .onSubmit { next(after: i) }
                        .focused($focused, equals: i)
                }
            }
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(border, lineWidth: active || !isAllowed(value) ? 2 : 1)
            )
            .accessibilityLabel(Text("Schuss \(i + 1)"))
            .accessibilityValue(Text(verbatim: value))
        }
    }
}

/// The values a shot can have on the Stich's target, as buttons, plus clearing the box and closing.
private struct ShotValueButtons: View {
    let values: [Double]
    /// Whether the box has a value to clear.
    let clear: Bool
    /// A value, or nil to clear the box.
    let pick: (Double?) -> Void
    let done: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 52, maximum: 70), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(values, id: \.self) { v in
                    Button { pick(v) } label: {
                        Text(verbatim: ScoreFormat.points(v)).monospacedDigit().bold().frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("shotValue-\(ScoreFormat.points(v))")
                }
            }
            HStack {
                if clear {
                    Button("Löschen", systemImage: "delete.left", role: .destructive) { pick(nil) }
                }
                Spacer()
                Button("Fertig") { done() }.bold()
            }
            .buttonStyle(.borderless)
        }
        .padding(.top, 4)
    }
}

/// One box's text field. SwiftUI leaves a field's text alone when its binding drops part of what was
/// typed (a letter stayed on screen), so the field keeps the typed text itself and takes the box's value back.
private struct ShotField: View {
    @Binding var value: String
    @State private var text = ""

    var body: some View {
        TextField("", text: $text)
            .onChange(of: text) { _, typed in
                value = typed
                // What the box keeps of it; reading `value` back here still gives the old one.
                let kept = ShotBoxes.tokens(typed).first ?? ""
                if kept != typed { text = kept }
            }
            .onChange(of: value, initial: true) { _, new in
                if new != text { text = new }
            }
    }
}
