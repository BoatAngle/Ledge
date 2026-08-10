import XCTest
@testable import IsletCore

final class DurationTests: XCTestCase {
    func testUnitSuffixes() {
        XCTAssertEqual(IsletDuration.parse("25m"), 1500)
        XCTAssertEqual(IsletDuration.parse("90s"), 90)
        XCTAssertEqual(IsletDuration.parse("2h"), 7200)
        XCTAssertEqual(IsletDuration.parse("1h30m"), 5400)
        XCTAssertEqual(IsletDuration.parse("1h30m15s"), 5415)
    }

    func testTrailingNumberReadsAsMinutes() {
        // "1h30" is what people actually type.
        XCTAssertEqual(IsletDuration.parse("1h30"), 5400)
    }

    func testClockNotation() {
        XCTAssertEqual(IsletDuration.parse("1:30"), 90)
        XCTAssertEqual(IsletDuration.parse("25:00"), 1500)
        XCTAssertEqual(IsletDuration.parse("1:30:00"), 5400)
    }

    func testBareNumberIsSeconds() {
        XCTAssertEqual(IsletDuration.parse("45"), 45)
        XCTAssertEqual(IsletDuration.parse(" 45 "), 45)
    }

    func testRejectsNonsense() {
        // Each of these would otherwise start a zero-second timer that fires
        // instantly, which is worse than an error message.
        XCTAssertNil(IsletDuration.parse("banana"))
        XCTAssertNil(IsletDuration.parse(""))
        XCTAssertNil(IsletDuration.parse("1:ab"))
        XCTAssertNil(IsletDuration.parse("5x"))
        XCTAssertNil(IsletDuration.parse("m"))
        XCTAssertNil(IsletDuration.parse("0s"))
    }

    func testDescribePicksTheNaturalUnit() {
        XCTAssertEqual(IsletDuration.describe(1500), "25 minute timer")
        XCTAssertEqual(IsletDuration.describe(7200), "2 hour timer")
        XCTAssertEqual(IsletDuration.describe(45), "45 second timer")
        XCTAssertEqual(IsletDuration.describe(90), "90 second timer")
    }
}
