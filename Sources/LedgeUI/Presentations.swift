import LedgeCore
import SwiftUI

/// An activity's resolved look, after the user's per-module overrides.
public struct ActivityStyle: Equatable, Sendable {
    public var tint: Color
    public var scale: CGFloat

    public init(tint: Color, scale: CGFloat = 1) {
        self.tint = tint
        self.scale = scale
    }

    /// Resolution order: the user's override, then whatever the module chose,
    /// then the fallback accent.
    public static func resolve(_ activity: Activity, appearance: ModuleAppearance?) -> ActivityStyle {
        let tint = appearance?.tint.map(Color.init)
            ?? activity.content.tint.map(Color.init)
            ?? IslandDesign.Ink.primary.opacity(0.9)
        return ActivityStyle(tint: tint, scale: CGFloat(appearance?.scale ?? 1))
    }

    public static let placeholder = ActivityStyle(tint: Color(LedgeColor.accent))
}

// MARK: - Compact

/// The glyph left of the camera housing.
///
/// Apple's compact presentation is deliberately wordless: two glyphs, no text.
/// Anything needing a sentence belongs in the expanded state, and resisting the
/// urge to cram a title in here is most of what keeps it looking right.
public struct CompactLeadingView: View {
    @Environment(\.islandTheme) private var theme
    public var activity: Activity
    public var height: CGFloat
    public var style: ActivityStyle

    public init(activity: Activity, height: CGFloat, style: ActivityStyle = .placeholder) {
        self.activity = activity
        self.height = height
        self.style = style
    }

    public var body: some View {
        let glyph = min(height - 12, 22) * style.scale * theme.compactGlyphScale
        Group {
            switch activity.nativeView {
            case .media:
                Artwork(icon: activity.content.icon, size: glyph + 3, cornerRadius: 5)
            case .privacy:
                // The provider sets a trailing symbol only when a second
                // device is live; that is the signal for the second dot.
                PrivacyDot(
                    tint: style.accentColor,
                    size: glyph * 0.46,
                    secondaryTint: activity.content.trailingIcon == nil
                        ? nil
                        : Color(LedgeColor.orange)
                )
            case .some, .none:
                ActivityIconView(
                    icon: activity.content.icon,
                    size: glyph,
                    tint: style.glyphColor(theme)
                )
                .glyphGlow(style.tint, radius: glyph * 0.34, intensity: style.glow(theme))
            }
        }
        // Handoffs read as one object re-forming, not a pop-in at glyph size.
        .transition(.blurReplace)
    }
}

/// The glyph right of the camera housing.
public struct CompactTrailingView: View {
    @Environment(\.islandTheme) private var theme
    public var activity: Activity
    public var height: CGFloat
    public var style: ActivityStyle
    /// False while this activity's panel is open: the panel header shows the
    /// same countdown/metric 30pt below, and one live readout is enough.
    public var showsReadout: Bool

    public init(
        activity: Activity,
        height: CGFloat,
        style: ActivityStyle = .placeholder,
        showsReadout: Bool = true
    ) {
        self.activity = activity
        self.height = height
        self.style = style
        self.showsReadout = showsReadout
    }

