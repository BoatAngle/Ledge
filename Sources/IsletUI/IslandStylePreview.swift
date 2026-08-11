import IsletCore
import SwiftUI

/// A miniature, non-interactive island for use inside Settings.
///
/// Reuses the real silhouette and the real compact views rather than mocking
/// them up, so what you tune is genuinely what you get — a hand-drawn
/// approximation would drift from the island the first time either changed.
public struct IslandStylePreview: View {
    public var activity: Activity
    public var style: ActivityStyle
    public var notchSize: CGSize
    public var isExpandedSample: Bool

    public init(
        activity: Activity,
        style: ActivityStyle,
        notchSize: CGSize = IslandMetrics.standardNotch,
        isExpandedSample: Bool = false
    ) {
        self.activity = activity
        self.style = style
        self.notchSize = notchSize
        self.isExpandedSample = isExpandedSample
    }

    private var metrics: IslandMetrics {
        IslandMetrics(notchSize: notchSize, screenWidth: 1_000, hasPhysicalNotch: true)
    }

    private var bodySize: CGSize {
        IslandGeometry.size(mode: .compact, metrics: metrics)
    }

    private var fillet: CGFloat { IslandGeometry.topFillet }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            IslandSilhouette(
                bodySize: bodySize,
                topFillet: fillet,
                bottomRadius: IslandGeometry.bottomRadius(for: .compact, metrics: metrics),
                hasDepth: true
            )
            .islandShadow(.resting)

            HStack(spacing: 0) {
                CompactLeadingView(activity: activity, height: bodySize.height, style: style)
                    .frame(width: sidePadding, height: bodySize.height)

                // Stands in for the camera housing so the preview shows the
                // same dead centre the real island has to work around.
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: notchSize.width * 0.7, height: bodySize.height * 0.5)
                    .frame(width: notchSize.width, height: bodySize.height)

                CompactTrailingView(activity: activity, height: bodySize.height, style: style)
                    .frame(width: sidePadding, height: bodySize.height)
            }
            .offset(x: fillet)
        }
        .frame(width: bodySize.width + fillet * 2, height: bodySize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .animation(IslandMotion.content, value: style)
    }

    private var sidePadding: CGFloat {
        max(0, (bodySize.width - notchSize.width) / 2)
    }
}

/// The preview sitting on a strip of "screen", so the black island has
/// something to be black *against*.
public struct IslandPreviewStage<Content: View>: View {
    public var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.top, 0)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
            .background {
                // A muted gradient rather than a photo: the point is to show the
                // island's edge against something, not to be decorative.
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.17, blue: 0.21),
                        Color(red: 0.09, green: 0.10, blue: 0.13),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
    }
}
