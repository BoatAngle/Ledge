import CoreLocation
import Foundation
import LedgeCore

/// A point-in-time reading.
public struct WeatherSnapshot: Sendable, Equatable {
    public var temperature: Double
    public var apparentTemperature: Double
    public var code: Int
    public var isDay: Bool
    public var precipitation: Double
    public var high: Double
    public var low: Double
    public var placeName: String?
    public var fetchedAt: Date

    public var condition: WeatherCode.Condition { WeatherCode.condition(for: code) }
}

/// Fetches conditions from Open-Meteo.
///
/// Chosen because it needs no API key and no account — the alternative,
/// WeatherKit, requires a paid Apple Developer membership and an entitlement,
/// which would make an MIT-licensed app impossible for anyone else to build
/// and run.
public enum WeatherService {
    public enum ServiceError: Error, CustomStringConvertible {
        case noLocation
        case network(String)
        case decoding

        public var description: String {
            switch self {
            case .noLocation:
                return "No location available. Allow location access, or set one in Settings."
            case .network(let detail):
                return "Couldn't reach the weather service: \(detail)"
            case .decoding:
                return "The weather service returned something unexpected."
            }
        }
    }

    public static func fetch(
        latitude: Double,
        longitude: Double,
        unit: TemperatureUnit,
        placeName: String?
    ) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            // Two decimal places: about a kilometre.
            //
            // Four was ~11 metres, which is a house. Nothing about a forecast
            // changes at that resolution, so the extra precision was leaving
            // the machine for no reason at all — and the cheapest privacy win
            // available is not sending what you do not need.
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,weather_code,is_day,precipitation"
            ),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(
                name: "temperature_unit",
                value: unit == .fahrenheit ? "fahrenheit" : "celsius"
            ),
            URLQueryItem(
                name: "precipitation_unit",
                value: unit == .fahrenheit ? "inch" : "mm"
            ),
        ]
        guard let url = components.url else { throw ServiceError.decoding }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        do {
            let (payload, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ServiceError.network("HTTP \(http.statusCode)")
            }
            data = payload
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError.network(error.localizedDescription)
        }

        guard let decoded = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) else {
            throw ServiceError.decoding
        }

        return WeatherSnapshot(
            temperature: decoded.current.temperature_2m,
            apparentTemperature: decoded.current.apparent_temperature,
            code: decoded.current.weather_code,
            isDay: decoded.current.is_day == 1,
            precipitation: decoded.current.precipitation,
            high: decoded.daily.temperature_2m_max.first ?? decoded.current.temperature_2m,
            low: decoded.daily.temperature_2m_min.first ?? decoded.current.temperature_2m,
            // A caller-supplied name (the user typed one into Settings) wins;
            // otherwise fall back to the zone Open-Meteo just resolved.
            placeName: placeName ?? Self.placeName(fromTimezone: decoded.timezone),
            fetchedAt: Date()
        )
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var apparent_temperature: Double
            var weather_code: Int
            var is_day: Int
            var precipitation: Double
        }
        struct Daily: Decodable {
            var temperature_2m_max: [Double]
            var temperature_2m_min: [Double]
        }
        var current: Current
        var daily: Daily
        /// Present because the request sends `timezone=auto`. This is where
        /// the place name comes from now — same reply, same service.
        var timezone: String?
    }

    /// "America/Los_Angeles" -> "Los Angeles".
    ///
    /// Coarse by construction: it names a metropolitan zone, not a
    /// neighbourhood, which is the right resolution for a subtitle and a
    /// happy accident for privacy. Returns nil for the zones that carry no
    /// place — "UTC", "GMT", and the "Etc/..." family.
    static func placeName(fromTimezone zone: String?) -> String? {
        guard let zone, !zone.isEmpty else { return nil }
        guard !zone.hasPrefix("Etc/") else { return nil }
        let last = zone.split(separator: "/").last.map(String.init) ?? zone
        guard !["UTC", "GMT", "UCT", "Universal", "Zulu"].contains(last) else { return nil }
        return last.replacingOccurrences(of: "_", with: " ")
    }
}

/// One-shot location lookup.
///
/// `CLLocationManager` is delegate-based and calls back on the main queue; this
/// wraps it in a single `async` call with a timeout, so a user who never answers
/// the authorization prompt can't leave the weather module waiting forever.
final class LocationResolver: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private let lock = NSLock()

    func currentLocation(timeout: TimeInterval = 15) async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { await self.request() }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            // Release any continuation the timeout raced past, or it leaks.
            self.finish(nil)
            return result
        }
    }

    private func request() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            manager.delegate = self
            // Kilometre accuracy is ample for weather and avoids waking the GPS.
            manager.desiredAccuracy = kCLLocationAccuracyKilometer

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(nil)
            default:
                manager.requestLocation()
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    // Reverse geocoding deliberately removed.
    //
    // There used to be a `placeName(for:)` here that sent the coordinate to
    // `CLGeocoder` — that is, to Apple — purely to put a city name in the
    // panel's subtitle. Three places in this project promise that the
    // coordinate goes to "Open-Meteo and nowhere else": the Location usage
    // string in Info.plist, the Weather pane's footer, and the README. Two
    // recipients is not nowhere else.
    //
    // The right fix was to make the code match the promise rather than soften
    // the promise, and it cost nothing: the forecast request already sends
    // `timezone=auto`, and Open-Meteo answers with the resolved zone —
    // "America/Los_Angeles" — whose last component is a serviceable place name
    // once the underscores come out. The label now comes from the same reply
    // as the temperature, from the one service the disclosure names.
}
