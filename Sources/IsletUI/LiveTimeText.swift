import IsletCore
import SwiftUI

/// A clock that ticks locally.
///
/// Activities that count down (a timer) or up (call duration) shouldn't need
/// the posting process to send an update every second — it would burn a socket
/// round trip per tick and still drift. The client declares a target date once
/// and the island animates it from there.
public struct LiveTimeText: View {
    public var target: Date?
    public var countUpFrom: Date?
    public var font: Font
    public var color: Color

    public init(
        target: Date? = nil,
        countUpFrom: Date? = nil,
        font: Font = .system(size: 13, weight: .semibold, design: .rounded),
        color: Color = IslandPalette.primaryText
    ) {
        self.target = target
        self.countUpFrom = countUpFrom
        self.font = font
        self.color = color
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(text(at: context.date))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
    }

    private func text(at now: Date) -> String {
        if let target {
            return Self.format(max(0, target.timeIntervalSince(now)))
        }
        if let countUpFrom {
            return Self.format(max(0, now.timeIntervalSince(countUpFrom)))
        }
        return "--:--"
    }

    /// `M:SS` under an hour, `H:MM:SS` above — the same thresholds the system
    /// timer uses, so the island never looks out of step with it.
    public static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Four bars that bounce while something is playing.
public struct WaveformView: View {
    public var color: Color
    public var isAnimating: Bool
    public var barCount: Int = 4
    public var size: CGSize = CGSize(width: 18, height: 14)

    public init(
        color: Color,
        isAnimating: Bool = true,
        barCount: Int = 4,
        size: CGSize = CGSize(width: 18, height: 14)
    ) {
        self.color = color
        self.isAnimating = isAnimating
        self.barCount = barCount
        self.size = size
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isAnimating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: 2.5, height: height(index: index, t: t))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .center)
        }
    }

    private func height(index: Int, t: Double) -> CGFloat {
        guard isAnimating else { return size.height * 0.28 }
        // Irrational-ish per-bar phase offsets keep the bars from marching in
        // lockstep, which is what makes it read as audio rather than a loader.
        let phase = t * 5.4 + Double(index) * 1.37
        let wave = (sin(phase) + sin(phase * 0.63)) / 2
        let normalized = (wave + 1) / 2
        return size.height * (0.26 + 0.74 * normalized)
    }
}

/// Determinate or indeterminate progress, drawn as a thin capsule track.
public struct IslandProgressBar: View {
    public var progress: ActivityProgress
    public var tint: Color
    public var height: CGFloat = 5

    public init(progress: ActivityProgress, tint: Color, height: CGFloat = 5) {
        self.progress = progress
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(IslandDesign.Ink.trackFill)
                    // A hairline along the top of the track reads as a recess
                    // rather than a painted stripe.
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.black.opacity(0.35))
                            .frame(height: 0.5)
                    }
                if let fraction = progress.fraction {
                    Capsule()
                        .fill(IslandDesign.tintGradient(tint))
                        .frame(width: max(height, proxy.size.width * fraction))
                        .shadow(color: tint.opacity(0.45), radius: 3)
                        .animation(IslandMotion.content, value: fraction)
                } else {
                    IndeterminateSweep(tint: tint, width: proxy.size.width)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

private struct IndeterminateSweep: View {
    var tint: Color
    var width: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let period = 1.4
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let segment = width * 0.35
            // Ease the sweep so it decelerates at each end instead of wrapping
            // with a visible seam.
            let eased = (1 - cos(t * 2 * .pi)) / 2
            Capsule()
                .fill(IslandDesign.tintGradient(tint))
                .frame(width: segment)
                .shadow(color: tint.opacity(0.4), radius: 3)
                .offset(x: eased * (width - segment))
        }
    }
}

/// A ring, for compact-slot progress where a bar won't fit.
public struct IslandProgressRing: View {
    public var fraction: Double?
    public var tint: Color
    public var lineWidth: CGFloat = 2.5

    public init(fraction: Double?, tint: Color, lineWidth: CGFloat = 2.5) {
        self.fraction = fraction
        self.tint = tint
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(IslandDesign.Ink.trackFill, lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.001, fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.55), radius: 2.5)
                    .animation(IslandMotion.content, value: fraction)
            } else {
                SpinningArc(tint: tint, lineWidth: lineWidth)
            }
        }
    }
}

private struct SpinningArc: View {
    var tint: Color
    var lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate * 220
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .shadow(color: tint.opacity(0.55), radius: 2.5)
                .rotationEffect(.degrees(angle))
        }
    }
}
