import Foundation
import Observation

/// How much of the island the weather module is allowed to occupy.
public enum WeatherMode: String, Codable, CaseIterable, Sendable {
    /// Never posts anything.
    case off
    /// Shows for a few seconds when asked — the menu bar, `islet weather`, or
    /// a Shortcut.
    case onDemand
    /// Sits on the island permanently, at the lowest priority, so anything
    /// actually happening takes precedence.
    case ambient

    public var label: String {
        switch self {
        case .off: return "Off"
        case .onDemand: return "On demand"
        case .ambient: return "Always visible"
        }
    }

    public var explanation: String {
        switch self {
        case .off:
            return "Islet never checks the weather."
        case .onDemand:
            return "Shows briefly when you ask for it. The island stays empty otherwise."
        case .ambient:
            return "Always on the island when nothing else is happening."
        }
    }
}

public enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case celsius
    case fahrenheit

    public var label: String {
        switch self {
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        }
    }

    public var suffix: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    /// What the user's region uses, so the default is right without asking.
    public static var localeDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

public enum WeatherLocationMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case manual

    public var label: String {
        switch self {
        case .automatic: return "Use my location"
        case .manual: return "Enter coordinates"
        }
    }
}

/// Every user-facing preference, in one observable place.
///
/// Values are held in memory and written through to `UserDefaults`, rather than
/// read from it on access: `@Observable` can only track stored properties, and
/// a computed property reading `UserDefaults` would leave the settings window
/// showing stale values.
@MainActor
@Observable
public final class IsletSettings {
    public static let shared = IsletSettings()

    private let defaults: UserDefaults

    // MARK: Interaction

    /// Whether resting the cursor on the island opens the panel.
    public var expandOnHover: Bool {
        didSet { defaults.set(expandOnHover, forKey: Keys.expandOnHover) }
    }

    /// Milliseconds the cursor must rest before the panel opens.
    public var hoverDelay: Double {
        didSet { defaults.set(hoverDelay, forKey: Keys.hoverDelay) }
    }

    /// Draw a virtual island on displays with no camera housing.
    public var showOnNotchlessDisplays: Bool {
        didSet { defaults.set(showOnNotchlessDisplays, forKey: Keys.showOnNotchless) }
    }

    /// Play the small bounce when an activity arrives.
    public var animateArrivals: Bool {
        didSet { defaults.set(animateArrivals, forKey: Keys.animateArrivals) }
    }

