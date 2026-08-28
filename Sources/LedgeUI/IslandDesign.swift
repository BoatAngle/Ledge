import LedgeCore
import SwiftUI

/// The island's visual vocabulary.
///
/// One constraint drives all of it: the island sits *over* the camera housing,
/// so its upper region has to be indistinguishable from the physical bezel.
/// Any depth — gradients, highlights, shadows — has to originate at the bottom
/// edge and fall away downward, or a seam appears where the drawn black meets
/// the real black. That rules out the obvious light-from-above treatment and is
/// why the surface gradient runs dark-to-slightly-less-dark going *down*.
public enum IslandDesign {

    // MARK: Rhythm

    /// Everything spaces on multiples of this. Consistent rhythm is most of
    /// what separates "designed" from "assembled".
    public static let unit: CGFloat = 4
    public static func space(_ multiple: CGFloat) -> CGFloat { unit * multiple }

    public static let panelHorizontalPadding: CGFloat = 18
    public static let panelBottomPadding: CGFloat = 16

    // MARK: Surface

    // The surface itself is theme-owned — see IslandTheme.surfaceFill and
    // its per-theme surfaceLift values.
    public static let rimWidth: CGFloat = 0.75

    /// One corner-radius ratio for every mark and chip. Four ratios had
    /// drifted in (0.24/0.26/0.28/0.3) across sibling elements.
    public static let markCornerRatio: CGFloat = 0.28

    // MARK: Shadow

    /// Two shadows, not one.
    ///
    /// A single mid-radius shadow reads as a drop shadow on a sticker. A tight
    /// contact shadow plus a wide ambient one is how real objects sit on a
    /// surface, and it's what Apple's own floating chrome uses.
    public struct ShadowSpec: Sendable {
        public var contactRadius: CGFloat
        public var contactY: CGFloat
        public var contactOpacity: Double
        public var ambientRadius: CGFloat
        public var ambientY: CGFloat
        public var ambientOpacity: Double

        public static let resting = ShadowSpec(
            contactRadius: 5, contactY: 2, contactOpacity: 0.30,
            ambientRadius: 14, ambientY: 6, ambientOpacity: 0.16
        )
        public static let raised = ShadowSpec(
            contactRadius: 8, contactY: 3, contactOpacity: 0.42,
            ambientRadius: 34, ambientY: 16, ambientOpacity: 0.34
        )
        /// Idle casts nothing — the island is the bezel.
        public static let none = ShadowSpec(
            contactRadius: 0, contactY: 0, contactOpacity: 0,
            ambientRadius: 0, ambientY: 0, ambientOpacity: 0
        )
    }

    // MARK: Type

    /// A deliberate ramp rather than ad-hoc point sizes.
    ///
    /// Title, subtitle, and metric fonts are THEME-OWNED — see
    /// IslandTheme.titleFont / subtitleFont / metricFont(_:). Only the sizes
    /// no theme varies live here.
    public enum Text {
        public static let body = Font.system(size: 12, weight: .regular)

        public static let label = Font.system(size: 11, weight: .regular)
        public static let value = Font.system(size: 11, weight: .medium)
        public static let caption = Font.system(size: 10, weight: .medium)

        public static let button = Font.system(size: 11.5, weight: .semibold)

        /// The expanded header's trailing readout — countdowns and metrics
        /// share the slot, so they share the size (they had drifted 17 vs 16).
        public static let headerMetricSize: CGFloat = 17
    }

    // MARK: Colour

    /// The ink ramp, measured against the island's true-black surface.
    ///
    /// These were tuned by eye and two of them failed: detail labels sat at
    /// roughly 3.9:1 (WCAG asks 4.5:1 for text this size) and the inactive page
    /// dots — which are a *control*, not decoration — at about 1.8:1 against a
    /// 3:1 floor for interface components. The values below clear both, and
    /// Increase Contrast pushes every step further still.
    ///
    /// Computed rather than stored so the setting takes effect live. Reading
    /// one inside a SwiftUI `body` also registers the observation, so the panel
    /// re-renders when the user changes it in System Settings.
    public enum Ink {
        private static var boost: Double { IslandAccessibility.prefersIncreasedContrast ? 1 : 0 }

        /// Interpolates toward full white by the Increase Contrast boost.
        private static func ink(_ base: Double, contrast: Double) -> Color {
            Color.white.opacity(base + (contrast - base) * boost)
        }

        public static let primary = Color.white
        public static var secondary: Color { ink(0.66, contrast: 0.86) }
        /// 0.55 ≈ 6.2:1 on black, up from 0.42 ≈ 3.9:1.
        public static var tertiary: Color { ink(0.55, contrast: 0.80) }
        /// Structural marks quieter than tertiary text — inactive page dots,
        /// the pre-glass button border. 0.36 ≈ 3.1:1, up from 0.22 ≈ 1.8:1:
        /// these dots are the panel's only navigation control and have to meet
        /// the component floor, not the decoration one.
        public static var quaternary: Color { ink(0.36, contrast: 0.62) }
        public static var separator: Color { ink(0.07, contrast: 0.22) }
        public static var controlFill: Color { ink(0.11, contrast: 0.20) }
        public static var controlStroke: Color { ink(0.09, contrast: 0.34) }
        public static var trackFill: Color { ink(0.11, contrast: 0.22) }
    }

