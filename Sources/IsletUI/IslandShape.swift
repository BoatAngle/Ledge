import SwiftUI

/// The island's silhouette: square across the top where it meets the bezel,
/// rounded along the bottom, with concave fillets joining the two.
///
/// Those fillets are the whole trick. Without them the island reads as a black
/// rectangle stuck to the screen; with them it reads as a shape carved out of
/// the display, which is what macOS itself does around the camera housing.
public struct NotchShape: Shape {
    /// Radius of the concave corner where the island meets the screen edge.
    public var topFillet: CGFloat
    /// Radius of the convex lower corners.
    public var bottomRadius: CGFloat

    public init(topFillet: CGFloat, bottomRadius: CGFloat) {
        self.topFillet = topFillet
        self.bottomRadius = bottomRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topFillet, bottomRadius) }
        set {
            topFillet = newValue.first
            bottomRadius = newValue.second
        }
    }

    /// `rect` is the *total* footprint, including the width the fillets flare
    /// out to. The solid body is inset by `topFillet` on each side.
    public func path(in rect: CGRect) -> Path {
        var path = Path()

        let fillet = max(0, min(topFillet, rect.width / 2, rect.height))
        let bodyWidth = rect.width - fillet * 2
        let radius = max(0, min(bottomRadius, bodyWidth / 2, rect.height - fillet))

        let left = rect.minX + fillet
        let right = rect.maxX - fillet

        // Screen edge, far left.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Concave sweep down into the body's left wall.
        path.addQuadCurve(
            to: CGPoint(x: left, y: rect.minY + fillet),
            control: CGPoint(x: left, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: left, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: left + radius, y: rect.maxY),
            control: CGPoint(x: left, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right - radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: right, y: rect.maxY - radius),
            control: CGPoint(x: right, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY + fillet))
        // Concave sweep back out to the screen edge.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: right, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Draws the island's silhouette — body plus, in `.split`, a detached circle —
/// through a metaball filter so the two forms stretch and merge like liquid
/// instead of snapping apart.
///
/// `goo` is pulsed only during structural changes. At rest it sits at zero and
/// the shapes render perfectly crisp; a permanent blur/threshold pass would
/// soften the fillets for no benefit.
public struct IslandSilhouette: View {
    public var bodySize: CGSize
    public var minimalFrame: CGRect?
    public var topFillet: CGFloat
    public var bottomRadius: CGFloat
    public var goo: CGFloat
    public var fill: Color

    /// Slack around the canvas so the blur has somewhere to bleed.
    private let pad: CGFloat = 30

    public init(
        bodySize: CGSize,
        minimalFrame: CGRect? = nil,
        topFillet: CGFloat,
        bottomRadius: CGFloat,
        goo: CGFloat = 0,
        fill: Color = .black
    ) {
        self.bodySize = bodySize
        self.minimalFrame = minimalFrame
        self.topFillet = topFillet
        self.bottomRadius = bottomRadius
        self.goo = goo
        self.fill = fill
    }

    /// Total footprint including the fillet flare and, in `.split`, the
    /// detached circle out to the right.
    public var footprint: CGSize {
        let contentWidth = max(bodySize.width, minimalFrame?.maxX ?? 0)
        let contentHeight = max(bodySize.height, minimalFrame?.maxY ?? 0)
        return CGSize(width: contentWidth + topFillet * 2, height: contentHeight)
    }

    public var body: some View {
        Canvas { context, _ in
            if goo > 0.2 {
                // Added first so it runs last: blur smears the two forms into
                // one blob, then the threshold snaps that blob back to a hard
                // edge — the classic metaball recipe.
                context.addFilter(.alphaThreshold(min: 0.5, color: fill))
                context.addFilter(.blur(radius: goo))
            }
            context.drawLayer { layer in
                let body = CGRect(
                    x: pad,
                    y: pad,
                    width: bodySize.width + topFillet * 2,
                    height: bodySize.height
                )
                layer.fill(
                    NotchShape(topFillet: topFillet, bottomRadius: bottomRadius).path(in: body),
                    with: .color(fill)
                )
                if var circle = minimalFrame {
                    // Minimal frames are expressed relative to the body's
                    // origin, which sits inside the fillet flare.
                    circle = circle.offsetBy(dx: pad + topFillet, dy: pad)
                    layer.fill(Path(ellipseIn: circle), with: .color(fill))
                }
            }
        }
        .frame(
            width: footprint.width + pad * 2,
            height: footprint.height + pad * 2
        )
        .offset(x: -pad, y: -pad)
        .allowsHitTesting(false)
    }
}
