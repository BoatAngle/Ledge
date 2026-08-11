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

    /// True black, matching the bezel.
    public static let bezelBlack = Color.black
    /// The faintest lift at the bottom of the body. Below ~#0C it stops reading
    /// as a surface; above it, the seam at the notch becomes visible.
    public static let surfaceLift = Color(white: 0.045)

    /// Fill for the island body.
    ///
    /// `liftsAtBottom` is false at idle, where the island *is* the notch and any
    /// deviation from pure black would show.
    public static func surfaceFill(liftsAtBottom: Bool) -> LinearGradient {
        LinearGradient(
            colors: liftsAtBottom ? [bezelBlack, surfaceLift] : [bezelBlack, bezelBlack],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// A hairline catching light along the lower edge.
    ///
    /// Drawn as a gradient stroke that fades to nothing by the halfway point, so
    /// only the bottom curve is lit — a full outline would look like a border.
    public static let rimHighlight = LinearGradient(
        stops: [
            .init(color: .white.opacity(0), location: 0.0),
            .init(color: .white.opacity(0), location: 0.45),
            .init(color: .white.opacity(0.10), location: 1.0),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let rimWidth: CGFloat = 0.75

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
            contactRadius: 5, contactY: 2, contactOpacity: 0.34,
            ambientRadius: 18, ambientY: 8, ambientOpacity: 0.22
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
    /// Negative tracking on the larger sizes: SF tightens optically as it grows,
    /// and text set without it looks loose next to Apple's own.
    public enum Text {
        public static let title = Font.system(size: 14, weight: .semibold)
        public static let titleTracking: CGFloat = -0.24

        public static let subtitle = Font.system(size: 11.5, weight: .regular)
        public static let body = Font.system(size: 12, weight: .regular)

        public static let label = Font.system(size: 11, weight: .regular)
        public static let value = Font.system(size: 11, weight: .medium)
        public static let caption = Font.system(size: 10, weight: .medium)

        /// Numbers that change in place — countdowns, percentages.
        public static func metric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        public static let button = Font.system(size: 11.5, weight: .semibold)
    }

    // MARK: Colour

    public enum Ink {
        public static let primary = Color.white
        public static let secondary = Color.white.opacity(0.66)
        public static let tertiary = Color.white.opacity(0.42)
        public static let separator = Color.white.opacity(0.07)
        public static let controlFill = Color.white.opacity(0.11)
        public static let controlStroke = Color.white.opacity(0.09)
        public static let trackFill = Color.white.opacity(0.11)
    }

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

    /// Title text with the ramp's tracking applied.
    func islandTitle() -> some View {
        font(IslandDesign.Text.title)
            .tracking(IslandDesign.Text.titleTracking)
            .foregroundStyle(IslandDesign.Ink.primary)
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
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.30), tint.opacity(0.16)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
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

    public func makeBody(configuration: Configuration) -> some View {
        let accent = isDestructive ? Color.red : IslandDesign.Ink.primary
        configuration.label
            .font(IslandDesign.Text.button)
            .foregroundStyle(kind == .plain && !isDestructive ? tint : accent)
            .padding(.horizontal, kind == .plain ? 0 : 13)
            .padding(.vertical, kind == .plain ? 2 : 7)
            .background { background }
            .overlay { border }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .filled:
            Capsule(style: .continuous)
                .fill(isDestructive ? Color.red.opacity(0.18) : IslandDesign.Ink.controlFill)
        case .glass:
            Capsule(style: .continuous).fill(Color.white.opacity(0.14))
        case .bordered, .plain:
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
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
        case .plain:
            Color.clear
        }
    }
}
