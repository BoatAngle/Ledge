import XCTest
@testable import LedgeCore
@testable import LedgeModules

final class WeatherCodeTests: XCTestCase {
    func testClearSkiesDifferByTimeOfDay() {
        let clear = WeatherCode.condition(for: 0)
        XCTAssertEqual(clear.summary, "Clear")
        XCTAssertEqual(clear.symbol(isDay: true), "sun.max.fill")
        XCTAssertEqual(clear.symbol(isDay: false), "moon.stars.fill")
        XCTAssertFalse(clear.isPrecipitation)
    }

    func testPrecipitationIsFlagged() {
        // These drive the "rain is starting" alert, so a wrong flag means a
        // missed notification rather than a cosmetic slip.
        for code in [51, 55, 61, 65, 71, 80, 82, 95, 99] {
            XCTAssertTrue(
                WeatherCode.condition(for: code).isPrecipitation,
                "Code \(code) should count as precipitation"
            )
        }
        for code in [0, 1, 2, 3, 45, 48] {
            XCTAssertFalse(
                WeatherCode.condition(for: code).isPrecipitation,
                "Code \(code) should not count as precipitation"
            )
        }
    }

    func testUnknownCodesDegradeInsteadOfCrashing() {
        // Open-Meteo can add codes; an unrecognised one must still render.
        let unknown = WeatherCode.condition(for: 1234)
        XCTAssertFalse(unknown.summary.isEmpty)
        XCTAssertFalse(unknown.symbol(isDay: true).isEmpty)
    }

    func testEveryDocumentedCodeHasASymbol() {
        let documented = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65,
                          66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99]
        for code in documented {
            let condition = WeatherCode.condition(for: code)
            XCTAssertFalse(condition.symbol(isDay: true).isEmpty, "code \(code)")
            XCTAssertFalse(condition.symbol(isDay: false).isEmpty, "code \(code)")
            XCTAssertNotEqual(condition.summary, "Weather", "Code \(code) fell through to the default")
        }
    }
}
