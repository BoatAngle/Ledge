import AppKit
import LedgeCore

public extension NSScreen {
    /// The camera housing's bounds in this screen's coordinate space, or `nil`
    /// on displays without one.
    ///
    /// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` give us the usable
    /// menu-bar strips either side of the housing; the gap between them *is*
    /// the notch. That is more reliable than assuming a hardware width, which
    /// differs between the 14" and 16" machines.
    var notchRect: CGRect? {
        guard safeAreaInsets.top > 0 else { return nil }

        let height = safeAreaInsets.top
        if let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            let width = right.minX - left.maxX
            guard width > 0 else { return nil }
            return CGRect(x: left.maxX, y: frame.maxY - height, width: width, height: height)
        }

        // Fall back to a centred housing of the standard width.
        let width = LedgeMetrics.standardNotch.width
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    var hasNotch: Bool { notchRect != nil }

    /// Everything the layout engine needs to know about this display.
    var ledgeMetrics: IslandMetrics {
        if let notch = notchRect {
            return IslandMetrics(
                notchSize: notch.size,
                screenWidth: frame.width,
                hasPhysicalNotch: true
            )
        }
        return .synthesized(screenWidth: frame.width)
    }

    /// The screen the island should live on: the built-in notched display when
    /// there is one, otherwise whichever screen holds the menu bar.
    static var islandHost: NSScreen? {
        screens.first(where: { $0.hasNotch }) ?? NSScreen.main ?? screens.first
    }
}

private enum LedgeMetrics {
    static let standardNotch = IslandMetrics.standardNotch
}
