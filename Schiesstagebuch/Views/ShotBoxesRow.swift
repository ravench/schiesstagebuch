import SwiftUI

/// One Passe in the entry editor: a box per shot with the shot number above it, the Passe total on the right.
/// A space, ";" or "+" (or the keyboard's Next key) moves on to the next box. The empty box for the
/// next shot only shows while one of this Passe's boxes has the cursor.
struct ShotBoxesRow: View {
    let number: Int
    @Binding var boxes: ShotBoxes
    @FocusState private var focused: Int?

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Passe \(number)").foregroundStyle(.secondary)
                Spacer()
                let shots = Score.parseShots(boxes.text)
                if !shots.isEmpty {
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
            TextField("", text: value)
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.next)
                .onSubmit { focused = i + 1 < boxes.values.count ? i + 1 : nil }
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