    public var body: some View {
        let content = activity.content
        let metric = 12 * style.scale
        Group {
            if activity.nativeView == .privacy {
                // The leading mark already carries the whole state, including
                // the second dot. Repeating the microphone as a 20pt glyph on
                // the trailing side would make one fact look like two.
                BreathingDot(tint: style.accentColor, size: 7 * style.scale)
            } else if activity.nativeView == .media {
                WaveformView(
                    color: style.accentColor,
                    isAnimating: true,
                    size: CGSize(width: 18 * style.scale, height: (height - 16) * style.scale)
                )
            } else if !showsReadout,
                      content.countdownTarget != nil || content.countUpFrom != nil
                        || content.trailingText != nil {
                EmptyView()
            } else if content.countdownTarget != nil || content.countUpFrom != nil {
                LiveTimeText(
                    target: content.countdownTarget,
                    countUpFrom: content.countUpFrom,
                    font: theme.metricFont(metric),
                    color: style.accentColor
                )
                .glyphGlow(style.tint, radius: 6, intensity: style.glow(theme) * 0.7)
            } else if let text = content.trailingText {
                Text(text)
                    .font(theme.metricFont(metric))
                    .monospacedDigit()
                    .foregroundStyle(style.accentColor)
                    .contentTransition(.numericText())
                    // Keyed to the text itself: the strip's animation keys on
                    // activity id, so 84% → 85% would otherwise snap.
                    .animation(IslandMotion.content, value: text)
                    .glyphGlow(style.tint, radius: 6, intensity: style.glow(theme) * 0.7)
            } else if let icon = content.trailingIcon {
                ActivityIconView(
                    icon: icon,
                    size: min(height - 12, 20) * style.scale * theme.compactGlyphScale,
                    tint: style.glyphColor(theme)
                )
                .glyphGlow(style.tint, radius: 6, intensity: style.glow(theme))
            } else if let progress = content.progress {
                IslandProgressRing(fraction: progress.fraction, tint: style.accentColor)
                    .frame(
                        width: min(height - 14, 18) * style.scale,
                        height: min(height - 14, 18) * style.scale
                    )
            } else {
                BreathingDot(tint: style.accentColor, size: 7 * style.scale)
            }
        }
        .transition(.blurReplace)
    }
}

// MARK: - Minimal

/// The detached circle that appears when a second activity is running.
public struct MinimalView: View {
    @Environment(\.islandTheme) private var theme
    public var activity: Activity
    public var diameter: CGFloat
    public var style: ActivityStyle

    public init(activity: Activity, diameter: CGFloat, style: ActivityStyle = .placeholder) {
        self.activity = activity
        self.diameter = diameter
        self.style = style
    }