    /// The island's overall visual direction.
    public var theme: IslandThemeID {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            NotificationCenter.default.post(name: .isletAppearanceChanged, object: nil)
        }
    }

    // MARK: Weather

    public var weatherMode: WeatherMode {
        didSet { defaults.set(weatherMode.rawValue, forKey: Keys.weatherMode) }
    }

    public var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Keys.temperatureUnit) }
    }

    public var weatherLocationMode: WeatherLocationMode {
        didSet { defaults.set(weatherLocationMode.rawValue, forKey: Keys.weatherLocationMode) }
    }

    public var manualLatitude: Double {
        didSet { defaults.set(manualLatitude, forKey: Keys.manualLatitude) }
    }

    public var manualLongitude: Double {
        didSet { defaults.set(manualLongitude, forKey: Keys.manualLongitude) }
    }

    public var manualPlaceName: String {
        didSet { defaults.set(manualPlaceName, forKey: Keys.manualPlaceName) }
    }

    /// Flash the island when rain or snow starts.
    public var weatherAlerts: Bool {
        didSet { defaults.set(weatherAlerts, forKey: Keys.weatherAlerts) }
    }

    // MARK: Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        expandOnHover = defaults.object(forKey: Keys.expandOnHover) as? Bool ?? true
        // 400, up from 220: with the stationary-pointer gate the delay is the
        // second line of defence, and 220 sat inside the natural correction
        // pause when aiming at menu bar targets near the notch. Values stored
        // at the old default migrate — 220 was never a choice anyone made.
        let storedDelay = defaults.object(forKey: Keys.hoverDelay) as? Double
        hoverDelay = (storedDelay == nil || storedDelay == 220) ? 400 : storedDelay!
        showOnNotchlessDisplays = defaults.object(forKey: Keys.showOnNotchless) as? Bool ?? true
        animateArrivals = defaults.object(forKey: Keys.animateArrivals) as? Bool ?? true
        theme = (defaults.string(forKey: Keys.theme)
            .flatMap(IslandThemeID.init(rawValue:))) ?? .glass

        // On-demand rather than always-visible by default. A permanent readout
        // would mean the island is never actually idle, and "invisible until
        // something happens" is the property that makes it read as hardware
        // rather than as a widget stuck to the bezel. One toggle away.
        weatherMode = (defaults.string(forKey: Keys.weatherMode)
            .flatMap(WeatherMode.init(rawValue:))) ?? .onDemand
        temperatureUnit = (defaults.string(forKey: Keys.temperatureUnit)
            .flatMap(TemperatureUnit.init(rawValue:))) ?? .localeDefault
        weatherLocationMode = (defaults.string(forKey: Keys.weatherLocationMode)
            .flatMap(WeatherLocationMode.init(rawValue:))) ?? .automatic
        manualLatitude = defaults.object(forKey: Keys.manualLatitude) as? Double ?? 0
        manualLongitude = defaults.object(forKey: Keys.manualLongitude) as? Double ?? 0
        manualPlaceName = defaults.string(forKey: Keys.manualPlaceName) ?? ""
        weatherAlerts = defaults.object(forKey: Keys.weatherAlerts) as? Bool ?? false
    }

    // MARK: Modules

    /// Modules are on unless the user has turned them off.
    public func isModuleEnabled(_ identifier: String) -> Bool {
        let key = Keys.module(identifier)
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    public func setModule(_ identifier: String, enabled: Bool) {
        defaults.set(enabled, forKey: Keys.module(identifier))
        // Stored separately from the observable properties above, so nudge
        // observers explicitly — the settings window needs to redraw.
        moduleRevision &+= 1
    }

    /// Bumped whenever a module is toggled, purely so `@Observable` has a
    /// stored property to notice.
    public private(set) var moduleRevision: UInt64 = 0

    // MARK: Permission bookkeeping

    /// Whether a module has ever raised its consent dialog on its own.
    ///
    /// The one-and-done rule: a TCC dialog dismissed by an app relaunch (or a
    /// reboot, or plain inattention) leaves the system in `.notDetermined`,
    /// and re-requesting at every launch turns consent into a nag. Each
    /// prompting module asks once, ever; after that the dialog appears only
    /// from an explicit Grant Access gesture in Settings.
    public func hasAutoRequestedPermission(_ identifier: String) -> Bool {
        defaults.bool(forKey: "permission.\(identifier).requested")
    }

    public func markPermissionAutoRequested(_ identifier: String) {
        defaults.set(true, forKey: "permission.\(identifier).requested")
    }

    /// For permissions with no queryable status (the Downloads folder):
    /// remembers that access has verifiably worked at least once.
    public func hasVerifiedPermission(_ identifier: String) -> Bool {
        defaults.bool(forKey: "permission.\(identifier).verified")
    }

    public func markPermissionVerified(_ identifier: String) {
        defaults.set(true, forKey: "permission.\(identifier).verified")
        moduleRevision &+= 1
    }

    // MARK: Appearance

    /// Per-module colour, size, and placement.
    public func appearance(for identifier: String) -> ModuleAppearance {
        guard let data = defaults.data(forKey: Keys.appearance(identifier)),
              let decoded = try? JSONDecoder().decode(ModuleAppearance.self, from: data)
        else { return .default }
        return decoded
    }

    public func setAppearance(_ appearance: ModuleAppearance, for identifier: String) {
        if appearance.isDefault {
            // Store nothing for defaults, so a future change to what "default"
            // means reaches anyone who never customised the module.
            defaults.removeObject(forKey: Keys.appearance(identifier))
        } else if let data = try? JSONEncoder().encode(appearance) {
            defaults.set(data, forKey: Keys.appearance(identifier))
        }
        appearanceRevision &+= 1
        NotificationCenter.default.post(name: .isletAppearanceChanged, object: nil)
    }

    public func resetAppearance(for identifier: String) {
        defaults.removeObject(forKey: Keys.appearance(identifier))
        appearanceRevision &+= 1
        NotificationCenter.default.post(name: .isletAppearanceChanged, object: nil)
    }

    /// Observable stand-in for appearance, which lives in `UserDefaults`.
    public private(set) var appearanceRevision: UInt64 = 0

    public func resetToDefaults() {
        for key in Keys.all { defaults.removeObject(forKey: key) }
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("module.") || key.hasPrefix("appearance.") {
            defaults.removeObject(forKey: key)
        }
        expandOnHover = true
        hoverDelay = 400
        showOnNotchlessDisplays = true
        animateArrivals = true
        theme = .glass
        weatherMode = .onDemand
        temperatureUnit = .localeDefault
        weatherLocationMode = .automatic
        manualLatitude = 0
        manualLongitude = 0
        manualPlaceName = ""
        weatherAlerts = false
        moduleRevision &+= 1
        appearanceRevision &+= 1
        NotificationCenter.default.post(name: .isletAppearanceChanged, object: nil)
    }

    enum Keys {
        static let expandOnHover = "interaction.expandOnHover"
        static let hoverDelay = "interaction.hoverDelay"
        static let showOnNotchless = "interaction.showOnNotchlessDisplays"
        static let animateArrivals = "interaction.animateArrivals"
        static let theme = "island.theme"
        static let weatherMode = "weather.mode"
        static let temperatureUnit = "weather.temperatureUnit"
        static let weatherLocationMode = "weather.locationMode"
        static let manualLatitude = "weather.manualLatitude"
        static let manualLongitude = "weather.manualLongitude"
        static let manualPlaceName = "weather.manualPlaceName"
        static let weatherAlerts = "weather.alerts"

        /// Unchanged from the original ad-hoc key so existing preferences
        /// survive the move into this type.
        static func module(_ identifier: String) -> String {
            "module.\(identifier).enabled"
        }

        static func appearance(_ identifier: String) -> String {
            "appearance.\(identifier)"
        }

        static let all = [
            expandOnHover, hoverDelay, showOnNotchless, animateArrivals,
            theme, weatherMode, temperatureUnit, weatherLocationMode,
            manualLatitude, manualLongitude, manualPlaceName, weatherAlerts,
        ]
    }
}

