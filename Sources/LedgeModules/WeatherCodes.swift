import Foundation
import LedgeCore

/// WMO weather interpretation codes, which is what Open-Meteo reports.
///
/// Mapped to a description and an SF Symbol rather than left as integers,
/// because "code 73" on the island would help nobody.
public enum WeatherCode {
    public struct Condition: Sendable, Equatable {
        public var summary: String
        /// Symbol for daytime.
        public var daySymbol: String
        /// Symbol for after dark, where one differs.
        public var nightSymbol: String
        public var isPrecipitation: Bool
        public var tint: LedgeColor

        public func symbol(isDay: Bool) -> String { isDay ? daySymbol : nightSymbol }
    }

    public static func condition(for code: Int) -> Condition {
        switch code {
        case 0:
            return Condition(summary: "Clear", daySymbol: "sun.max.fill",
                             nightSymbol: "moon.stars.fill", isPrecipitation: false, tint: .yellow)
        case 1:
            return Condition(summary: "Mainly clear", daySymbol: "sun.max.fill",
                             nightSymbol: "moon.fill", isPrecipitation: false, tint: .yellow)
        case 2:
            return Condition(summary: "Partly cloudy", daySymbol: "cloud.sun.fill",
                             nightSymbol: "cloud.moon.fill", isPrecipitation: false, tint: .cyan)
        case 3:
            return Condition(summary: "Overcast", daySymbol: "cloud.fill",
                             nightSymbol: "cloud.fill", isPrecipitation: false, tint: .gray)
        case 45, 48:
            return Condition(summary: "Fog", daySymbol: "cloud.fog.fill",
                             nightSymbol: "cloud.fog.fill", isPrecipitation: false, tint: .gray)
        case 51, 53, 55:
            return Condition(summary: "Drizzle", daySymbol: "cloud.drizzle.fill",
                             nightSymbol: "cloud.drizzle.fill", isPrecipitation: true, tint: .cyan)
        case 56, 57:
            return Condition(summary: "Freezing drizzle", daySymbol: "cloud.sleet.fill",
                             nightSymbol: "cloud.sleet.fill", isPrecipitation: true, tint: .cyan)
        case 61, 63, 65:
            return Condition(summary: "Rain", daySymbol: "cloud.rain.fill",
                             nightSymbol: "cloud.rain.fill", isPrecipitation: true, tint: .blue)
        case 66, 67:
            return Condition(summary: "Freezing rain", daySymbol: "cloud.sleet.fill",
                             nightSymbol: "cloud.sleet.fill", isPrecipitation: true, tint: .blue)
        case 71, 73, 75, 77:
            return Condition(summary: "Snow", daySymbol: "cloud.snow.fill",
                             nightSymbol: "cloud.snow.fill", isPrecipitation: true, tint: .cyan)
        case 80, 81, 82:
            return Condition(summary: "Rain showers", daySymbol: "cloud.sun.rain.fill",
                             nightSymbol: "cloud.moon.rain.fill", isPrecipitation: true, tint: .blue)
        case 85, 86:
            return Condition(summary: "Snow showers", daySymbol: "cloud.snow.fill",
                             nightSymbol: "cloud.snow.fill", isPrecipitation: true, tint: .cyan)
        case 95:
            return Condition(summary: "Thunderstorm", daySymbol: "cloud.bolt.rain.fill",
                             nightSymbol: "cloud.bolt.rain.fill", isPrecipitation: true, tint: .purple)
        case 96, 99:
            return Condition(summary: "Thunderstorm with hail", daySymbol: "cloud.bolt.rain.fill",
                             nightSymbol: "cloud.bolt.rain.fill", isPrecipitation: true, tint: .purple)
        default:
            // Open-Meteo may add codes; an unknown one shouldn't blank the module.
            return Condition(summary: "Weather", daySymbol: "cloud.fill",
                             nightSymbol: "cloud.fill", isPrecipitation: false, tint: .gray)
        }
    }
}
