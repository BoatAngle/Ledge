import CoreLocation
import Foundation
import IsletCore

/// Current conditions on the island.
///
/// Unlike every other module, weather isn't an *event* — it's ambient state, and
/// ambient state on a permanent readout would mean the island is never idle.
/// So the default is `.onDemand`: it's fetched and cached, but only shown when
/// asked. `.ambient` is one toggle away for anyone who wants it there always.
@MainActor
public final class WeatherProvider: SystemProvider {
    public let identifier = "system.weather"
    public let displayName = "Weather"
    public let summary = "Current conditions, from Open-Meteo"
    public let isAvailable = true

    private weak var store: ActivityStore?
    private let settings: IsletSettings
    private let resolver = LocationResolver()

    private var snapshot: WeatherSnapshot?
    private var coordinate: CLLocationCoordinate2D?
    private var placeName: String?
    private var lastError: String?
    private var isFetching = false
    private var wasPrecipitating = false
    private var actionObserver: NSObjectProtocol?

    /// Fifteen minutes. Weather does not change faster than that, and Open-Meteo
    /// is a free service — hammering it would be rude.
    private lazy var poller = PollTimer(interval: 900) { [weak self] in
        self?.refresh()
    }

    public init(settings: IsletSettings = .shared) {
        self.settings = settings
    }

    public func start(store: ActivityStore) {
        self.store = store
        guard settings.weatherMode != .off else { return }

        // Only fetch ahead of time when something will actually be shown.
        //
        // In `.onDemand` the first fetch waits until you ask, so a fresh
        // install doesn't raise a location prompt for a feature you haven't
        // used yet. Alerts need the poll regardless — they're the whole point.
        guard settings.weatherMode == .ambient || settings.weatherAlerts else { return }

        // Deferred: resolving location raises the authorization prompt, which
        // must not happen while the app is still launching.
        Task { @MainActor [weak self] in
            self?.refresh()
        }
        poller.start()

        actionObserver = NotificationCenter.default.addObserver(
            forName: .isletActionInvoked,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard note.userInfo?["actionID"] as? String == "weather.refresh" else { return }
            MainActor.assumeIsolated { self?.refresh(force: true) }
        }
    }

    public func stop() {
        poller.stop()
        if let actionObserver { NotificationCenter.default.removeObserver(actionObserver) }
        actionObserver = nil
        store?.end(id: identifier)
        store = nil
    }

    public func suspend() { poller.suspend() }
    public func resume() {
        poller.resume()
        refresh()
    }

    // MARK: - Public

    public var latest: WeatherSnapshot? { snapshot }

    /// Show the current conditions for a few seconds. Fetches first if the
    /// cached reading is stale.
    public func showNow() {
        guard settings.weatherMode != .off else { return }
        if let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < 1800 {
            flash(snapshot)
        } else {
            Task { @MainActor [weak self] in
                await self?.fetch()
                guard let self else { return }
                if let snapshot = self.snapshot {
                    self.flash(snapshot)
                } else {
                    self.flashError()
                }
            }
        }
    }

    // MARK: - Fetching

    private func refresh(force: Bool = false) {
        guard settings.weatherMode != .off else {
            store?.end(id: identifier)
            return
        }
        Task { @MainActor [weak self] in
            await self?.fetch(force: force)
            self?.publishAmbientIfNeeded()
        }
    }

    private func fetch(force: Bool = false) async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        guard let coordinate = await resolveCoordinate(force: force) else {
            lastError = WeatherService.ServiceError.noLocation.description
            return
        }

        do {
            let reading = try await WeatherService.fetch(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                unit: settings.temperatureUnit,
                placeName: placeName
            )
            lastError = nil
            let wasWet = wasPrecipitating
            wasPrecipitating = reading.condition.isPrecipitation
            snapshot = reading

            // Rain starting is the one weather event worth interrupting for.
            if settings.weatherAlerts, !wasWet, reading.condition.isPrecipitation {
                alert(reading)
            }
        } catch {
            lastError = (error as? WeatherService.ServiceError)?.description
                ?? error.localizedDescription
        }
    }

    private func resolveCoordinate(force: Bool) async -> CLLocationCoordinate2D? {
        if settings.weatherLocationMode == .manual {
            let manual = CLLocationCoordinate2D(
                latitude: settings.manualLatitude,
                longitude: settings.manualLongitude
            )
            guard CLLocationCoordinate2DIsValid(manual),
                  !(manual.latitude == 0 && manual.longitude == 0)
            else { return nil }
            placeName = settings.manualPlaceName.isEmpty ? nil : settings.manualPlaceName
            coordinate = manual
            return manual
        }

        // Location rarely changes enough to matter between refreshes, and each
        // lookup costs a Core Location round trip.
        if let coordinate, !force { return coordinate }

        guard let location = await resolver.currentLocation() else { return coordinate }
        coordinate = location.coordinate
        placeName = await LocationResolver.placeName(for: location)
        return location.coordinate
    }

    // MARK: - Presenting

    private func publishAmbientIfNeeded() {
        guard let store else { return }
        guard settings.weatherMode == .ambient, let snapshot else {
            store.end(id: identifier)
            return
        }
        store.present(
            Activity(
                id: identifier,
                source: "system",
                kind: .ongoing,
                // Lowest of the low: anything actually happening outranks it, so
                // weather only surfaces when the island would be empty.
                priority: .background,
                content: content(for: snapshot),
                nativeView: .weather,
                module: identifier,
                isExpandable: true
            )
        )
    }

    private func flash(_ snapshot: WeatherSnapshot) {
        store?.flash(
            id: "weather.now",
            nativeView: .weather,
            module: identifier,
            content: content(for: snapshot),
            priority: .normal,
            dwell: 4
        )
    }

    private func flashError() {
        store?.flash(
            id: "weather.now",
            nativeView: .weather,
            module: identifier,
            content: ActivityContent(
                title: "Weather unavailable",
                subtitle: lastError,
                icon: .symbol("exclamationmark.triangle.fill"),
                tint: .orange
            ),
            priority: .normal,
            dwell: 4
        )
    }

    private func alert(_ snapshot: WeatherSnapshot) {
        store?.flash(
            id: "weather.alert",
            nativeView: .weather,
            module: identifier,
            content: ActivityContent(
                title: "\(snapshot.condition.summary) starting",
                subtitle: placeName,
                icon: .symbol(snapshot.condition.symbol(isDay: snapshot.isDay)),
                tint: snapshot.condition.tint
            ),
            priority: .high,
            dwell: 5
        )
    }

    private func content(for snapshot: WeatherSnapshot) -> ActivityContent {
        let unit = settings.temperatureUnit.suffix
        let condition = snapshot.condition

        var details = [
            ActivityDetail(
                label: "Feels like",
                value: "\(Self.round(snapshot.apparentTemperature))\(unit)"
            ),
            ActivityDetail(
                label: "High / Low",
                value: "\(Self.round(snapshot.high))\(unit) / \(Self.round(snapshot.low))\(unit)"
            ),
        ]
        if snapshot.precipitation > 0 {
            details.append(
                ActivityDetail(label: "Precipitation", value: String(format: "%.1f mm", snapshot.precipitation))
            )
        }

        return ActivityContent(
            title: condition.summary,
            subtitle: snapshot.placeName ?? placeName,
            icon: .symbol(condition.symbol(isDay: snapshot.isDay)),
            trailingText: "\(Self.round(snapshot.temperature))\(unit)",
            tint: condition.tint,
            details: details,
            actions: [
                ActivityAction(id: "weather.refresh", title: "Refresh", symbol: "arrow.clockwise")
            ]
        )
    }

    private static func round(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
