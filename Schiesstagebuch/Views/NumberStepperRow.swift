import SwiftUI

/// A number you can type freely or change with +/−. The buttons snap to the step grid,
/// so with step 50 a typed 95 goes to 100 or 50 (not 145 or 45).
struct NumberStepperRow: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...10_000
    var step: Int = 1
    /// Shown instead of 0, e.g. "Aus" for a disabled reminder.
    var zeroLabel: String? = nil

    var body: some View {
        HStack {
            Text(title.loc)
            Spacer()
            TextField(zeroLabel?.loc ?? "0", value: field, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Stepper(title.loc) {
                value = Self.snap(value, step: step, up: true, in: range)
            } onDecrement: {
                value = Self.snap(value, step: step, up: false, in: range)
            }
            .labelsHidden()
        }
    }

    /// With a zero label, 0 shows as the empty field's placeholder.
    private var field: Binding<Int?> {
        Binding(
            get: { zeroLabel != nil && value == 0 ? nil : value },
            set: { value = min(max($0 ?? 0, range.lowerBound), range.upperBound) }
        )
    }

    static func snap(_ v: Int, step: Int, up: Bool, in range: ClosedRange<Int>) -> Int {
        guard step > 1 else { return min(max(v + (up ? 1 : -1), range.lowerBound), range.upperBound) }
        let floorMultiple = Int((Double(v) / Double(step)).rounded(.down)) * step
        let next: Int
        if up {
            next = floorMultiple + step
        } else {
            next = floorMultiple == v ? v - step : floorMultiple
        }
        return min(max(next, range.lowerBound), range.upperBound)
    }
}
