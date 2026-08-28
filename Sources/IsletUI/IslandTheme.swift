import IsletCore
import SwiftUI

/// How much colour a theme uses.
public enum AccentUsage: Equatable, Sendable {
    /// Glyphs, metrics and progress all carry the tint.
    case full
    /// Glyphs stay monochrome; colour is reserved for things that encode state
    /// — progress, a warning, a live indicator.
    case sparing
}

/// How rows of detail are contained in the expanded panel.
public enum DetailStyle: Equatable, Sendable {
    /// A filled, rounded group, like a Settings section.
    case grouped
    /// Hairline rules between rows, no container.
    case rules
    /// Translucent group.
    case glass
    /// A filled group defined by a one-pixel stroke — a WinUI card.
    case card
    /// An inset well carved into the surface.
    case soft
    /// Nothing but spacing.
    case plain
}

public enum ChipStyle: Equatable, Sendable {
    case tinted
    case neutral
    case glass
    /// A flat circular tonal container — M3's icon chip.
    case tonal
    /// A near-black tile ringed in glowing accent.
    case emissive
    /// Extruded from the surface — dual shadows, no outline.
    case soft
    /// No container — the glyph stands alone.
    case none
}

public enum ActionStyle: Equatable, Sendable {
    case filled
    case bordered
    case glass
    /// A squared accent-filled control — WinUI's AccentButton.
    case accent
    /// A flat tonal pill — M3's filled tonal button.
    case tonal
    /// A dark capsule ringed and lit in the accent.
    case emissive
    /// Extruded from the surface; presses back in.
    case soft
    /// A command in square brackets — text only, monochrome, monospaced.
    case command
    /// Text only.
    case plain
}

/// A complete visual direction.
///
/// Themes are whole positions, not slider settings: each picks a different
/// answer to "what is this object made of, and how loudly does it speak".
/// Mixing them tends to produce something that looks like neither.
public struct IslandTheme: Equatable, Sendable {
    public var id: IslandThemeID

    // Surface
    /// How far the bottom of the body lifts off true black.
    public var surfaceLift: Double
    public var rimOpacity: Double
    /// Translucent body below the camera strip.
    public var usesGlass: Bool
    /// Darkening laid over the material.
    ///
    /// A bare material samples whatever is behind the window, so over a bright
    /// desktop the panel's own text loses contrast — the frosted look reads as
    /// "designed" right up until you can't read it. The scrim buys back a
    /// guaranteed floor while keeping the blur.
    public var glassScrim: Double

