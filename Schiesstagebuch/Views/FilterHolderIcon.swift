import SwiftUI

/// Icon for colour filters: an AXIA filter holder (a ring for the filter with a long U-shaped wire
/// loop above it), tilted 45° to the right.
struct FilterHolderIcon: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22

    var body: some View {
        Canvas { ctx, canvas in
            let g = FilterHolderGeometry(size: min(canvas.width, canvas.height))
            let tint = GraphicsContext.Shading.style(.tint)
            ctx.stroke(g.wire, with: tint, style: StrokeStyle(lineWidth: g.wireLine, lineCap: .round, lineJoin: .round))
            ctx.stroke(g.ring, with: tint, lineWidth: g.ringLine)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The parts of the filter holder icon, fitted into a square of `size` points (top-left at the origin).
/// Drawn in model units first (ring radius 1, centred at the origin, wire loop above), then tilted and fitted.
struct FilterHolderGeometry {
    let size: CGFloat

    /// How far the holder leans to the right.
    static let tilt = Angle.degrees(45)
    /// Line widths in model units (ring radius = 1).
    static let ringWidth: CGFloat = 0.18
    static let wireWidth: CGFloat = 0.12
    /// Half the distance between the wire's two legs, and how far above the ring centre the loop's bend starts.
    static let legOffset: CGFloat = 0.42
    static let bendHeight: CGFloat = 2.2
    /// Room left around the icon, as a fraction of `size`.
    static let margin: CGFloat = 0.04

    private static var modelRing: Path { Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)) }

    /// Left leg up from the ring, a round bend over the top, right leg back down to the ring.
    private static var modelWire: Path {
        let x = legOffset, foot = -(1 - x * x).squareRoot(), bend = -bendHeight, k: CGFloat = 0.5523 * x
        var p = Path()
        p.move(to: CGPoint(x: -x, y: foot))
        p.addLine(to: CGPoint(x: -x, y: bend))
        p.addCurve(to: CGPoint(x: 0, y: bend - x), control1: CGPoint(x: -x, y: bend - k), control2: CGPoint(x: -k, y: bend - x))
        p.addCurve(to: CGPoint(x: x, y: bend), control1: CGPoint(x: k, y: bend - x), control2: CGPoint(x: x, y: bend - k))
        p.addLine(to: CGPoint(x: x, y: foot))
        return p
    }

    private static var tiltTransform: CGAffineTransform { CGAffineTransform(rotationAngle: CGFloat(tilt.radians)) }

    /// Points along the wire's centre line in model units: up the left leg, round the bend, down the right leg.
    static var modelWirePoints: [CGPoint] {
        let x = legOffset, foot = -(1 - x * x).squareRoot(), bend = -bendHeight
        let bendPoints = (0...12).map { i -> CGPoint in
            let a = CGFloat.pi * CGFloat(i) / 12
            return CGPoint(x: -x * cos(a), y: bend - x * sin(a))
        }
        return [CGPoint(x: -x, y: foot)] + bendPoints + [CGPoint(x: x, y: foot)]
    }

    /// Tilts the model and scales it so everything, strokes included, fits the square with a margin.
    /// The extent is worked out from the geometry itself, not from path bounds (which can include curve control points).
    private var transform: CGAffineTransform {
        let tilt = Self.tiltTransform
        let ringReach = 1 + Self.ringWidth / 2, wireReach = Self.wireWidth / 2
        var minX = -ringReach, maxX = ringReach, minY = -ringReach, maxY = ringReach
        for p in Self.modelWirePoints.map({ $0.applying(tilt) }) {
            minX = min(minX, p.x - wireReach); maxX = max(maxX, p.x + wireReach)
            minY = min(minY, p.y - wireReach); maxY = max(maxY, p.y + wireReach)
        }
        let scale = size * (1 - 2 * Self.margin) / max(maxX - minX, maxY - minY)
        return tilt
            .concatenating(CGAffineTransform(translationX: -(minX + maxX) / 2, y: -(minY + maxY) / 2))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: size / 2, y: size / 2))
    }

    /// Points per model unit.
    private var scale: CGFloat { (transform.a * transform.a + transform.b * transform.b).squareRoot() }

    /// Ring centre and radius (to the middle of its stroke) in points.
    var ringCentre: CGPoint { CGPoint.zero.applying(transform) }
    var ringRadius: CGFloat { scale }
    /// The wire's centre line in points.
    var wirePoints: [CGPoint] { Self.modelWirePoints.map { $0.applying(transform) } }

    var ring: Path { Self.modelRing.applying(transform) }
    var wire: Path { Self.modelWire.applying(transform) }
    var ringLine: CGFloat { Self.ringWidth * scale }
    var wireLine: CGFloat { Self.wireWidth * scale }
}