/// The island's overall visual direction.
///
/// A theme is a coherent set of choices — material, glyph treatment, how much
/// colour is used, type scale — not a colour swap. Each one is meant to be
/// defensible on its own terms rather than a slider position between the others.
public enum IslandThemeID: String, Codable, CaseIterable, Sendable {
    /// Restrained, reads as part of macOS chrome.
    case system
    /// Saturated and confident, closest to Apple's own Dynamic Island.
    case vivid
    /// Translucent materials and specular edges.
    case glass
    /// Type-led and quiet, hairline rules instead of filled containers.
    case editorial
    /// Windows 11: acrylic, tight corners, one-pixel strokes.
    case fluent
    /// Material 3 dark: flat tonal containers, full pills.
    case material
    /// Emissive accents on a void-black body.
    case neon
    /// Dark neumorphism: controls extruded from the surface.
    case soft
    /// Terminal chic: monospaced, hairlines, bracketed commands.
    case mono

    public var label: String {
        switch self {
        case .system: return "System"
        case .vivid: return "Vivid"
        case .glass: return "Glass"
        case .editorial: return "Editorial"
        case .fluent: return "Fluent"
        case .material: return "Material"
        case .neon: return "Neon"
        case .soft: return "Soft"
        case .mono: return "Mono"
        }
    }

    public var explanation: String {
        switch self {
        case .system:
            return "Monochrome glyphs, color only where it carries meaning. Sits quietly alongside the menu bar."
        case .vivid:
            return "Saturated, filled glyphs with a soft bloom. Closest to the iPhone's Dynamic Island."
        case .glass:
            return "Translucent panel over a frosted blur, with lit edges."
        case .editorial:
            return "Type first. Hairline rules, generous spacing, one restrained accent."
        case .fluent:
            return "Frosted acrylic behind tight corners and one-pixel strokes, with color saved for the controls — the island as Windows 11 would draw it."
        case .material:
            return "Flat tonal containers, filled marks, full-pill buttons. Material 3's dark scheme — elevation told in tone, never in shadow."
        case .neon:
            return "Emissive on true black. Outlined glyphs glow like tube light, edges run bright, and color reads as light rather than paint."
        case .soft:
            return "Controls rise out of the surface on soft dual shadows and press back in. Muted color, pillowy corners, no hard edges."
        case .mono:
            return "Monospaced type, hairline rules, commands in brackets. The island as a status line."
        }
    }
}
