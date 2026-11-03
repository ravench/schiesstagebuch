import SwiftUI

/// Icon for the filter list: an AXIA-style filter holder hanging from the glasses' rail on its joint,
/// with a tinted filter in front and a second one stacked behind it.
struct FilterHolderIcon: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22

    var body: some View {
        Canvas { ctx, canvas in
            let shapes = FilterHolderGeometry(size: min(canvas.width, canvas.height))
            let solid = GraphicsContext.Shading.style(.tint)
            ctx.fill(shapes.rail, with: solid)
            ctx.fill(shapes.arm, with: solid)
            ctx.fill(shapes.joint, with: solid)
            ctx.opacity = 0.5
            ctx.stroke(shapes.backFilter, with: solid, lineWidth: shapes.backLine)
            ctx.opacity = 0.35
            ctx.fill(shapes.lens, with: solid)
            ctx.opacity = 1
            ctx.stroke(shapes.frontRing, with: solid, lineWidth: shapes.frontLine)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The parts of the filter holder icon in a square of `size` points, top-left at the origin.
struct FilterHolderGeometry {
    let size: CGFloat

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * size, y: y * size, width: w * size, height: h * size)
    }

    private func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGRect {
        rect(cx - r, cy - r, 2 * r, 2 * r)
    }

    /// Centre and radius of the front filter ring, as fractions of `size`.
    static let ringCentre = CGPoint(x: 0.50, y: 0.64)
    static let ringRadius: CGFloat = 0.31 - 0.045

    var rail: Path { Path(roundedRect: rect(0.08, 0.03, 0.84, 0.10), cornerRadius: 0.05 * size) }
    var arm: Path { Path(rect(0.465, 0.10, 0.07, 0.27)) }
    var joint: Path { Path(ellipseIn: circle(0.50, 0.24, 0.07)) }
    var frontLine: CGFloat { 0.09 * size }
    var backLine: CGFloat { 0.05 * size }
    var frontRing: Path { Path(ellipseIn: circle(Self.ringCentre.x, Self.ringCentre.y, Self.ringRadius)) }
    var backFilter: Path { Path(ellipseIn: circle(Self.ringCentre.x + 0.07, Self.ringCentre.y - 0.03, 0.31 - 0.025)) }
    var lens: Path { Path(ellipseIn: circle(Self.ringCentre.x, Self.ringCentre.y, 0.22)) }

    /// Everything drawn with the room it takes beyond its path (half the stroke), for checking that
    /// the icon stays inside its square.
    var all: [(path: Path, outset: CGFloat)] {
        [(rail, 0), (arm, 0), (joint, 0), (lens, 0), (frontRing, frontLine / 2), (backFilter, backLine / 2)]
    }
}
