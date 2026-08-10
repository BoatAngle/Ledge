import AppIntents
import Foundation
import IsletCore

/// Shortcuts actions for the island.
///
/// These deliberately go through `IsletClient` — the same socket the CLI uses —
/// rather than reaching for the store directly. One code path for "something
/// outside the app wants to post an activity" means the API can't drift between
/// its two front doors.

struct ShowActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Activity in Notch"
    static let description = IntentDescription(
        "Posts a live activity to the notch. Reuse the same identifier to update it in place.",
        categoryName: "Island"
    )

    @Parameter(title: "Title")
    var activityTitle: String

    @Parameter(title: "Subtitle")
    var subtitle: String?

    @Parameter(title: "SF Symbol", default: "sparkles")
    var symbol: String?

    @Parameter(title: "Tint", default: "blue")
    var tint: String?

    @Parameter(title: "Progress", description: "0 to 1. Leave empty for no progress bar.")
    var progress: Double?

    @Parameter(title: "Identifier", description: "Reuse to update an existing activity.")
    var identifier: String?

    @Parameter(title: "Dismiss After", description: "Seconds. Leave empty to keep it until ended.")
    var dwell: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$activityTitle) in the notch") {
            \.$subtitle
            \.$symbol
            \.$tint
            \.$progress
            \.$identifier
            \.$dwell
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var content = ActivityContent(
            title: activityTitle,
            subtitle: subtitle,
            icon: .symbol(symbol ?? "sparkles"),
            tint: tint.flatMap(IsletColor.init(parsing:)) ?? .accent
        )
        if let progress {
            content.progress = ActivityProgress(fraction: progress)
        }

        let activity = Activity(
            id: identifier ?? UUID().uuidString,
            source: "shortcuts",
            kind: dwell == nil ? .ongoing : .transient,
            content: content,
            expiresAt: dwell.map { Date().addingTimeInterval($0) }
        )

        let response = try send(IsletRequest(command: .present, activity: activity))
        return .result(value: response.id ?? activity.id)
    }
}

struct EndActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Notch Activity"
    static let description = IntentDescription(
        "Removes one activity from the notch by its identifier.",
        categoryName: "Island"
    )

    @Parameter(title: "Identifier")
    var identifier: String

    static var parameterSummary: some ParameterSummary {
        Summary("Remove \(\.$identifier) from the notch")
    }

    func perform() async throws -> some IntentResult {
        _ = try send(IsletRequest(command: .end, id: identifier))
        return .result()
    }
}

struct ClearIslandIntent: AppIntent {
    static let title: LocalizedStringResource = "Clear the Notch"
    static let description = IntentDescription(
        "Removes every activity currently showing in the notch.",
        categoryName: "Island"
    )

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let response = try send(IsletRequest(command: .endAll))
        return .result(value: response.count ?? 0)
    }
}

/// Shared transport plus a readable failure when the app isn't running.
private func send(_ request: IsletRequest) throws -> IsletResponse {
    do {
        return try IsletClient().send(request)
    } catch let error as IsletClient.ClientError {
        throw IsletIntentError.unavailable(error.description)
    }
}

enum IsletIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable(let detail): return "\(detail)"
        }
    }
}

/// Phrases Siri and Spotlight will accept without the user building a shortcut.
struct IsletShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClearIslandIntent(),
            phrases: ["Clear the notch in \(.applicationName)"],
            shortTitle: "Clear the Notch",
            systemImageName: "xmark.circle"
        )
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: ["Start a timer in \(.applicationName)"],
            shortTitle: "Start a Timer",
            systemImageName: "timer"
        )
    }
}

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Notch Timer"
    static let description = IntentDescription(
        "Starts a countdown in the notch that chimes when it finishes.",
        categoryName: "Island"
    )

    @Parameter(title: "Duration", description: "Minutes.", default: 25)
    var minutes: Double

    @Parameter(title: "Label")
    var label: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute timer") {
            \.$label
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard minutes > 0 else {
            throw IsletIntentError.unavailable("A timer needs a duration greater than zero.")
        }
        let response = try send(
            IsletRequest(
                command: .startTimer,
                content: label.map { ActivityContent(title: $0) },
                duration: minutes * 60
            )
        )
        return .result(value: response.id ?? "")
    }
}
