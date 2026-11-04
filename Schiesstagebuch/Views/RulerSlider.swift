import SwiftUI

/// The maths behind `RulerSlider`, kept apart from the view so it can be tested.
/// The ruler shows `halfSpan` units either side of the value under the centre mark.
struct RulerScale: Equatable {
    var range: ClosedRange<Double>
    var step: Double
    /// Units shown left and right of the centre mark (0.5 shows 1 unit across the ruler).
    var halfSpan: Double = 0.5
    /// Every `majorEvery` steps gets a long tick with a number.
    var majorEvery: Int = 5

    struct Tick: Equatable {
        var value: Double
        var isMajor: Bool
        /// Whole units get the longest tick.
        var isWhole: Bool
    }

    /// Points on screen for one unit when the ruler is `width` points wide.
    func pointsPerUnit(width: Double) -> Double {
        width / (2 * halfSpan)
    }

    /// Rounds to the nearest step and keeps the value in the range.
    func snapped(_ v: Double) -> Double {
        let steps = ((v - range.lowerBound) / step).rounded()
        let s = range.lowerBound + steps * step
        // Round to the step's decimals so 0.1 steps never show 2.3000000000000003.
        let r = (min(max(s, range.lowerBound), range.upperBound) / step).rounded() * step
        return (r * 1_000_000).rounded() / 1_000_000
    }

    /// Dragging the ruler right lowers the value, like pulling a tape measure.
    func value(from start: Double, translation: Double, width: Double) -> Double {
        guard width > 0 else { return snapped(start) }
        return snapped(start - translation / pointsPerUnit(width: width))
    }

    /// Horizontal position of `tick` when `value` sits under the centre mark.
    func x(of tick: Double, at value: Double, width: Double) -> Double {
        width / 2 + (tick - value) * pointsPerUnit(width: width)
    }

    /// The ticks that are on screen (plus one step either side), never outside the range.
    func ticks(around value: Double) -> [Tick] {
        let first = max(range.lowerBound, value - halfSpan - step)
        let last = min(range.upperBound, value + halfSpan + step)
        // The small slack keeps 1.5000000000000002 steps from rounding up to the next tick.
        let startIndex = Int(((first - range.lowerBound) / step - 1e-6).rounded(.up))
        let endIndex = Int(((last - range.lowerBound) / step + 1e-6).rounded(.down))
        guard startIndex <= endIndex else { return [] }
        return (startIndex...endIndex).map { i in
            let v = snapped(range.lowerBound + Double(i) * step)
            let n = Int((v / step).rounded())
            let isWhole = abs(v - v.rounded()) < step / 2
            return Tick(value: v, isMajor: isWhole || n % majorEvery == 0, isWhole: isWhole)
        }
    }
}

/// A horizontal ruler that slides under a fixed centre mark, for values that need finer control
/// than a slider gives (diopter, iris, ring). Shows ±0.5 units, snaps to 0.1, flicks with momentum.
struct RulerSlider: View {
    let title: String
    @Binding var value: Double
    var scale: RulerScale

    /// The value shown while the ruler moves; `value` itself only takes snapped values.
    @State private var dragStart: Double?
    @State private var shown: Double?

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            RulerTicks(value: shown ?? value, scale: scale)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { g in
                            let start = dragStart ?? value
                            dragStart = start
                            shown = scale.value(from: start, translation: Double(g.translation.width), width: width)
                            if let shown, shown != value { value = shown }
                        }
                        .onEnded { g in
                            let start = dragStart ?? value
                            let end = scale.value(from: start, translation: Double(g.predictedEndTranslation.width), width: width)
                            dragStart = nil
                            withAnimation(.easeOut(duration: 0.35)) {
                                value = end
                                shown = nil
                            }
                        })
        }
        .frame(height: 44)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(Text(title.loc))
        .accessibilityValue(Text(SightSettings.format(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = scale.snapped(value + scale.step)
            case .decrement: value = scale.snapped(value - scale.step)
            @unknown default: break
            }
        }
    }
}

/// The drawn ruler. Animatable so a flick glides to its end value.
private struct RulerTicks: View, Animatable {
    var value: Double
    let scale: RulerScale

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width), h = Double(size.height)
            let ink = GraphicsContext.Shading.color(.secondary)
            for tick in scale.ticks(around: value) {
                let x = scale.x(of: tick.value, at: value, width: w)
                let len = tick.isWhole ? h * 0.42 : tick.isMajor ? h * 0.3 : h * 0.18
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: len))
                ctx.stroke(p, with: ink, lineWidth: tick.isMajor ? 1.5 : 1)
                if tick.isMajor {
                    ctx.draw(Text(SightSettings.format(tick.value)).font(.caption2).monospacedDigit()
                                .foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: h * 0.72))
                }
            }
            // Fixed centre mark.
            var mark = Path()
            mark.move(to: CGPoint(x: w / 2, y: 0))
            mark.addLine(to: CGPoint(x: w / 2, y: h * 0.55))
            ctx.stroke(mark, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        // Ticks fade out towards the edges.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                                     .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }
}
