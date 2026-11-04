import SwiftUI

/// A Passe entered «Pro Passe»: its shot count and points, both empty until typed.
struct PasseTotalDraft: Identifiable {
    let id = UUID()
    var shots: Int?
    var points: Double?
    var total: PasseTotal { PasseTotal(shots: shots ?? 0, points: points ?? 0) }
}

/// The Passen of the «Pro Passe» form in the entry editor: one row per Passe with shots and
/// points side by side, swipe to delete, and a button for the next Passe.
struct PasseTotalsRows: View {
    @Binding var passen: [PasseTotalDraft]

    var body: some View {
        ForEach($passen) { $passe in
            row(number: (passen.firstIndex { $0.id == passe.id } ?? 0) + 1, passe: $passe)
        }
        .onDelete { passen.remove(atOffsets: $0) }
        Button {
            // Passen of a Stich usually have the same number of shots.
            passen.append(PasseTotalDraft(shots: passen.last?.shots))
        } label: {
            Label("Passe hinzufügen", systemImage: "plus.circle")
        }
    }

    private func row(number: Int, passe: Binding<PasseTotalDraft>) -> some View {
        HStack {
            Text("Passe \(number)").foregroundStyle(.secondary)
            Spacer()
            TextField("Schüsse", value: passe.shots, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 56)
                .accessibilityLabel(Text("Schüsse"))
            Text("Schuss").foregroundStyle(.secondary)
            TextField("Punkte", value: passe.points, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 72)
                .accessibilityLabel(Text("Punkte"))
            Text("Punkte").foregroundStyle(.secondary)
        }
        .monospacedDigit()
    }
}
