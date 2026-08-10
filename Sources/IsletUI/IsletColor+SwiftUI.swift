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
}

/// Shared palette for the island's chrome, so every module agrees on what
/// "secondary text" means.
public enum IslandPalette {
    public static let body = Color.black
    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.62)
    public static let tertiaryText = Color.white.opacity(0.40)
    public static let separator = Color.white.opacity(0.10)
    public static let controlFill = Color.white.opacity(0.12)
    public static let defaultTint = Color(IsletColor.accent)
}
