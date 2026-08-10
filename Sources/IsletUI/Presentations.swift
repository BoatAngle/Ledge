import IsletCore
import SwiftUI

// MARK: - Compact

/// The glyph that sits left of the camera housing.
///
/// Apple's compact presentation is deliberately wordless: two glyphs, no text.
/// Anything that needs a sentence belongs in the expanded state, and resisting
/// the urge to cram a title in here is most of what keeps it looking right.
public struct CompactLeadingView: View {
    public var activity: Activity
    public var height: CGFloat

    public init(activity: Activity, height: CGFloat) {
        self.activity = activity
        self.height = height
    }

    private var tint: Color {
        activity.content.tint.map(Color.init) ?? IslandPalette.defaultTint
    }

    public var body: some View {
        let glyph = min(height - 12, 22)
        Group {
            switch activity.nativeView {
            case .media:
                ActivityIconView(icon: activity.content.icon, size: glyph + 2, tint: tint)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            case .privacy:
                PrivacyDot(tint: tint, size: glyph * 0.5)
            case .some, .none:
                ActivityIconView(icon: activity.content.icon, size: glyph, tint: tint)
            }
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

/// The glyph that sits right of the camera housing.
public struct CompactTrailingView: View {
    public var activity: Activity
    public var height: CGFloat

    public init(activity: Activity, height: CGFloat) {
        self.activity = activity
        self.height = height
    }

    private var tint: Color {
        activity.content.tint.map(Color.init) ?? IslandPalette.defaultTint
    }

    public var body: some View {
        let content = activity.content
        Group {
            if activity.nativeView == .media {
                WaveformView(color: tint, isAnimating: true, size: CGSize(width: 18, height: height - 16))
            } else if content.countdownTarget != nil || content.countUpFrom != nil {
                LiveTimeText(
                    target: content.countdownTarget,
                    countUpFrom: content.countUpFrom,
                    font: .system(size: 12, weight: .semibold, design: .rounded),
                    color: tint
                )
            } else if let text = content.trailingText {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            } else if let icon = content.trailingIcon {
                ActivityIconView(icon: icon, size: min(height - 12, 20), tint: tint)
            } else if let progress = content.progress {
                IslandProgressRing(fraction: progress.fraction, tint: tint)
                    .frame(width: min(height - 14, 18), height: min(height - 14, 18))
            } else {
                // Nothing specific to say — a soft pulse still signals "live".
                BreathingDot(tint: tint)
            }
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

// MARK: - Minimal

/// The detached circle that appears when a second activity is running.
public struct MinimalView: View {
    public var activity: Activity
    public var diameter: CGFloat

    public init(activity: Activity, diameter: CGFloat) {
        self.activity = activity
        self.diameter = diameter
    }

    private var tint: Color {
        activity.content.tint.map(Color.init) ?? IslandPalette.defaultTint
    }

    public var body: some View {
        Group {
            if activity.nativeView == .media {
                ActivityIconView(icon: activity.content.icon, size: diameter - 8, tint: tint)
                    .clipShape(Circle())
            } else if let progress = activity.content.progress {
                IslandProgressRing(fraction: progress.fraction, tint: tint, lineWidth: 2)
                    .frame(width: diameter - 10, height: diameter - 10)
            } else {
                ActivityIconView(icon: activity.content.icon, size: diameter - 13, tint: tint)
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
    public var onSelect: (String) -> Void
    public var onAction: (ActivityAction) -> Void
    public var onDismiss: () -> Void

    public init(
        activity: Activity,
        siblings: [Activity] = [],
        onSelect: @escaping (String) -> Void = { _ in },
        onAction: @escaping (ActivityAction) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.activity = activity
        self.siblings = siblings
        self.onSelect = onSelect
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    private var tint: Color {
        activity.content.tint.map(Color.init) ?? IslandPalette.defaultTint
    }

    public var body: some View {
        let content = activity.content
        VStack(alignment: .leading, spacing: 12) {
            header(content)

            if let body = content.body {
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(IslandPalette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let progress = content.progress {
                VStack(alignment: .leading, spacing: 5) {
                    IslandProgressBar(progress: progress, tint: tint)
                    if let label = progress.label {
                        Text(label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(IslandPalette.tertiaryText)
                    }
                }
            }

            if !content.details.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(content.details.enumerated()), id: \.offset) { _, detail in
                        HStack {
                            Text(detail.label)
                                .font(.system(size: 11))
                                .foregroundStyle(IslandPalette.tertiaryText)
                            Spacer(minLength: 12)
                            Text(detail.value)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(IslandPalette.secondaryText)
                                .monospacedDigit()
                        }
                    }
                }
            }

            if !content.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(content.actions) { action in
                        Button {
                            onAction(action)
                        } label: {
                            HStack(spacing: 5) {
                                if let symbol = action.symbol {
                                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                                }
                                Text(action.title).font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    action.isDestructive
                                        ? Color.red.opacity(0.22)
                                        : IslandPalette.controlFill
                                )
                            )
                            .foregroundStyle(action.isDestructive ? Color.red : IslandPalette.primaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }

            if siblings.count > 1 {
                switcher
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
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
        HStack(spacing: 12) {
            ActivityIconView(icon: content.icon, size: 38, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IslandPalette.primaryText)
                    .lineLimit(1)
                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(IslandPalette.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if content.countdownTarget != nil || content.countUpFrom != nil {
                LiveTimeText(
                    target: content.countdownTarget,
                    countUpFrom: content.countUpFrom,
                    font: .system(size: 17, weight: .semibold, design: .rounded),
                    color: tint
                )
            } else if let trailing = content.trailingText {
                Text(trailing)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
        }
    }

    /// Dots for paging between concurrent activities, the way the island cycles
    /// when more than one thing is live.
    private var switcher: some View {
        HStack(spacing: 6) {
            ForEach(siblings) { sibling in
                Button {
                    onSelect(sibling.id)
                } label: {
                    Capsule()
                        .fill(sibling.id == activity.id
                              ? IslandPalette.primaryText
                              : Color.white.opacity(0.25))
                        .frame(width: sibling.id == activity.id ? 16 : 6, height: 6)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .animation(IslandMotion.content, value: activity.id)
    }
}

// MARK: - Small parts

struct BreathingDot: View {
    var tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let scale = 0.82 + 0.18 * (sin(t * 2.4) + 1) / 2
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .scaleEffect(scale)
                .opacity(0.65 + 0.35 * scale)
        }
        .frame(width: 12, height: 12)
    }
}

struct PrivacyDot: View {
    var tint: Color
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.8), radius: size * 0.5)
    }
}

/// Carries the expanded panel's measured height up to the island.
struct ExpandedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
