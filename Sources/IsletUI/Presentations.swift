import IsletCore
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

    public static let placeholder = ActivityStyle(tint: Color(IsletColor.accent))
}

// MARK: - Compact

/// The glyph left of the camera housing.
///
/// Apple's compact presentation is deliberately wordless: two glyphs, no text.
/// Anything needing a sentence belongs in the expanded state, and resisting the
/// urge to cram a title in here is most of what keeps it looking right.
public struct CompactLeadingView: View {
    public var activity: Activity
    public var height: CGFloat
    public var style: ActivityStyle

    public init(activity: Activity, height: CGFloat, style: ActivityStyle = .placeholder) {
        self.activity = activity
        self.height = height
        self.style = style
    }

    public var body: some View {
        let glyph = min(height - 12, 22) * style.scale
        Group {
            switch activity.nativeView {
            case .media:
                Artwork(icon: activity.content.icon, size: glyph + 3, cornerRadius: 5)
            case .privacy:
                PrivacyDot(tint: style.tint, size: glyph * 0.46)
            case .some, .none:
                ActivityIconView(icon: activity.content.icon, size: glyph, tint: style.tint)
                    .glyphGlow(style.tint, radius: glyph * 0.34, intensity: 0.42)
            }
        }
        .transition(.scale(scale: 0.62).combined(with: .opacity))
    }
}

/// The glyph right of the camera housing.
public struct CompactTrailingView: View {
    public var activity: Activity
    public var height: CGFloat
    public var style: ActivityStyle

    public init(activity: Activity, height: CGFloat, style: ActivityStyle = .placeholder) {
        self.activity = activity
        self.height = height
        self.style = style
    }

    public var body: some View {
        let content = activity.content
        let metric = 12 * style.scale
        Group {
            if activity.nativeView == .media {
                WaveformView(
                    color: style.tint,
                    isAnimating: true,
                    size: CGSize(width: 18 * style.scale, height: (height - 16) * style.scale)
                )
            } else if content.countdownTarget != nil || content.countUpFrom != nil {
                LiveTimeText(
                    target: content.countdownTarget,
                    countUpFrom: content.countUpFrom,
                    font: IslandDesign.Text.metric(metric),
                    color: style.tint
                )
                .glyphGlow(style.tint, radius: 6, intensity: 0.3)
            } else if let text = content.trailingText {
                Text(text)
                    .font(IslandDesign.Text.metric(metric))
                    .monospacedDigit()
                    .foregroundStyle(style.tint)
                    .contentTransition(.numericText())
                    .glyphGlow(style.tint, radius: 6, intensity: 0.3)
            } else if let icon = content.trailingIcon {
                ActivityIconView(
                    icon: icon,
                    size: min(height - 12, 20) * style.scale,
                    tint: style.tint
                )
                .glyphGlow(style.tint, radius: 6, intensity: 0.4)
            } else if let progress = content.progress {
                IslandProgressRing(fraction: progress.fraction, tint: style.tint)
                    .frame(
                        width: min(height - 14, 18) * style.scale,
                        height: min(height - 14, 18) * style.scale
                    )
            } else {
                BreathingDot(tint: style.tint, size: 7 * style.scale)
            }
        }
        .transition(.scale(scale: 0.62).combined(with: .opacity))
    }
}

// MARK: - Minimal

/// The detached circle that appears when a second activity is running.
public struct MinimalView: View {
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
                IslandProgressRing(fraction: progress.fraction, tint: style.tint, lineWidth: 2)
                    .frame(width: diameter - 11, height: diameter - 11)
            } else {
                ActivityIconView(
                    icon: activity.content.icon,
                    size: (diameter - 13) * style.scale,
                    tint: style.tint
                )
                .glyphGlow(style.tint, radius: 5, intensity: 0.45)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Expanded

/// The drop-down panel.
public struct ExpandedView: View {
    public var activity: Activity
    public var siblings: [Activity]
    public var style: ActivityStyle
    public var onSelect: (String) -> Void
    public var onAction: (ActivityAction) -> Void
    public var onDismiss: () -> Void

    public init(
        activity: Activity,
        siblings: [Activity] = [],
        style: ActivityStyle = .placeholder,
        onSelect: @escaping (String) -> Void = { _ in },
        onAction: @escaping (ActivityAction) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.activity = activity
        self.siblings = siblings
        self.style = style
        self.onSelect = onSelect
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let content = activity.content
        VStack(alignment: .leading, spacing: IslandDesign.space(3)) {
            header(content)

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
                    .islandTitle()
                    .lineLimit(1)
                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(IslandDesign.Text.subtitle)
                        .foregroundStyle(IslandDesign.Ink.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: IslandDesign.space(2))

            if content.countdownTarget != nil || content.countUpFrom != nil {
                LiveTimeText(
                    target: content.countdownTarget,
                    countUpFrom: content.countUpFrom,
                    font: IslandDesign.Text.metric(17),
                    color: style.tint
                )
            } else if let trailing = content.trailingText {
                Text(trailing)
                    .font(IslandDesign.Text.metric(16))
                    .monospacedDigit()
                    .foregroundStyle(style.tint)
                    .contentTransition(.numericText())
            }
        }
    }

    /// A symbol gets a tinted chip; real artwork stands on its own with a
    /// hairline so it doesn't float against the black.
    @ViewBuilder
    private func mark(_ content: ActivityContent) -> some View {
        let size: CGFloat = 38
        if case .symbol = content.icon {
            IconChip(tint: style.tint, size: size) {
                ActivityIconView(icon: content.icon, size: size * 0.52, tint: style.tint)
            }
        } else if content.icon != nil {
            Artwork(icon: content.icon, size: size, cornerRadius: size * 0.26)
        } else {
            IconChip(tint: style.tint, size: size) {
                Circle()
                    .fill(style.tint)
                    .frame(width: size * 0.22, height: size * 0.22)
            }
        }
    }

    private func details(_ rows: [ActivityDetail]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, detail in
                if index > 0 {
                    Rectangle()
                        .fill(IslandDesign.Ink.separator)
                        .frame(height: 0.5)
                }
                HStack {
                    Text(detail.label)
                        .font(IslandDesign.Text.label)
                        .foregroundStyle(IslandDesign.Ink.tertiary)
                    Spacer(minLength: IslandDesign.space(3))
                    Text(detail.value)
                        .font(IslandDesign.Text.value)
                        .foregroundStyle(IslandDesign.Ink.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, IslandDesign.space(1.25))
            }
        }
        .padding(.horizontal, IslandDesign.space(2.5))
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
        }
    }

    private func actions(_ actions: [ActivityAction]) -> some View {
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
                .buttonStyle(IslandButtonStyle(tint: style.tint, isDestructive: action.isDestructive))
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
                        .fill(isCurrent ? IslandDesign.Ink.primary : Color.white.opacity(0.22))
                        .frame(width: isCurrent ? 15 : 5, height: 5)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .animation(IslandMotion.content, value: activity.id)
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
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * 2.2) + 1) / 2
            Circle()
                .fill(tint)
                .frame(width: size, height: size)
                .scaleEffect(0.84 + 0.16 * phase)
                .opacity(0.62 + 0.38 * phase)
                .glyphGlow(tint, radius: size * 0.7, intensity: 0.55)
        }
        .frame(width: size + 5, height: size + 5)
    }
}

struct PrivacyDot: View {
    var tint: Color
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.9), radius: size * 0.55)
    }
}

/// Carries the expanded panel's measured height up to the island.
struct ExpandedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