    /// The app accent as a SwiftUI color, for the few places outside an
    /// activity's own tint.
    public static let accent = Color(LedgeColor.accent)

    /// Tinted fills get a slight vertical gradient rather than a flat colour —
    /// flat saturated blocks are the fastest way to look unfinished.
    public static func tintGradient(_ tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [tint, tint.opacity(0.78)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Modifiers

private extension View {
    /// Brightness that is genuinely absent when it isn't wanted.
    ///
    /// The distinction matters: a filter modifier with a neutral value still
    /// forces an offscreen render pass, which is enough to break a Liquid Glass
    /// background underneath it.
    @ViewBuilder
    func brightness(ifHovering apply: Bool, by amount: Double) -> some View {
        if apply { brightness(amount) } else { self }
    }
}

public extension View {
    /// Layered shadow.
    func islandShadow(_ spec: IslandDesign.ShadowSpec) -> some View {
        shadow(
            color: .black.opacity(spec.contactOpacity),
            radius: spec.contactRadius,
            y: spec.contactY
        )
        .shadow(
            color: .black.opacity(spec.ambientOpacity),
            radius: spec.ambientRadius,
            y: spec.ambientY
        )
    }

}

/// A soft bloom behind a tinted glyph.
///
/// On an OLED panel a saturated symbol against true black reads as emissive;
/// this approximates that so coloured glyphs sit *in* the island rather than
/// on top of it.
public struct GlyphGlow: ViewModifier {
    public var tint: Color
    public var radius: CGFloat
    public var intensity: Double

    public init(tint: Color, radius: CGFloat = 7, intensity: Double = 0.5) {
        self.tint = tint
        self.radius = radius
        self.intensity = intensity
    }

    public func body(content: Content) -> some View {
        content
            .background {
                content
                    .foregroundStyle(tint)
                    .blur(radius: radius)
                    .opacity(intensity)
                    .allowsHitTesting(false)
            }
    }
}

public extension View {
    func glyphGlow(_ tint: Color, radius: CGFloat = 7, intensity: Double = 0.5) -> some View {
        modifier(GlyphGlow(tint: tint, radius: radius, intensity: intensity))
    }
}

/// The rounded, tinted container an activity's mark sits in when expanded.
///
/// Mirrors how Live Activities present an app icon: a continuous-corner chip
/// with a tinted wash and a hairline edge, so a bare SF Symbol doesn't float
/// unanchored in the panel.
public struct IconChip<Content: View>: View {
    public var tint: Color
    public var size: CGFloat
    public var content: Content

    public init(tint: Color, size: CGFloat = 38, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.size = size
        self.content = content()
    }

    public var body: some View {
        content
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * IslandDesign.markCornerRatio, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.30), tint.opacity(0.16)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * IslandDesign.markCornerRatio, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 0.75)
            }
    }
}

/// Action button in the expanded panel, in whichever form the theme calls for.
public struct IslandButtonStyle: ButtonStyle {
    public var tint: Color
    public var isDestructive: Bool
    public var kind: ActionStyle

    public init(tint: Color, isDestructive: Bool = false, kind: ActionStyle = .filled) {
        self.tint = tint
        self.isDestructive = isDestructive
        self.kind = kind
    }

    /// Hover feedback, in every theme rather than in one.
    ///
    /// Only `.glass` acknowledged the pointer, because `.interactive()` glass
    /// brings its own shimmer; the other eight themes' buttons sat inert under
    /// the cursor and read as labels until you clicked one. A `ButtonStyle`
    /// can't hold `@State`, so the body goes through this wrapper.
    ///
    /// Deliberately quiet — a small lift in opacity and a hair of scale. These
    /// controls live on a panel that opens under the pointer; anything louder
    /// would fire every time the panel appeared.
    private struct Hoverable<Content: View>: View {
        var isPressed: Bool
        @ViewBuilder var content: (Bool) -> Content
        @State private var isHovering = false

