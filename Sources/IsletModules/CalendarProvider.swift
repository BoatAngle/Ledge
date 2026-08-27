import AppKit
import EventKit
import Foundation
import IsletCore

/// The next meeting, surfaced as it approaches.
///
/// Not a calendar viewer — the island's job is the twenty minutes before a
/// meeting, when "am I late" and "where's the link" are the only two questions
/// that matter. Everything else belongs in Calendar.app.
@MainActor
public final class CalendarProvider: SystemProvider {
    public let identifier = "system.calendar"
    public let displayName = "Calendar & Events"
    public let summary = "Your next meeting, with a button to join it"

    /// Hidden only when the user has actively said no.
    public var isAvailable: Bool {
        EKEventStore.authorizationStatus(for: .event) != .denied
            && EKEventStore.authorizationStatus(for: .event) != .restricted
    }

    /// How far ahead of a meeting the island starts caring.
    public var leadTime: TimeInterval = 15 * 60
    /// How long an in-progress meeting stays up after it starts.
    public var lingerAfterStart: TimeInterval = 5 * 60

    private weak var store: ActivityStore?
    private let eventStore = EKEventStore()
    private var isAuthorized = false
    private var shownEventID: String?
    private var actionObserver: NSObjectProtocol?
    private var joinURL: URL?
    /// 20 seconds is plenty — the countdown itself animates locally, so this
    /// only decides when we notice a *different* meeting is now next.
    private lazy var poller = PollTimer(interval: 20) { [weak self] in self?.refresh() }

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isAuthorized = await Self.requestAccess(self.eventStore)
            guard self.isAuthorized else { return }
            self.poller.start()
            self.refresh()
        }

        actionObserver = NotificationCenter.default.addObserver(
            forName: .isletActionInvoked,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard note.userInfo?["actionID"] as? String == "calendar.join" else { return }
            MainActor.assumeIsolated { self?.join() }
        }

        // EventKit tells us when anything changes, which catches a meeting
        // moved five minutes before it starts.
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    public func stop() {
        poller.stop()
        if let actionObserver { NotificationCenter.default.removeObserver(actionObserver) }
        actionObserver = nil
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: eventStore)
        store?.end(id: identifier)
        store = nil
    }

    public func suspend() { poller.suspend() }
    public func resume() {
        poller.resume()
        refresh()
    }

    private static func requestAccess(_ eventStore: EKEventStore) async -> Bool {
        await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Finding the next meeting

    private func refresh() {
        guard let store, isAuthorized else { return }

        guard let event = nextEvent() else {
            if shownEventID != nil {
                shownEventID = nil
                joinURL = nil
                store.end(id: identifier)
            }
            return
        }

        let startsIn = event.startDate.timeIntervalSinceNow
        let hasStarted = startsIn <= 0
        joinURL = Self.meetingLink(in: event)

        var actions: [ActivityAction] = []
        if joinURL != nil {
            actions.append(
                ActivityAction(id: "calendar.join", title: "Join", symbol: "video.fill")
            )
        }

        var details: [ActivityDetail] = []
        details.append(
            ActivityDetail(label: "Starts", value: Self.timeFormatter.string(from: event.startDate))
        )
        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty, !location.contains("://") {
            details.append(ActivityDetail(label: "Where", value: location))
        }

        store.present(
            Activity(
                id: identifier,
                source: "system",
                kind: .ongoing,
                // Rises above ambient activities as the meeting gets close, so
                // music doesn't hide a meeting starting in ninety seconds.
                priority: startsIn <= 120 ? .high : .normal,
                content: ActivityContent(
                    title: event.title ?? "Event",
                    // The calendar name carries information; "Upcoming" next
                    // to a countdown carried none.
                    subtitle: hasStarted ? "Happening now" : (event.calendar?.title ?? "Upcoming"),
                    icon: .symbol(joinURL != nil ? "video.fill" : "calendar"),
                    tint: hasStarted ? .red : .blue,
                    details: details,
                    actions: actions,
                    countdownTarget: hasStarted ? nil : event.startDate
                ),
                nativeView: .calendar,
                module: identifier,
                isExpandable: true
            )
        )
        shownEventID = event.eventIdentifier
    }

    /// The soonest event worth showing: starting within `leadTime`, or started
    /// less than `lingerAfterStart` ago.
    private func nextEvent() -> EKEvent? {
        let now = Date()
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-lingerAfterStart),
            end: now.addingTimeInterval(leadTime),
            calendars: nil
        )

        return eventStore.events(matching: predicate)
            .filter { event in
                // All-day events aren't "starting soon" in any useful sense.
                guard !event.isAllDay else { return false }
                guard event.status != .canceled else { return false }
                // Declined invitations shouldn't nag.
                if let attendees = event.attendees,
                   attendees.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) {
                    return false
                }
                return event.endDate > now
            }
            .min { $0.startDate < $1.startDate }
    }

    private func join() {
        guard let joinURL else { return }
        NSWorkspace.shared.open(joinURL)
    }

    // MARK: - Meeting links

    private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "bluejeans.com", "gotomeeting.com",
        "chime.aws", "around.co", "meet.jit.si", "discord.gg", "slack.com",
    ]

    /// Digs a video-call link out of wherever the invite happened to put it.
    ///
    /// Every calendar system stashes it somewhere different — the URL field,
    /// the location, or buried in the notes — so all three get searched.
    static func meetingLink(in event: EKEvent) -> URL? {
        if let url = event.url, isMeetingLink(url) { return url }

        for text in [event.location, event.notes].compactMap({ $0 }) {
            if let url = firstMeetingURL(in: text) { return url }
        }
        // Fall back to any URL in the notes — better than nothing when the
        // host isn't one we recognise.
        if let notes = event.notes, let any = firstURL(in: notes) { return any }
        return event.url
    }

    private static func isMeetingLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static func firstMeetingURL(in text: String) -> URL? {
        urls(in: text).first(where: isMeetingLink)
    }

    private static func firstURL(in text: String) -> URL? {
        urls(in: text).first
    }

    private static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
