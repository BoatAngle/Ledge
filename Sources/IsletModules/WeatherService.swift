import CoreLocation
import Foundation
import IsletCore

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
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
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
            placeName: placeName,
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

    /// Best-effort place name for the expanded panel.
    static func placeName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks?.first else { return nil }
        return placemark.locality ?? placemark.administrativeArea ?? placemark.country
    }
}
