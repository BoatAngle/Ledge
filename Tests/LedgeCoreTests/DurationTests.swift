import XCTest
@testable import LedgeCore

final class DurationTests: XCTestCase {
    func testUnitSuffixes() {
        XCTAssertEqual(LedgeDuration.parse("25m"), 1500)
        XCTAssertEqual(LedgeDuration.parse("90s"), 90)
        XCTAssertEqual(LedgeDuration.parse("2h"), 7200)
        XCTAssertEqual(LedgeDuration.parse("1h30m"), 5400)
        XCTAssertEqual(LedgeDuration.parse("1h30m15s"), 5415)
    }

    func testTrailingNumberReadsAsMinutes() {
        // "1h30" is what people actually type.
        XCTAssertEqual(LedgeDuration.parse("1h30"), 5400)
    }

    func testClockNotation() {
        XCTAssertEqual(LedgeDuration.parse("1:30"), 90)
        XCTAssertEqual(LedgeDuration.parse("25:00"), 1500)
        XCTAssertEqual(LedgeDuration.parse("1:30:00"), 5400)
    }

    func testBareNumberIsSeconds() {
        XCTAssertEqual(LedgeDuration.parse("45"), 45)
        XCTAssertEqual(LedgeDuration.parse(" 45 "), 45)
    }

    func testRejectsNonsense() {
        // Each of these would otherwise start a zero-second timer that fires
        // instantly, which is worse than an error message.
        XCTAssertNil(LedgeDuration.parse("banana"))
        XCTAssertNil(LedgeDuration.parse(""))
        XCTAssertNil(LedgeDuration.parse("1:ab"))
        XCTAssertNil(LedgeDuration.parse("5x"))
        XCTAssertNil(LedgeDuration.parse("m"))
        XCTAssertNil(LedgeDuration.parse("0s"))
    }

    func testDescribePicksTheNaturalUnit() {
        XCTAssertEqual(LedgeDuration.describe(1500), "25 minutes")
        XCTAssertEqual(LedgeDuration.describe(7200), "2 hours")
        XCTAssertEqual(LedgeDuration.describe(45), "45 seconds")
        XCTAssertEqual(LedgeDuration.describe(90), "1 minute 30 seconds")
        XCTAssertEqual(LedgeDuration.describe(5400), "1 hour 30 minutes")
    }
}