        var body: some View {
            content(isHovering)
                .onHover { hovering in
                    withAnimation(IslandMotion.content) { isHovering = hovering }
                }
                .scaleEffect(isPressed ? 0.95 : (isHovering ? 1.02 : 1))
                .animation(
                    isPressed ? IslandMotion.pressIn : IslandMotion.pressRelease,
                    value: isPressed
                )
        }
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if kind == .command {
            // The brackets ARE the container — no fill, no stroke, no radius.
            // A terminal control dims; it does not bounce.
            HStack(spacing: 0) {
                Text("[").foregroundStyle(IslandDesign.Ink.tertiary)
                configuration.label
                    .foregroundStyle(isDestructive ? Color.red : IslandDesign.Ink.primary)
                Text("]").foregroundStyle(IslandDesign.Ink.tertiary)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(
                configuration.isPressed ? IslandMotion.pressIn : IslandMotion.pressRelease,
                value: configuration.isPressed
            )
        } else {
            Hoverable(isPressed: configuration.isPressed) { isHovering in
                let label = configuration.label
                    .font(IslandDesign.Text.button)
                    .foregroundStyle(labelColor)
                    .padding(.horizontal, kind == .plain ? 0 : 13)
                    .padding(.vertical, kind == .plain ? 2 : 7)

                Group {
                    if kind == .glass, #available(macOS 26.0, *) {
                        // Glass goes ON the label, not behind it.
                        //
                        // This used to be `.background { Color.clear.glassEffect(…) }`
                        // with `.glassEffectID` applied to the whole button.
                        // `glassEffectID` marks a view that *has* a glass
                        // effect; tagging a button whose glass lives in a
                        // detached background layer made the container treat
                        // the button's own rendering as glass geometry and lens
                        // it — so "Choose Modules" and "Got It" rendered as
                        // unreadable smears, in the app's default theme, on the
                        // one panel a new user is guaranteed to see.
                        //
                        // Applied directly, the material draws behind the label
                        // and the text stays crisp, which is the documented
                        // shape and also the obvious one.
                        label.glassEffect(
                            .regular
                                .tint(isDestructive ? Color.red.opacity(0.35) : .clear)
                                .interactive(),
                            in: .capsule
                        )
                    } else {
                        label
                            .background { background }
                            .overlay { border }
                            // Only attached when it does something: `.brightness`
                            // is a filter, and an always-present one costs an
                            // offscreen pass for a no-op.
                            .brightness(ifHovering: isHovering, by: 0.09)
                    }
                }
                .opacity(configuration.isPressed ? 0.75 : 1)
            }
        }
    }

    private var labelColor: Color {
        if isDestructive {
            switch kind {
            case .accent: return IslandDesign.Ink.primary // white on the red fill
            case .tonal: return Color(red: 0.95, green: 0.72, blue: 0.70) // M3 on-error-container
            default: return Color.red
            }
        }
        switch kind {
        case .plain, .emissive: return tint
        // WinUI TextOnAccentFillColorPrimary (dark theme): near-black on the
        // bright accent fill.
        case .accent: return Color.black.opacity(0.9)
        default: return IslandDesign.Ink.primary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .filled:
            Capsule(style: .continuous)
                .fill(isDestructive ? Color.red.opacity(0.18) : IslandDesign.Ink.controlFill)
        case .glass:
            // On macOS 26 the glass is applied to the label itself in
            // `makeBody` — see the note there. This is the pre-26 fallback.
            Capsule(style: .continuous).fill(Color.white.opacity(0.14))
        case .accent:
            // WinUI AccentButton: a squared accent fill; corners are circular
            // arcs, not superellipses.
            RoundedRectangle(cornerRadius: 5, style: .circular)
                .fill(isDestructive ? Color.red.opacity(0.85) : tint)
        case .tonal:
            // M3 filled tonal button: a flat wash, elevation 0, no outline.
            Capsule(style: .continuous)
                .fill(isDestructive ? Color.red.opacity(0.22) : tint.opacity(0.20))
        case .emissive:
            Capsule(style: .continuous)
                .fill((isDestructive ? Color.red : tint).opacity(0.10))
        case .soft:
            // Same emboss recipe as the .soft chip. The material stays
            // neutral even when destructive — the red label carries the
            // meaning; a neumorphic object changes state, not substance.
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.15), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    if isDestructive {
                        Capsule(style: .continuous).fill(Color.red.opacity(0.08))
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 3)
                .shadow(color: .white.opacity(0.05), radius: 3, x: -1.5, y: -2)
        case .bordered, .plain, .command:
            Color.clear
        }
    }

    @ViewBuilder
    private var border: some View {
        switch kind {
        case .filled, .bordered:
            Capsule(style: .continuous)
                .strokeBorder(
                    isDestructive ? Color.red.opacity(0.24) : IslandDesign.Ink.controlStroke,
                    lineWidth: 0.75
                )
        case .glass:
            // Real glass supplies its own edge and never reaches here on 26+.
            Capsule(style: .continuous)
                .strokeBorder(IslandDesign.Ink.quaternary, lineWidth: 0.75)
        case .accent:
            // WinUI's ControlElevationBorder: the 1px stroke IS the elevation.
            RoundedRectangle(cornerRadius: 5, style: .circular)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        case .emissive:
            // The 1pt tinted ring with its bloom — the border is the light.
            Capsule(style: .continuous)
                .strokeBorder((isDestructive ? Color.red : tint).opacity(0.80), lineWidth: 1)
                .shadow(color: (isDestructive ? Color.red : tint).opacity(0.50), radius: 3)
        case .soft:
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.16), location: 0),
                            .init(color: .white.opacity(0.02), location: 0.55),
                            .init(color: .white.opacity(0), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        case .tonal, .plain, .command:
            Color.clear
        }
    }
}