    public var body: some View {
        Group {
            if activity.nativeView == .media {
                Artwork(icon: activity.content.icon, size: diameter - 8, cornerRadius: (diameter - 8) / 2)
            } else if let progress = activity.content.progress {
                IslandProgressRing(fraction: progress.fraction, tint: style.accentColor, lineWidth: 2)
                    .frame(width: diameter - 11, height: diameter - 11)
            } else {
                ActivityIconView(
                    icon: activity.content.icon,
                    size: (diameter - 13) * style.scale,
                    tint: style.glyphColor(theme)
                )
                .glyphGlow(style.tint, radius: 5, intensity: style.glow(theme))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Expanded

/// The drop-down panel.
public struct ExpandedView: View {
    @Environment(\.islandTheme) private var theme
    @Namespace private var actionsNamespace
    public var activity: Activity
    public var siblings: [Activity]
    public var style: ActivityStyle
    public var onSelect: (String) -> Void
    public var onAction: (ActivityAction) -> Void
    public var onDismiss: () -> Void
    /// Open the owning app. Reachable only through the header row — a tap on
    /// the panel's background dismisses, it never launches anything.
    public var onOpen: () -> Void

    public init(
        activity: Activity,
        siblings: [Activity] = [],
        style: ActivityStyle = .placeholder,
        onSelect: @escaping (String) -> Void = { _ in },
        onAction: @escaping (ActivityAction) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {},
        onOpen: @escaping () -> Void = {}
    ) {
        self.activity = activity
        self.siblings = siblings
        self.style = style
        self.onSelect = onSelect
        self.onAction = onAction
        self.onDismiss = onDismiss
        self.onOpen = onOpen
    }

    public var body: some View {
        let content = activity.content
        VStack(alignment: .leading, spacing: theme.panelSpacing) {
            header(content)
                .contentShape(Rectangle())
                .onTapGesture {
                    // The header is opaque to hit-testing, so a tap here never
                    // reaches the background's dismiss gesture. When there is
                    // no app to open — a timer, a shell script's activity, most
                    // of the system modules — that used to mean the most
                    // clickable-looking row on the panel simply ate the click.
                    // Nothing is not an acceptable answer to a click.
                    if activity.openURL != nil { onOpen() } else { onDismiss() }
                }
                // The header is one thing that says one sentence — and, when
                // there's an app behind it, one thing you can activate.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(content.spokenSummary))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(
                    activity.openURL != nil ? Text("Opens the app") : Text("Closes the panel")
                )

            if let body = content.body {
                Text(body)
                    .font(IslandDesign.Text.body)
                    .foregroundStyle(IslandDesign.Ink.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let progress = content.progress {
                VStack(alignment: .leading, spacing: IslandDesign.space(1.5)) {
                    IslandProgressBar(progress: progress, tint: style.tint)
                    if let label = progress.label {
                        Text(label)
                            .font(IslandDesign.Text.caption)
                            .foregroundStyle(IslandDesign.Ink.tertiary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(progress.label ?? "Progress"))
                // A determinate bar reports a percentage; an indeterminate one
                // says so rather than reporting a meaningless zero.
                .accessibilityValue(
                    Text(
                        progress.fraction.map { "\(Int(($0 * 100).rounded())) percent" }
                            ?? "In progress"
                    )
                )
            }

            if !content.details.isEmpty {
                details(content.details)
            }

            if !content.actions.isEmpty {
                actions(content.actions)
            }

            if siblings.count > 1 {
                switcher
            }
        }
        .padding(.horizontal, IslandDesign.panelHorizontalPadding)
        .padding(.bottom, IslandDesign.panelBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Report the panel's natural height so the island can size itself
            // to the content instead of to a table of guessed constants.
            GeometryReader { proxy in
                Color.clear.preference(key: ExpandedHeightKey.self, value: proxy.size.height)
            }
        )
    }

    private func header(_ content: ActivityContent) -> some View {
        HStack(spacing: IslandDesign.space(3)) {
            mark(content)

            VStack(alignment: .leading, spacing: 1) {
                Text(content.title)
                    .font(theme.titleFont)
                    .tracking(theme.titleTracking)
                    .foregroundStyle(IslandDesign.Ink.primary)
                    .lineLimit(1)
                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(theme.subtitleFont)
                        .foregroundStyle(IslandDesign.Ink.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: IslandDesign.space(2))

            if content.countdownTarget != nil || content.countUpFrom != nil {
                LiveTimeText(
                    target: content.countdownTarget,
                    countUpFrom: content.countUpFrom,
                    font: theme.metricFont(IslandDesign.Text.headerMetricSize),
                    color: style.accentColor
                )
            } else if let trailing = content.trailingText {
                Text(trailing)
                    .font(theme.metricFont(IslandDesign.Text.headerMetricSize))
                    .monospacedDigit()
                    .foregroundStyle(style.accentColor)
                    .contentTransition(.numericText())
                    .animation(IslandMotion.content, value: trailing)
            }
        }
    }

    /// A symbol gets a tinted chip; real artwork stands on its own with a
    /// hairline so it doesn't float against the black.
    @ViewBuilder
    private func mark(_ content: ActivityContent) -> some View {
        let size: CGFloat = theme.chipStyle == .none ? 26 : 38
        if content.icon != nil, case .symbol = content.icon {
            chipped(size: size) {
                ActivityIconView(
                    icon: content.icon,
                    size: theme.chipStyle == .none ? size : size * 0.52,
                    tint: style.glyphColor(theme)
                )
            }
        } else if content.icon != nil {
            Artwork(icon: content.icon, size: size, cornerRadius: size * IslandDesign.markCornerRatio)
        } else {
            chipped(size: size) {
                Circle()
                    .fill(style.accentColor)
                    .frame(width: size * 0.22, height: size * 0.22)
            }
        }
    }

    /// The container an activity's mark sits in, which each theme answers
    /// differently — from a tinted chip down to nothing at all.
    @ViewBuilder
    private func chipped<Content: View>(
        size: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        switch theme.chipStyle {
        case .tinted:
            IconChip(tint: style.tint, size: size, content: content)
        case .neutral:
            content()
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                }
        case .glass:
            content()
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: size * IslandDesign.markCornerRatio, style: .continuous)
                        .fill(Color.white.opacity(0.13))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * IslandDesign.markCornerRatio, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.34), .white.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                }
        case .tonal:
            // M3's circular icon container: a flat tonal wash, nothing else.
            // A hairline or gradient would collapse it back into Vivid's chip.
            content()
                .frame(width: size, height: size)
                .background {
                    Circle().fill(style.tint.opacity(0.22))
                }
        case .emissive:
            // A near-black tile whose 1pt tinted ring is the light source —
            // the shadow blooms the ring only; the glyph already carries glow.
            content()
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: size * IslandDesign.markCornerRatio, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * IslandDesign.markCornerRatio, style: .continuous)
                        .strokeBorder(style.tint.opacity(0.85), lineWidth: 1)
                        .shadow(color: style.tint.opacity(0.55), radius: 4)
                }
        case .soft:
            // Extruded: top-leading-lit fill whose dark corner lands on the
            // panel's own lift, dual shadows on the shape only, and a
            // top-leading stroke gradient standing in for the inner light
            // SwiftUI can't draw.
            content()
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.16), Color(white: 0.09)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 3)
                        .shadow(color: .white.opacity(0.05), radius: 3, x: -1.5, y: -2)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.15), location: 0),
                                    .init(color: .white.opacity(0.02), location: 0.55),
                                    .init(color: .white.opacity(0), location: 1),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        case .none:
            content()
        }
    }

    private func details(_ rows: [ActivityDetail]) -> some View {
        let showsRules = theme.detailStyle == .rules || theme.detailStyle == .grouped
            || theme.detailStyle == .card
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, detail in
                if index > 0, showsRules {
                    Rectangle()
                        .fill(IslandDesign.Ink.separator)
                        .frame(height: 0.5)
                }
                HStack {
                    Text(detail.label)
                        .font(IslandDesign.Text.label)
                        .foregroundStyle(IslandDesign.Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: IslandDesign.space(3))
                    Text(detail.value)
                        .layoutPriority(1)
                        .font(IslandDesign.Text.value)
                        .foregroundStyle(IslandDesign.Ink.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, theme.detailStyle == .plain ? 3.5 : IslandDesign.space(1.25))
                // One element per row, label and value paired the way the eye
                // reads them. Left to itself VoiceOver walks the two Texts
                // separately, which turns a table into a list of orphans.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(detail.label))
                .accessibilityValue(Text(detail.value))
            }
        }
        .padding(.horizontal, theme.detailStyle == .plain ? 0 : IslandDesign.space(2.5))
        .background { detailBackground }
    }

    @ViewBuilder
    private var detailBackground: some View {
        switch theme.detailStyle {
        case .grouped:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
        case .glass:
            // A pane, not another material. Nesting materials compounds the
            // blur into mud and costs a second offscreen pass for no gain.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.09))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.26), .white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                }
        case .card:
            // WinUI dark card tokens: white 5% fill, white 8% one-pixel
            // stroke, radius 8. Circular corners — Windows arcs, not
            // superellipses.
            RoundedRectangle(cornerRadius: 8, style: .circular)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .circular)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        case .soft:
            // The exact inverse of the .soft chip: carved into the surface,
            // darker at the lit corner, stroke running shadow-to-light.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.035), Color(white: 0.075)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.5), location: 0),
                                    .init(color: .black.opacity(0.1), location: 0.5),
                                    .init(color: .white.opacity(0.07), location: 1),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        case .rules, .plain:
            Color.clear
        }
    }

    @ViewBuilder
    private func actions(_ actions: [ActivityAction]) -> some View {
        // On glass, the buttons share a container so a swap (Pause → Resume)
        // flows between shapes instead of cross-fading — the platform's echo,
        // at control scale, of the island's own metaball idea.
        if theme.actionStyle == .glass, #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                actionRow(actions, morphing: true)
            }
        } else {
            actionRow(actions, morphing: false)
        }
    }

    private func actionRow(_ actions: [ActivityAction], morphing: Bool) -> some View {
        HStack(spacing: IslandDesign.space(2)) {
            ForEach(actions) { action in
                Button {
                    onAction(action)
                } label: {
                    HStack(spacing: IslandDesign.space(1.25)) {
                        if let symbol = action.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(action.title)
                    }
                }
                .buttonStyle(
                    IslandButtonStyle(
                        tint: style.tint,
                        isDestructive: action.isDestructive,
                        kind: theme.actionStyle
                    )
                )
                .modifier(ActionMorphID(id: action.id, namespace: actionsNamespace, enabled: morphing))
            }
            Spacer(minLength: 0)
        }
    }

    /// Dots for paging between concurrent activities, the way the island cycles
    /// when more than one thing is live.
    private var switcher: some View {
        HStack(spacing: IslandDesign.space(1.5)) {
            ForEach(siblings) { sibling in
                let isCurrent = sibling.id == activity.id
                Button {
                    onSelect(sibling.id)
                } label: {
                    Capsule(style: .continuous)
                        .fill(isCurrent ? IslandDesign.Ink.primary : IslandDesign.Ink.quaternary)
                        .frame(width: isCurrent ? 15 : 5, height: 5)
                        // The visual stays a 5pt dot; the target doesn't.
                        .frame(minWidth: 16, minHeight: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // A 5pt capsule has no name. Without this VoiceOver reads
                // "button" four times and the user has no way to tell which
                // activity each one leads to.
                .accessibilityLabel(Text(sibling.content.title))
                .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Activities"))
        .animation(IslandMotion.content, value: activity.id)
    }
}

/// Tags an action button into the actions' glass container, where available.
private struct ActionMorphID: ViewModifier {
    var id: String
    var namespace: Namespace.ID
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled, #available(macOS 26.0, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - Small parts

/// Album art and app icons, with a hairline edge so they read as inset into the
/// island rather than pasted on.
struct Artwork: View {
    var icon: ActivityIcon?
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        ActivityIconView(icon: icon, size: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
    }
}

struct BreathingDot: View {
    var tint: Color
    var size: CGFloat = 7

    var body: some View {
        // Reduce Motion stops the breath and the 24fps timeline that drives
        // it. The dot still means "this is live"; it just says so by being
        // there rather than by moving — and the island stops asking the GPU
        // for a frame 24 times a second to animate a 7pt circle.
        if IslandAccessibility.shared.reduceMotion {
            dot(phase: 1)
                .frame(width: size + 5, height: size + 5)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                dot(phase: (sin(t * 2.2) + 1) / 2)
            }
            .frame(width: size + 5, height: size + 5)
        }
    }

    private func dot(phase: Double) -> some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .scaleEffect(0.84 + 0.16 * phase)
            .opacity(0.62 + 0.38 * phase)
            .glyphGlow(tint, radius: size * 0.7, intensity: 0.55)
    }
}

/// The camera / microphone in-use mark.
///
/// macOS's own convention, kept deliberately: **green means the camera is on,
/// orange means the microphone is.** When both are live the mark becomes two
/// dots, the way Control Centre shows it — a difference in *shape*, so the
/// three states are distinguishable to someone who can't separate the two hues,
/// and at the 5pt the compact slot allows.
struct PrivacyDot: View {
    var tint: Color
    var size: CGFloat
    /// Set only when a second device is also in use.
    var secondaryTint: Color?

    init(tint: Color, size: CGFloat, secondaryTint: Color? = nil) {
        self.tint = tint
        self.size = size
        self.secondaryTint = secondaryTint
    }

    var body: some View {
        HStack(spacing: size * 0.5) {
            dot(tint)
            if let secondaryTint { dot(secondaryTint) }
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: size * 0.55)
    }
}

/// Carries the expanded panel's measured height up to the island.
struct ExpandedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