    /// The scrim as actually applied.
    ///
    /// On real Liquid Glass the darkening goes INTO the material via tint —
    /// laying the full 0.46 flat scrim over live glass would bury the specular
    /// and lensing response you switched to glass for. The residual 0.18 wash
    /// is only a legibility floor over pathological bright desktops. Older
    /// systems keep the stored token untouched.
    public var effectiveGlassScrim: Double {
        if #available(macOS 26.0, *) {
            // 0.18 failed the white-desktop contrast ladder (panel went
            // mid-grey, Ink.secondary mush, visible seam at the camera strip);
            // 0.26 is the next rung, paired with tint 0.55 in the surface.
            return usesGlass ? 0.26 : glassScrim
        }
        return glassScrim
    }
    public var bottomRadiusScale: CGFloat

    // Glyphs
    public var glyphGlow: Double
    public var glyphWeight: Font.Weight
    /// Prefer `.fill` symbol variants where one exists.
    public var prefersFilledSymbols: Bool
    public var accentUsage: AccentUsage
    public var compactGlyphScale: CGFloat
    /// Stroke weight for the custom glyph family, at a 24pt reference size.
    public var glyphLineWidth: CGFloat
    /// Whether marks are drawn as silhouettes rather than outlines.
    public var glyphFill: GlyphWeight

    // Type
    public var titleSize: CGFloat
    public var titleWeight: Font.Weight
    /// Mono sets .monospaced; every other theme stays .default.
    public var titleDesign: Font.Design
    public var titleTracking: CGFloat
    public var subtitleSize: CGFloat
    public var metricDesign: Font.Design
    public var metricWeight: Font.Weight

    // Panel
    public var detailStyle: DetailStyle
    public var chipStyle: ChipStyle
    public var actionStyle: ActionStyle
    public var panelSpacing: CGFloat
    public var progressHeight: CGFloat
    public var progressUsesGradient: Bool

    // MARK: Presets

    /// Quiet enough to live next to the menu bar without competing with it.
    /// Colour appears only where it means something.
    public static let system = IslandTheme(
        id: .system,
        surfaceLift: 0.03,
        rimOpacity: 0.06,
        usesGlass: false,
        glassScrim: 0,
        bottomRadiusScale: 1,
        glyphGlow: 0,
        glyphWeight: .medium,
        prefersFilledSymbols: false,
        accentUsage: .sparing,
        compactGlyphScale: 0.95,
        glyphLineWidth: 1.7,
        glyphFill: .outline,
        titleSize: 13.5,
        titleWeight: .semibold,
        titleDesign: .default,
        titleTracking: -0.1,
        subtitleSize: 11,
        metricDesign: .default,
        metricWeight: .medium,
        detailStyle: .rules,
        chipStyle: .neutral,
        actionStyle: .bordered,
        panelSpacing: 11,
        progressHeight: 4,
        progressUsesGradient: false
    )

    /// The closest to Apple's own island: saturated, filled, confident.
    public static let vivid = IslandTheme(
        id: .vivid,
        surfaceLift: 0.05,
        rimOpacity: 0.10,
        usesGlass: false,
        glassScrim: 0,
        bottomRadiusScale: 1,
        glyphGlow: 0.45,
        glyphWeight: .semibold,
        prefersFilledSymbols: true,
        accentUsage: .full,
        compactGlyphScale: 1.05,
        glyphLineWidth: 2.1,
        glyphFill: .solid,
        titleSize: 14,
        titleWeight: .semibold,
        titleDesign: .default,
        titleTracking: -0.24,
        subtitleSize: 11.5,
        metricDesign: .rounded,
        metricWeight: .semibold,
        detailStyle: .grouped,
        chipStyle: .tinted,
        actionStyle: .filled,
        panelSpacing: 12,
        progressHeight: 5,
        progressUsesGradient: true
    )

    /// Translucent below the camera strip, with brighter lit edges.
    public static let glass = IslandTheme(
        id: .glass,
        surfaceLift: 0.06,
        rimOpacity: 0.30,
        usesGlass: true,
        glassScrim: 0.46,
        bottomRadiusScale: 1.15,
        glyphGlow: 0.3,
        glyphWeight: .medium,
        prefersFilledSymbols: true,
        accentUsage: .full,
        compactGlyphScale: 1,
        glyphLineWidth: 1.9,
        glyphFill: .solid,
        titleSize: 14,
        titleWeight: .medium,
        titleDesign: .default,
        titleTracking: -0.2,
        subtitleSize: 11.5,
        metricDesign: .rounded,
        metricWeight: .medium,
        detailStyle: .glass,
        chipStyle: .glass,
        actionStyle: .glass,
        panelSpacing: 13,
        progressHeight: 5,
        progressUsesGradient: true
    )

    /// Type carries the design. Hairlines instead of boxes, one quiet accent.
    public static let editorial = IslandTheme(
        id: .editorial,
        surfaceLift: 0.02,
        rimOpacity: 0.05,
        usesGlass: false,
        glassScrim: 0,
        bottomRadiusScale: 0.85,
        glyphGlow: 0,
        glyphWeight: .regular,
        prefersFilledSymbols: false,
        accentUsage: .sparing,
        compactGlyphScale: 0.9,
        glyphLineWidth: 1.45,
        glyphFill: .outline,
        titleSize: 15,
        titleWeight: .medium,
        titleDesign: .default,
        titleTracking: -0.35,
        subtitleSize: 11,
        metricDesign: .default,
        metricWeight: .regular,
        detailStyle: .plain,
        chipStyle: .none,
        actionStyle: .plain,
        panelSpacing: 15,
        progressHeight: 2.5,
        progressUsesGradient: false
    )

    /// Cool acrylic, squared corners, one-pixel strokes; accent belongs to
    /// the controls. The island as Windows 11 would draw it.
    public static let fluent = IslandTheme(
        id: .fluent,
        surfaceLift: 0.05,
        rimOpacity: 0.12,
        usesGlass: true,
        glassScrim: 0.55,
        bottomRadiusScale: 0.7,
        glyphGlow: 0,
        glyphWeight: .regular,
        prefersFilledSymbols: false,
        accentUsage: .sparing,
        compactGlyphScale: 0.95,
        glyphLineWidth: 1.5,
        glyphFill: .outline,
        titleSize: 14,
        titleWeight: .semibold,
        titleDesign: .default,
        titleTracking: 0,
        subtitleSize: 11.5,
        metricDesign: .default,
        metricWeight: .semibold,
        detailStyle: .card,
        chipStyle: .neutral,
        actionStyle: .accent,
        panelSpacing: 12,
        progressHeight: 3,
        progressUsesGradient: false
    )

    /// Material 3, dark scheme. Colour lives in flat tonal containers,
    /// elevation is a lighter tone rather than a blur or a shadow, and every
    /// control is a full pill. Opaque on purpose — M3 surfaces are paint,
    /// not glass.
    public static let material = IslandTheme(
        id: .material,
        surfaceLift: 0.06,
        rimOpacity: 0.04,
        usesGlass: false,
        glassScrim: 0,
        bottomRadiusScale: 1.2,
        glyphGlow: 0,
        glyphWeight: .regular,
        prefersFilledSymbols: true,
        accentUsage: .full,
        compactGlyphScale: 1,
        glyphLineWidth: 2.0,
        glyphFill: .solid,
        titleSize: 14.5,
        titleWeight: .medium,
        titleDesign: .default,
        titleTracking: 0.1,
        subtitleSize: 11.5,
        metricDesign: .default,
        metricWeight: .medium,
        detailStyle: .grouped,
        chipStyle: .tonal,
        actionStyle: .tonal,
        panelSpacing: 13,
        progressHeight: 6,
        progressUsesGradient: false
    )

    /// Emissive colour on a void-black body. Nothing here is painted — glyphs,
    /// rims, rings and bars all read as light sources, which only works because
    /// the surface itself stays as close to off as the family allows.
    public static let neon = IslandTheme(
        id: .neon,
        surfaceLift: 0.02,
        rimOpacity: 0.38,
        usesGlass: false,
        glassScrim: 0,
        bottomRadiusScale: 1,
        glyphGlow: 0.6,
        glyphWeight: .semibold,
        prefersFilledSymbols: false,
        accentUsage: .full,
        compactGlyphScale: 1,
        glyphLineWidth: 2.0,
        glyphFill: .outline,
        titleSize: 13.5,
        titleWeight: .semibold,
        titleDesign: .default,
        titleTracking: 0.5,
        subtitleSize: 11,
        metricDesign: .rounded,
        metricWeight: .semibold,
        detailStyle: .rules,
        chipStyle: .emissive,
        actionStyle: .emissive,
        panelSpacing: 12,
        progressHeight: 3.5,
        progressUsesGradient: true
    )

    /// Sculpted, not drawn: the panel is a slab of soft dark material, and
    /// every control is extruded from it or pressed into it. Dual shadows,
    /// no outlines, no glow — the light does the talking, quietly.
    public static let soft = IslandTheme(
        id: .soft,
        surfaceLift: 0.09,
        rimOpacity: 0.08,
        usesGlass: false,
        glassScrim: 0,
        bottomRadiusScale: 1.25,
        glyphGlow: 0,
        glyphWeight: .medium,
        prefersFilledSymbols: false,
        accentUsage: .sparing,
        compactGlyphScale: 0.95,
        glyphLineWidth: 1.8,
        glyphFill: .outline,
        titleSize: 13.5,
        titleWeight: .medium,
        titleDesign: .default,
        titleTracking: 0,
        subtitleSize: 11,
        metricDesign: .rounded,
        metricWeight: .medium,
        detailStyle: .soft,
        chipStyle: .soft,
        actionStyle: .soft,
        panelSpacing: 14,
        progressHeight: 6,
        progressUsesGradient: false
    )

    /// The island as a status line: monospaced type on flat black, hairline
    /// rules, bracketed commands, nothing lit. Colour appears only where it
    /// encodes state, the way a status bar goes red.
    public static let mono = IslandTheme(
        id: .mono,
        surfaceLift: 0.02,
        rimOpacity: 0.08,
        usesGlass: false,
        glassScrim: 0,
        bottomRadiusScale: 0.75,
        glyphGlow: 0,
        glyphWeight: .regular,
        prefersFilledSymbols: false,
        accentUsage: .sparing,
        compactGlyphScale: 0.9,
        glyphLineWidth: 1.5,
        glyphFill: .outline,
        titleSize: 13,
        titleWeight: .semibold,
        titleDesign: .monospaced,
        titleTracking: 0,
        subtitleSize: 10.5,
        metricDesign: .monospaced,
        metricWeight: .medium,
        detailStyle: .rules,
        chipStyle: .none,
        actionStyle: .command,
        panelSpacing: 9,
        progressHeight: 3,
        progressUsesGradient: false
    )

    public static func preset(_ id: IslandThemeID) -> IslandTheme {
        switch id {
        case .system: return .system
        case .vivid: return .vivid
        case .glass: return .glass
        case .editorial: return .editorial
        case .fluent: return .fluent
        case .material: return .material
        case .neon: return .neon
        case .soft: return .soft
        case .mono: return .mono
        }
    }

    // MARK: Derived

    public var titleFont: Font { .system(size: titleSize, weight: titleWeight, design: titleDesign) }
    public var subtitleFont: Font { .system(size: subtitleSize, design: titleDesign) }

    public func metricFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: metricWeight, design: metricDesign)
    }

    /// Adjusts a symbol name to the theme's preferred variant.
    ///
    /// Modules pick filled symbols because they read better small; the quieter
    /// themes strip the fill rather than making every module aware of themes.
    public func symbolName(_ name: String) -> String {
        if prefersFilledSymbols { return name }
        guard name.hasSuffix(".fill") else { return name }
        let stripped = String(name.dropLast(5))
        // Not every symbol has an unfilled twin; keep the fill where it doesn't.
        return NSImage(systemSymbolName: stripped, accessibilityDescription: nil) != nil
            ? stripped
            : name
    }

    public func surfaceFill(liftsAtBottom: Bool) -> LinearGradient {
        LinearGradient(
            colors: liftsAtBottom
                ? [.black, Color(white: surfaceLift)]
                : [.black, .black],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public var rim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0.0),
                .init(color: .white.opacity(0), location: 0.45),
                .init(color: .white.opacity(rimOpacity), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Environment

private struct IslandThemeKey: EnvironmentKey {
    static let defaultValue: IslandTheme = .vivid
}

public extension EnvironmentValues {
    var islandTheme: IslandTheme {
        get { self[IslandThemeKey.self] }
        set { self[IslandThemeKey.self] = newValue }
    }
}

public extension View {
    func islandTheme(_ theme: IslandTheme) -> some View {
        environment(\.islandTheme, theme)
    }
}

public extension ActivityStyle {
    /// Colour for a glyph, which the quieter themes keep monochrome.
    func glyphColor(_ theme: IslandTheme) -> Color {
        theme.accentUsage == .full ? tint : IslandDesign.Ink.primary
    }

    /// Colour for anything encoding state — progress, metrics, indicators.
    /// Always the tint, in every theme; that's what colour is *for*.
    var accentColor: Color { tint }

    func glow(_ theme: IslandTheme) -> Double {
        theme.accentUsage == .full ? theme.glyphGlow : 0
    }
}
