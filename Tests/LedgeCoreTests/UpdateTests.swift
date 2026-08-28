import XCTest
@testable import LedgeCore

/// The classic way an update check goes wrong is string comparison, which
/// cheerfully reports 0.10.0 as older than 0.9.0 and offers a downgrade.
final class SemanticVersionTests: XCTestCase {
    func testOrdersByNumberNotByText() {
        XCTAssertLessThan(SemanticVersion("0.9.0")!, SemanticVersion("0.10.0")!)
        XCTAssertLessThan(SemanticVersion("1.9.9")!, SemanticVersion("1.10.0")!)
        XCTAssertGreaterThan(SemanticVersion("2.0.0")!, SemanticVersion("1.99.99")!)
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(SemanticVersion("1.2"), SemanticVersion("1.2.0"))
        XCTAssertLessThan(SemanticVersion("1.2")!, SemanticVersion("1.2.1")!)
    }

    func testAcceptsTheVPrefixGitHubTagsUse() {
        XCTAssertEqual(SemanticVersion("v0.2.0"), SemanticVersion("0.2.0"))
    }

    func testPreReleaseTailIsIgnoredForOrdering() {
        // A build tagged 0.3.0-beta.1 is still 0.3.0 for "is there something
        // newer than 0.2.0".
        XCTAssertGreaterThan(SemanticVersion("0.3.0-beta.1")!, SemanticVersion("0.2.0")!)
    }

    func testRejectsThingsThatArentVersions() {
        XCTAssertNil(SemanticVersion("latest"))
        XCTAssertNil(SemanticVersion("1.x.0"))
        XCTAssertNil(SemanticVersion(""))
    }

    func testEqualVersionsAreNotAnUpdate() {
        XCTAssertFalse(SemanticVersion("0.2.0")! < SemanticVersion("0.2.0")!)
    }
}

final class UpdateScheduleTests: XCTestCase {
    @MainActor
    private func settings() -> LedgeSettings {
        let suite = UserDefaults(suiteName: "dev.ledge.tests.updates.\(UUID().uuidString)")!
        return LedgeSettings(defaults: suite)
    }

    @MainActor
    func testAFreshInstallIsDueImmediately() {
        XCTAssertTrue(settings().isUpdateCheckDue())
    }

    @MainActor
    func testCheckingIsNotDueAgainWithinTheDay() {
        let s = settings()
        s.lastUpdateCheck = Date()
        XCTAssertFalse(s.isUpdateCheckDue())
        XCTAssertTrue(s.isUpdateCheckDue(now: Date().addingTimeInterval(86_401)))
    }

    @MainActor
    func testTurningItOffMeansNoRequestEverBecomesDue() {
        let s = settings()
        s.checksForUpdates = false
        XCTAssertFalse(s.isUpdateCheckDue())
        XCTAssertFalse(s.isUpdateCheckDue(now: Date().addingTimeInterval(86_400 * 30)))
    }
}
