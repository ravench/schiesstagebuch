import SwiftUI

/// One Passe (or the sighters) in the entry editor: a box per shot with the shot number above it,
/// the total on the right unless `showsTotal` is off.
/// The boxes take numbers only and open the number pad; «Weiter» above it (a space, ";", "+" or the
/// Next key on a full keyboard) moves on to the next box. The empty box for the
/// next shot only shows while one of this Passe's boxes has the cursor.
struct ShotBoxesRow: View {
    let title: Text
    @Binding var boxes: ShotBoxes
    var showsTotal = true
    @FocusState private var focused: Int?

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 6)]

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
                ForEach(0..<boxes.visibleCount(editing: focused != nil), id: \.self) { box($0) }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: focused) { _, now in
            if now == nil { boxes.removeEmptyBoxes() }
        }
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

    private func box(_ i: Int) -> some View {
        let value = Binding(
            get: { boxes.values.indices.contains(i) ? boxes.values[i] : "" },
            set: { if let next = boxes.set($0, at: i) { focused = next } }
        )
        return VStack(spacing: 2) {
            Text((i + 1).formatted())
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            ShotField(value: value)
                .keyboardType(.decimalPad)
                .submitLabel(.next)
                .onSubmit { next(after: i) }
                .focused($focused, equals: i)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(focused == i ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: focused == i ? 2 : 1)
                )
                .accessibilityLabel(Text("Schuss \(i + 1)"))
        }
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
