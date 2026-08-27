import AppKit
import IsletCore
import SwiftUI

public extension Color {
    init(_ islet: IsletColor) {
        self.init(
            .sRGB,
            red: islet.red,
            green: islet.green,
            blue: islet.blue,
            opacity: islet.alpha
        )
    }
}

public extension IsletColor {
    var swiftUIColor: Color { Color(self) }

    /// Converts back from SwiftUI, for the custom colour well in Settings.
    ///
    /// Goes through sRGB explicitly: `NSColor` from a SwiftUI `Color` can land
    /// in a device or catalog space whose components mean something different,
    /// and the island stores plain sRGB numbers.
    init?(_ color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent)
        )
    }
}

// IslandPalette is gone: it duplicated IslandDesign.Ink with drifted values
// (secondary 0.62 vs 0.66, separator 0.10 vs 0.07…), so "secondary text"
// meant two different things in the same island. IslandDesign is the single
// ink source.
