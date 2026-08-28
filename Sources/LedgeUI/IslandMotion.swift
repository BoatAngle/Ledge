import SwiftUI

/// The island's motion vocabulary, in one place.
///
/// Everything the island does is a spring — nothing uses a plain ease curve.
/// That is the single biggest reason Apple's version feels physical and most
/// clones feel like resizing rectangles.
public enum IslandMotion {
    /// Mirror of the system's Reduce Motion setting, maintained by
    /// `IslandAccessibility`.
    ///
    /// A plain stored flag rather than `@Environment(\.accessibilityReduceMotion)`
    /// because these animations are also consumed from `withAnimation` inside
    /// AppKit callbacks and from `ButtonStyle.makeBody` — neither of which has a
    /// SwiftUI environment to read. Written only from the main actor.
    nonisolated(unsafe) public internal(set) static var prefersReducedMotion = false

    /// Reduce Motion does not mean "no animation" — an instant cut is its own
    /// kind of jarring, and the setting's actual contract is *no large or
    /// springy movement*. Everything below collapses to a short, flat fade,
    /// which is what the system's own reduced transitions do.
    private static let reduced = Animation.easeOut(duration: 0.16)
    private static let reducedFast = Animation.easeOut(duration: 0.12)

    /// Geometry changes: growing, shrinking, splitting.
    public static var shape: Animation {
        prefersReducedMotion ? reduced : .spring(response: 0.42, dampingFraction: 0.78)
    }
    /// Content swaps inside a stable shape — a shade quicker so text doesn't
    /// lag the container it lives in.
    public static var content: Animation {
        prefersReducedMotion ? reducedFast : .spring(response: 0.30, dampingFraction: 0.86)
    }
    /// Opening the panel. A breath of overshoot, but FAST — the first tuning
    /// (0.50) read as sluggish on real hands: an invitation is not a flourish.
    public static var expand: Animation {
        prefersReducedMotion ? reduced : .spring(response: 0.40, dampingFraction: 0.80)
    }
    /// Closing it. Quick and nearly critically damped: when the user is done,
    /// the island's job is to get out of the way immediately.
    public static var collapse: Animation {
        prefersReducedMotion ? reducedFast : .spring(response: 0.30, dampingFraction: 0.95)
    }
    /// Peak blur radius during a split or merge. Zero under Reduce Motion: the
    /// metaball is pure movement, and it is the one effect here with no
    /// informational content at all.
    public static var gooPeak: CGFloat { prefersReducedMotion ? 0 : 16 }
    /// The pulse is asymmetric: liquid snaps together fast and settles slowly
    /// — but not so slowly that the island looks soft while you're waiting.
    public static let gooRise: TimeInterval = 0.16
    public static let gooFall: TimeInterval = 0.30

    /// Press choreography, shared by every button style: in is near-instant
    /// (input acknowledgment), release carries the spring personality. One
    /// vocabulary — three views had drifted to three tunings.
    public static var pressIn: Animation { .snappy(duration: 0.12, extraBounce: 0) }
    public static var pressRelease: Animation {
        // The bounce is the personality; under Reduce Motion it is also the
        // exact thing being asked for less of.
        prefersReducedMotion ? reducedFast : .spring(response: 0.32, dampingFraction: 0.55)
    }

    // No shared `contentTransition` helper here.
    //
    // There was one, and it was both unused and a warning: building a
    // `BlurReplaceTransition` needs the main actor, which a nonisolated static
    // can't promise. The two places that branch on Reduce Motion
    // (`IslandRootView.panelTransition` and the minimal circle) build their
    // transitions inline, inside a `View`, where the isolation is already
    // correct. Note that `AnyTransition` genuinely has no `.blurReplace` — only
    // the `Transition` protocol does — so the concrete type has to be built and
    // erased by hand at those sites.
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
        // Reduce Motion zeroes the peak; skip the whole animation rather than
        // animating from 0 to 0 twice per shape change.
        guard peak > 0 else { radius = 0; return }
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
