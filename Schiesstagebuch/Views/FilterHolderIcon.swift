import SwiftUI

/// Icon for colour filters: an AXIA filter holder (a ring for the filter with a long U-shaped wire
/// loop above it), tilted 45° to the right.
struct FilterHolderIcon: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22

    var body: some View {
        Canvas { ctx, canvas in
            let g = FilterHolderGeometry(size: min(canvas.width, canvas.height))
            let tint = GraphicsContext.Shading.style(.tint)
            ctx.opacity = 0.25
            ctx.fill(g.lens, with: tint)
            ctx.opacity = 1
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
    static let wireWidth: CGFloat = 0.08
    /// Half the distance between the wire's two legs, and how far above the ring centre the loop's bend starts.
    static let legOffset: CGFloat = 0.42
    static let bendHeight: CGFloat = 2.2
    /// Room left around the icon, as a fraction of `size`.
    static let margin: CGFloat = 0.04

    private static var modelRing: Path { Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)) }

    private static var modelLens: Path {
        let r = 1 - ringWidth / 2
        return Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
    }

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

    /// Tilts the model and scales it so everything, strokes included, fits the square with a margin.
    private var transform: CGAffineTransform {
        let tilt = CGAffineTransform(rotationAngle: CGFloat(Self.tilt.radians))
        let outline = Self.modelRing.strokedPath(StrokeStyle(lineWidth: Self.ringWidth))
            .applying(tilt).boundingRect
            .union(Self.modelWire.strokedPath(StrokeStyle(lineWidth: Self.wireWidth, lineCap: .round)).applying(tilt).boundingRect)
        let scale = size * (1 - 2 * Self.margin) / max(outline.width, outline.height)
        return tilt
            .concatenating(CGAffineTransform(translationX: -outline.midX, y: -outline.midY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: size / 2, y: size / 2))
    }

    /// Points per model unit.
    private var scale: CGFloat { (transform.a * transform.a + transform.b * transform.b).squareRoot() }

    var ring: Path { Self.modelRing.applying(transform) }
    var lens: Path { Self.modelLens.applying(transform) }
    var wire: Path { Self.modelWire.applying(transform) }
    var ringLine: CGFloat { Self.ringWidth * scale }
    var wireLine: CGFloat { Self.wireWidth * scale }

    /// Everything drawn with the room it takes beyond its path (half the stroke), for checking that
    /// the icon stays inside its square.
    var all: [(path: Path, outset: CGFloat)] { [(lens, 0), (ring, ringLine / 2), (wire, wireLine / 2)] }
}
