import SwiftUI

/// The island's motion vocabulary, in one place.
///
/// Everything the island does is a spring — nothing uses a plain ease curve.
/// That is the single biggest reason Apple's version feels physical and most
/// clones feel like resizing rectangles.
public enum IslandMotion {
    /// Geometry changes: growing, shrinking, splitting.
    public static let shape = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Content swaps inside a stable shape — a shade quicker so text doesn't
    /// lag the container it lives in.
    public static let content = Animation.spring(response: 0.30, dampingFraction: 0.86)
    /// Opening and closing the panel. Slightly looser, with a little overshoot.
    public static let expand = Animation.spring(response: 0.48, dampingFraction: 0.80)
    /// The nudge a newly arrived activity gives the island.
    public static let arrival = Animation.spring(response: 0.34, dampingFraction: 0.58)

    /// Peak blur radius during a split or merge.
    public static let gooPeak: CGFloat = 16
    /// How long the goo pulse lasts. Long enough to read as liquid, short
    /// enough that the shapes are crisp by the time the eye settles.
    public static let gooDuration: TimeInterval = 0.42
}

/// Drives the metaball blur through a rise-and-fall pulse whenever the island's
/// structure changes.
@MainActor
@Observable
public final class GooDriver {
    public private(set) var radius: CGFloat = 0
    private var task: Task<Void, Never>?

    public init() {}

    /// Pulse the goo. Safe to call repeatedly; a new pulse replaces the old.
    public func pulse(peak: CGFloat = IslandMotion.gooPeak) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let half = IslandMotion.gooDuration / 2
            withAnimation(.easeOut(duration: half)) { self.radius = peak }
            try? await Task.sleep(for: .seconds(half))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: half)) { self.radius = 0 }
        }
    }

    isolated deinit {
        task?.cancel()
    }
}
