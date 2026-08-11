import XCTest
@testable import IsletCore

@MainActor
final class IsletSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A private suite: these tests must not touch the user's real prefs.
        suiteName = "dev.islet.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaults() {
        let settings = IsletSettings(defaults: defaults)
        XCTAssertTrue(settings.expandOnHover)
        XCTAssertEqual(settings.hoverDelay, 220)
        XCTAssertTrue(settings.animateArrivals)
        XCTAssertTrue(settings.showOnNotchlessDisplays)
        XCTAssertFalse(settings.weatherAlerts)
        XCTAssertEqual(settings.weatherLocationMode, .automatic)
    }

    /// Weather is ambient state, not an event. Defaulting it to always-visible
    /// would mean the island is never idle, which is the property that makes it
    /// read as hardware rather than a widget.
    func testWeatherDefaultsToOnDemandRatherThanAmbient() {
        XCTAssertEqual(IsletSettings(defaults: defaults).weatherMode, .onDemand)
    }

    func testValuesPersist() {
        let first = IsletSettings(defaults: defaults)
        first.hoverDelay = 500
        first.weatherMode = .ambient
        first.temperatureUnit = .fahrenheit
        first.expandOnHover = false

        let second = IsletSettings(defaults: defaults)
        XCTAssertEqual(second.hoverDelay, 500)
        XCTAssertEqual(second.weatherMode, .ambient)
        XCTAssertEqual(second.temperatureUnit, .fahrenheit)
        XCTAssertFalse(second.expandOnHover)
    }

    func testModulesAreOnUnlessTurnedOff() {
        let settings = IsletSettings(defaults: defaults)
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
        let settings = IsletSettings(defaults: defaults)
        let before = settings.moduleRevision
        settings.setModule("system.media", enabled: false)
        XCTAssertNotEqual(settings.moduleRevision, before)
    }

    func testModuleKeyIsUnchangedSoExistingPreferencesSurvive() {
        // The key format predates this type; changing it would silently
        // re-enable modules the user had turned off.
        XCTAssertEqual(IsletSettings.Keys.module("system.media"), "module.system.media.enabled")
    }

    func testResetRestoresDefaultsAndClearsModules() {
        let settings = IsletSettings(defaults: defaults)
        settings.hoverDelay = 700
        settings.weatherMode = .off
        settings.setModule("system.media", enabled: false)

        settings.resetToDefaults()

        XCTAssertEqual(settings.hoverDelay, 220)
        XCTAssertEqual(settings.weatherMode, .onDemand)
        XCTAssertTrue(settings.isModuleEnabled("system.media"))
    }

    func testTemperatureUnitFollowsTheRegion() {
        // Whatever the machine's locale says, it must be one of the two.
        XCTAssertTrue([.celsius, .fahrenheit].contains(TemperatureUnit.localeDefault))
    }
}
