import Foundation

/// Where a module prefers to sit when the island has more than one thing to say.
public enum ModuleSlot: String, Codable, CaseIterable, Hashable, Sendable {
    /// Let priority decide, as normal.
    case automatic
    /// Bias toward leading the compact presentation.
    case leading
    /// Bias toward the detached circle, staying out of the way.
    case minimal

    public var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .leading: return "Front"
        case .minimal: return "Small circle"
        }
    }

    public var explanation: String {
        switch self {
        case .automatic:
            return "Priority decides, the way it does for everything else."
        case .leading:
            return "Comes forward ahead of other activities when several are live."
        case .minimal:
            return "Stays in the detached circle unless nothing else is running."
        }
    }
}

/// Per-module look and placement.
///
/// Deliberately a small, closed set. A theming system with arbitrary fonts and
/// spacing would let anyone build something that no longer looks like the
/// island; colour, size and placement cover what people actually want to change
/// without letting the design come apart.
public struct ModuleAppearance: Codable, Hashable, Sendable {
    /// Overrides the module's own tint. `nil` keeps whatever it chose.
    public var tint: IsletColor?
    /// Multiplier on glyph and text size, clamped to a range that still fits
    /// the notch.
    public var scale: Double
    public var slot: ModuleSlot
    /// Nudges the module up or down the ordering without rewriting priorities.
    public var priorityOffset: Int

    public static let scaleRange: ClosedRange<Double> = 0.8...1.25
    public static let priorityRange: ClosedRange<Int> = -200...200

    public static let `default` = ModuleAppearance()

    public init(
        tint: IsletColor? = nil,
        scale: Double = 1,
        slot: ModuleSlot = .automatic,
        priorityOffset: Int = 0
    ) {
        self.tint = tint
        self.scale = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        self.slot = slot
        self.priorityOffset = min(
            max(priorityOffset, Self.priorityRange.lowerBound),
            Self.priorityRange.upperBound
        )
    }

    /// True when nothing has been changed from the defaults, so the UI can show
    /// "Customised" only where it's true.
    public var isDefault: Bool {
        tint == nil && scale == 1 && slot == .automatic && priorityOffset == 0
    }

    /// Decoding has to clamp too — the values land in `UserDefaults`, which
    /// anyone can write to with `defaults write`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tint = try container.decodeIfPresent(IsletColor.self, forKey: .tint)
        let scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        let slot = try container.decodeIfPresent(ModuleSlot.self, forKey: .slot) ?? .automatic
        let offset = try container.decodeIfPresent(Int.self, forKey: .priorityOffset) ?? 0
        self.init(tint: tint, scale: scale, slot: slot, priorityOffset: offset)
    }
}
