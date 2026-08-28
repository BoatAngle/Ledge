import XCTest
@testable import LedgeCore

@MainActor
final class LedgeSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A private suite: these tests must not touch the user's real prefs.
        suiteName = "dev.ledge.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaults() {
        let settings = LedgeSettings(defaults: defaults)
        XCTAssertTrue(settings.expandOnHover)
        XCTAssertEqual(settings.hoverDelay, 400)
        XCTAssertTrue(settings.animateArrivals)
        XCTAssertTrue(settings.showOnNotchlessDisplays)
        XCTAssertFalse(settings.weatherAlerts)
        XCTAssertEqual(settings.weatherLocationMode, .automatic)
    }

    /// Weather is ambient state, not an event. Defaulting it to always-visible
    /// would mean the island is never idle, which is the property that makes it
    /// read as hardware rather than a widget.
    func testWeatherDefaultsToOnDemandRatherThanAmbient() {
        XCTAssertEqual(LedgeSettings(defaults: defaults).weatherMode, .onDemand)
    }

    func testValuesPersist() {
        let first = LedgeSettings(defaults: defaults)
        first.hoverDelay = 500
        first.weatherMode = .ambient
        first.temperatureUnit = .fahrenheit
        first.expandOnHover = false

        let second = LedgeSettings(defaults: defaults)
        XCTAssertEqual(second.hoverDelay, 500)
        XCTAssertEqual(second.weatherMode, .ambient)
        XCTAssertEqual(second.temperatureUnit, .fahrenheit)
        XCTAssertFalse(second.expandOnHover)
    }

    func testModulesAreOnUnlessTurnedOff() {
        let settings = LedgeSettings(defaults: defaults)
        XCTAssertTrue(settings.isModuleEnabled("system.media"), "Unset means enabled")

        settings.setModule("system.media", enabled: false)
        XCTAssertFalse(settings.isModuleEnabled("system.media"))
        XCTAssertTrue(settings.isModuleEnabled("system.battery"), "Others unaffected")

        settings.setModule("system.media", enabled: true)
        XCTAssertTrue(settings.isModuleEnabled("system.media"))
    }

    /// Module state lives in UserDefaults rather than a stored property, so it
    /// needs an explicit nudge for `@Observable` to notice.
    func testTogglingAModuleBumpsTheObservableRevision() {
        let settings = LedgeSettings(defaults: defaults)
        let before = settings.moduleRevision
        settings.setModule("system.media", enabled: false)
        XCTAssertNotEqual(settings.moduleRevision, before)
    }

    func testModuleKeyIsUnchangedSoExistingPreferencesSurvive() {
        // The key format predates this type; changing it would silently
        // re-enable modules the user had turned off.
        XCTAssertEqual(LedgeSettings.Keys.module("system.media"), "module.system.media.enabled")
    }

    func testResetRestoresDefaultsAndClearsModules() {
        let settings = LedgeSettings(defaults: defaults)
        settings.hoverDelay = 700
        settings.weatherMode = .off
        settings.setModule("system.media", enabled: false)

        settings.resetToDefaults()

        XCTAssertEqual(settings.hoverDelay, 400)
        XCTAssertEqual(settings.weatherMode, .onDemand)
        XCTAssertTrue(settings.isModuleEnabled("system.media"))
    }

    func testTemperatureUnitFollowsTheRegion() {
        // Whatever the machine's locale says, it must be one of the two.
        XCTAssertTrue([.celsius, .fahrenheit].contains(TemperatureUnit.localeDefault))
    }
}

@MainActor
final class AppearanceSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "dev.ledge.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAppearanceDefaultsAndPersists() {
        let settings = LedgeSettings(defaults: defaults)
        XCTAssertTrue(settings.appearance(for: "system.media").isDefault)

        settings.setAppearance(
            ModuleAppearance(tint: .purple, scale: 1.1, slot: .minimal),
            for: "system.media"
        )

        let reloaded = LedgeSettings(defaults: defaults)
        let stored = reloaded.appearance(for: "system.media")
        XCTAssertEqual(stored.tint, .purple)
        XCTAssertEqual(stored.scale, 1.1, accuracy: 0.001)
        XCTAssertEqual(stored.slot, .minimal)
        XCTAssertTrue(reloaded.appearance(for: "system.timer").isDefault, "Others unaffected")
    }

    /// Storing nothing for a default keeps future changes to what "default"
    /// means reaching anyone who never customised the module.
    func testSettingBackToDefaultRemovesTheStoredValue() {
        let settings = LedgeSettings(defaults: defaults)
        settings.setAppearance(ModuleAppearance(scale: 1.2), for: "system.media")
        XCTAssertNotNil(defaults.data(forKey: "appearance.system.media"))

        settings.setAppearance(.default, for: "system.media")
        XCTAssertNil(defaults.data(forKey: "appearance.system.media"))
    }

    func testAppearanceChangeBumpsTheObservableRevision() {
        let settings = LedgeSettings(defaults: defaults)
        let before = settings.appearanceRevision
        settings.setAppearance(ModuleAppearance(scale: 1.2), for: "system.media")
        XCTAssertNotEqual(settings.appearanceRevision, before)
    }

    /// Recorded because it's a design decision, not an accident: Glass is the
    /// direction that got picked, so a fresh install should show it.
    func testGlassIsTheShippedDefault() {
        XCTAssertEqual(LedgeSettings(defaults: defaults).theme, .glass)
    }

    func testThemeSurvivesRelaunch() {
        let settings = LedgeSettings(defaults: defaults)
        settings.theme = .editorial
        XCTAssertEqual(LedgeSettings(defaults: defaults).theme, .editorial)
    }

    func testResetClearsAppearance() {
        let settings = LedgeSettings(defaults: defaults)
        settings.setAppearance(ModuleAppearance(tint: .red), for: "system.media")
        settings.resetToDefaults()
        XCTAssertTrue(settings.appearance(for: "system.media").isDefault)
    }
}
