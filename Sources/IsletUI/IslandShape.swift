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
    /// False at idle, where the island *is* the camera housing and any lift off
    /// pure black would show as a seam against the bezel.
    public var hasDepth: Bool

    /// Slack around the canvas so the blur has somewhere to bleed.
    private let pad: CGFloat = 30

    public init(
        bodySize: CGSize,
        minimalFrame: CGRect? = nil,
        topFillet: CGFloat,
        bottomRadius: CGFloat,
        goo: CGFloat = 0,
        hasDepth: Bool = true
    ) {
        self.bodySize = bodySize
        self.minimalFrame = minimalFrame
        self.topFillet = topFillet
        self.bottomRadius = bottomRadius
        self.goo = goo
        self.hasDepth = hasDepth
    }

    /// Total footprint including the fillet flare and, in `.split`, the
    /// detached circle out to the right.
    public var footprint: CGSize {
        let contentWidth = max(bodySize.width, minimalFrame?.maxX ?? 0)
        let contentHeight = max(bodySize.height, minimalFrame?.maxY ?? 0)
        return CGSize(width: contentWidth + topFillet * 2, height: contentHeight)
    }

    /// Width of the notch-shaped body including its fillet flare.
    private var bodyFootprintWidth: CGFloat { bodySize.width + topFillet * 2 }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // The metaball pass produces a silhouette; that silhouette then
            // masks the surface gradient. Filling the canvas with a gradient
            // directly isn't possible — `alphaThreshold` works on a flat colour
            // — so the mask is what lets the shape have depth *and* merge like
            // liquid.
            Rectangle()
                .fill(IslandDesign.surfaceFill(liftsAtBottom: hasDepth))
                .mask(alignment: .topLeading) { silhouetteMask }

            if hasDepth, goo <= 0.2 {
                rim
            }
        }
        .frame(width: footprint.width, height: footprint.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private var silhouetteMask: some View {
        Canvas { context, _ in
            if goo > 0.2 {
                // Added first so it runs last: blur smears the two forms into
                // one blob, then the threshold snaps that blob back to a hard
                // edge — the classic metaball recipe.
                context.addFilter(.alphaThreshold(min: 0.5, color: .black))
                context.addFilter(.blur(radius: goo))
            }
            context.drawLayer { layer in
                let body = CGRect(
                    x: pad,
                    y: pad,
                    width: bodyFootprintWidth,
                    height: bodySize.height
                )
                layer.fill(
                    NotchShape(topFillet: topFillet, bottomRadius: bottomRadius).path(in: body),
                    with: .color(.black)
                )
                if var circle = minimalFrame {
                    // Minimal frames are expressed relative to the body's
                    // origin, which sits inside the fillet flare.
                    circle = circle.offsetBy(dx: pad + topFillet, dy: pad)
                    layer.fill(Path(ellipseIn: circle), with: .color(.black))
                }
            }
        }
        .frame(
            width: footprint.width + pad * 2,
            height: footprint.height + pad * 2
        )
        .offset(x: -pad, y: -pad)
    }

    /// The lit lower edge. Suppressed mid-morph, where a stroke tracing a
    /// stretching blob reads as an outline rather than a highlight.
    @ViewBuilder
    private var rim: some View {
        NotchShape(topFillet: topFillet, bottomRadius: bottomRadius)
            .stroke(IslandDesign.rimHighlight, lineWidth: IslandDesign.rimWidth)
            .frame(width: bodyFootprintWidth, height: bodySize.height)

        if let minimalFrame {
            Circle()
                .stroke(IslandDesign.rimHighlight, lineWidth: IslandDesign.rimWidth)
                .frame(width: minimalFrame.width, height: minimalFrame.height)
                .offset(x: topFillet + minimalFrame.minX, y: minimalFrame.minY)
        }
    }
}
