import CoreGraphics
import Foundation

/// Physical facts about the display the island is living on.
public struct IslandMetrics: Equatable, Sendable {
    /// The camera housing's bounds, or a synthesized stand-in on displays that
    /// have no notch.
    public var notchSize: CGSize
    public var screenWidth: CGFloat
    /// False on external monitors and pre-2021 Macs — we draw a floating pill
    /// instead of hugging real hardware.
    public var hasPhysicalNotch: Bool

    public init(notchSize: CGSize, screenWidth: CGFloat, hasPhysicalNotch: Bool) {
        self.notchSize = notchSize
        self.screenWidth = screenWidth
        self.hasPhysicalNotch = hasPhysicalNotch
    }

    /// What a 14"/16" MacBook Pro camera housing measures in points. Used
    /// verbatim as the virtual island on notchless displays so the app looks
    /// identical everywhere.
    public static let standardNotch = CGSize(width: 200, height: 32)

    public static func synthesized(screenWidth: CGFloat) -> IslandMetrics {
        IslandMetrics(notchSize: standardNotch, screenWidth: screenWidth, hasPhysicalNotch: false)
    }
}

/// Resolves a mode plus its content into concrete pixel geometry.
///
/// Every number here was tuned against the real thing: the island should feel
/// like it grew out of the notch, so the compact state keeps the notch's exact
/// height and only the corner radii and width move.
public enum IslandGeometry {
    // MARK: Tunables

    /// Extra width per side in the compact state.
    ///
    /// Tighter than it looks like it should be. The camera housing is already
    /// 220pt wide, so every point added here is doubled and the compact state
    /// stretches toward a letterbox; hugging close keeps it reading as one
    /// object rather than a bar.
    public static let compactSidePadding: CGFloat = 52
    /// Grown height in compact — a couple of points taller than the notch reads
    /// as "alive" without looking detached.
    public static let compactHeightBonus: CGFloat = 6
    /// Diameter of the detached circle in `.split`.
    public static let minimalDiameter: CGFloat = 28
    /// Gap between the compact body and the detached circle.
    public static let splitGap: CGFloat = 10

    /// Wider than the old 420.
    ///
    /// Apple's island expands to roughly 2.9× its idle width; at 420 against a
    /// 220pt housing this only managed 1.9×, so opening it felt like a nudge
    /// rather than an event.
    public static let expandedWidth: CGFloat = 468
    public static let expandedMinHeight: CGFloat = 86
    public static let expandedMaxHeight: CGFloat = 420

    /// Convex radius on the island's lower corners.
    ///
    /// Just under half the compact height, so the lower edge is a hair off a
    /// full capsule — a true capsule reads as a pill sitting on the bezel
    /// rather than a shape cut into it.
    public static let bottomRadius: CGFloat = 21
    /// Concave fillet where the island meets the top edge of the screen. This
    /// is the detail that sells the "carved out of the bezel" illusion.
    public static let topFillet: CGFloat = 12

    // MARK: Sizing

    /// Total bounds the island occupies, including the detached circle in
    /// `.split` and excluding shadow padding.
    public static func size(
        mode: IslandMode,
        metrics: IslandMetrics,
        expandedHeight: CGFloat = expandedMinHeight
    ) -> CGSize {
        switch mode {
        case .idle:
            return metrics.notchSize
        case .compact:
            return CGSize(
                width: metrics.notchSize.width + compactSidePadding * 2,
                height: metrics.notchSize.height + compactHeightBonus
            )
        case .split:
            let compact = size(mode: .compact, metrics: metrics)
            return CGSize(
                width: compact.width + splitGap + minimalDiameter,
                height: max(compact.height, minimalDiameter)
            )
        case .expanded:
            return CGSize(
                width: max(expandedWidth, metrics.notchSize.width + 80),
                height: min(max(expandedHeight, expandedMinHeight), expandedMaxHeight)
            )
        }
    }

    /// The primary body's frame within the island's own coordinate space,
    /// origin top-left. In `.split` the body sits left of the detached circle.
    public static func bodyFrame(
        mode: IslandMode,
        metrics: IslandMetrics,
        in bounds: CGSize
    ) -> CGRect {
        switch mode {
        case .split:
            let compact = size(mode: .compact, metrics: metrics)
            return CGRect(x: 0, y: 0, width: compact.width, height: compact.height)
        default:
            return CGRect(origin: .zero, size: bounds)
        }
    }

    /// Frame of the detached minimal circle, or `nil` outside `.split`.
    public static func minimalFrame(
        mode: IslandMode,
        metrics: IslandMetrics,
        in bounds: CGSize
    ) -> CGRect? {
        guard mode == .split else { return nil }
        let compact = size(mode: .compact, metrics: metrics)
        return CGRect(
            x: compact.width + splitGap,
            y: (compact.height - minimalDiameter) / 2,
            width: minimalDiameter,
            height: minimalDiameter
        )
    }

    /// Corner radius for the body's lower corners at a given mode.
    public static func bottomRadius(for mode: IslandMode, metrics: IslandMetrics) -> CGFloat {
        switch mode {
        case .idle:
            // Match the hardware's own curvature so idle is invisible.
            return metrics.hasPhysicalNotch ? 10 : 10
        case .compact, .split:
            return bottomRadius
        case .expanded:
            return 34
        }
    }

}
