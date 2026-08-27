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
    /// Opening the panel. A breath of overshoot, but FAST — the first tuning
    /// (0.50) read as sluggish on real hands: an invitation is not a flourish.
    public static let expand = Animation.spring(response: 0.40, dampingFraction: 0.80)
    /// Closing it. Quick and nearly critically damped: when the user is done,
    /// the island's job is to get out of the way immediately.
    public static let collapse = Animation.spring(response: 0.30, dampingFraction: 0.95)
    /// Peak blur radius during a split or merge.
    public static let gooPeak: CGFloat = 16
    /// The pulse is asymmetric: liquid snaps together fast and settles slowly
    /// — but not so slowly that the island looks soft while you're waiting.
    public static let gooRise: TimeInterval = 0.16
    public static let gooFall: TimeInterval = 0.30
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
            withAnimation(.easeOut(duration: IslandMotion.gooRise)) { self.radius = peak }
            try? await Task.sleep(for: .seconds(IslandMotion.gooRise))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: IslandMotion.gooFall)) { self.radius = 0 }
        }
    }

    isolated deinit {
        task?.cancel()
    }
}
