import AppKit
import Foundation
import IsletCore

/// A snapshot of whatever is playing.
struct NowPlaying: Equatable, Sendable {
    enum PlayerState: String, Sendable { case playing, paused, stopped }

    var player: MediaPlayer
    var state: PlayerState
    var title: String
    var artist: String
    var album: String
    /// Seconds.
    var duration: Double
    var position: Double
    /// Spotify hands us a URL; Music hands us bytes. Either resolves to art.
    var artworkURL: String?

    /// Identity of the *track*, so we only refetch artwork when it changes.
    var trackKey: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }
}

/// The players we know how to drive.
enum MediaPlayer: String, CaseIterable, Sendable {
    case music
    case spotify

    var bundleIdentifier: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var applicationName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }

    var displayName: String {
        switch self {
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    var tint: IsletColor {
        switch self {
        case .music: return IsletColor(red: 0.98, green: 0.19, blue: 0.35)
        case .spotify: return IsletColor(red: 0.11, green: 0.84, blue: 0.38)
        }
    }
}

/// Now Playing, with transport controls.
///
/// Reads Music and Spotify over AppleScript. That choice is deliberate: the
/// private MediaRemote framework that used to expose system-wide Now Playing
/// was locked behind an entitlement in macOS 15.4, and building on it would
/// mean shipping something that breaks on the next point release. `MediaSource`
/// is a protocol so a MediaRemote adapter can be dropped in later without the
/// rest of the app noticing.
@MainActor
public final class MediaProvider: SystemProvider {
    public let identifier = "system.media"
    public let displayName = "Now Playing"
    public let summary = "What's playing in Music or Spotify, with controls"
    public let isAvailable = true

    private weak var store: ActivityStore?
    private lazy var poller = PollTimer(interval: 1.0) { [weak self] in self?.tick() }
    private var pollTask: Task<Void, Never>?
    private var current: NowPlaying?
    private var artworkPath: String?
    private var artworkTrackKey: String?
    private var pausedSince: Date?
    private var actionObserver: NSObjectProtocol?

    /// How long a paused player lingers before the island lets it go.
    private static let pauseGrace: TimeInterval = 6

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store

        poller.start()
        tick()

        actionObserver = NotificationCenter.default.addObserver(
            forName: .isletActionInvoked,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let id = note.userInfo?["actionID"] as? String else { return }
            MainActor.assumeIsolated { self?.handleAction(id) }
        }
    }

    public func stop() {
        poller.stop()
        pollTask?.cancel()
        pollTask = nil
        if let actionObserver { NotificationCenter.default.removeObserver(actionObserver) }
        actionObserver = nil
        store?.end(id: identifier)
        store = nil
    }

    // MARK: - Polling

    private func tick() {
        guard pollTask == nil else { return } // Skip if the last poll is still out.
        pollTask = Task { @MainActor [weak self] in
            defer { self?.pollTask = nil }
            guard let self else { return }
            let snapshot = await Self.readNowPlaying()
            self.apply(snapshot)
        }
    }

    /// Asks each running player in turn and takes the first one that's playing,
    /// falling back to the first that merely has a track loaded.
    private static func readNowPlaying() async -> NowPlaying? {
        var paused: NowPlaying?
        for player in MediaPlayer.allCases {
            guard await MainActor.run(body: {
                AppleScriptRunner.isRunning(bundleIdentifier: player.bundleIdentifier)
            }) else { continue }

            guard let raw = await AppleScriptRunner.string(script(for: player)) else { continue }
            guard let snapshot = parse(raw, player: player) else { continue }
            if snapshot.state == .playing { return snapshot }
            if paused == nil, snapshot.state == .paused { paused = snapshot }
        }
        return paused
    }

    private static func script(for player: MediaPlayer) -> String {
        let extra = player == .spotify ? "& tab & (artwork url of current track)" : ""
        // Spotify reports duration in milliseconds, Music in seconds; the
        // parser normalises using the player it came from.
        return """
        tell application "\(player.applicationName)"
            set playerState to (player state as text)
            if playerState is "stopped" then return "stopped"
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackDuration to duration of current track
            set trackPosition to player position
            return playerState & tab & trackName & tab & trackArtist & tab & trackAlbum ¬
                & tab & (trackDuration as text) & tab & (trackPosition as text) \(extra)
        end tell
        """
    }

    private static func parse(_ raw: String, player: MediaPlayer) -> NowPlaying? {
        if raw == "stopped" { return nil }
        let fields = raw.components(separatedBy: "\t")
        guard fields.count >= 6 else { return nil }
        guard let state = NowPlaying.PlayerState(rawValue: fields[0].lowercased()) else { return nil }

        let rawDuration = Double(fields[4]) ?? 0
        let duration = player == .spotify ? rawDuration / 1000 : rawDuration

        return NowPlaying(
            player: player,
            state: state,
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            duration: duration,
            position: Double(fields[5]) ?? 0,
            artworkURL: fields.count >= 7 ? fields[6] : nil
        )
    }

    // MARK: - Publishing

    private func apply(_ snapshot: NowPlaying?) {
        guard let store else { return }

        guard let snapshot else {
            current = nil
            pausedSince = nil
            store.end(id: identifier)
            return
        }

        // Let a paused player sit for a moment — skipping between tracks briefly
        // reports paused, and blinking the island off and on would look broken.
        if snapshot.state == .paused {
            if pausedSince == nil { pausedSince = Date() }
            if Date().timeIntervalSince(pausedSince!) > Self.pauseGrace {
                current = snapshot
                store.end(id: identifier)
                return
            }
        } else {
            pausedSince = nil
        }

        if snapshot.trackKey != current?.trackKey {
            fetchArtwork(for: snapshot)
        }
        current = snapshot

        store.present(
            Activity(
                id: identifier,
                source: "system",
                kind: .ongoing,
                priority: .normal,
                content: content(for: snapshot),
                nativeView: .media,
                module: identifier,
                isExpandable: true,
                openURL: nil
            )
        )
    }

    private func content(for snapshot: NowPlaying) -> ActivityContent {
        let icon: ActivityIcon = artworkPath.map { .file($0) }
            ?? .bundleIdentifier(snapshot.player.bundleIdentifier)

        let progress: ActivityProgress? = snapshot.duration > 0
            ? ActivityProgress(
                fraction: min(1, snapshot.position / snapshot.duration),
                label: "\(LiveTimeFormat.short(snapshot.position)) / \(LiveTimeFormat.short(snapshot.duration))"
            )
            : nil

        return ActivityContent(
            title: snapshot.title,
            subtitle: snapshot.artist,
            body: snapshot.album.isEmpty ? nil : snapshot.album,
            icon: icon,
            tint: snapshot.player.tint,
            progress: progress,
            details: [],
            actions: [
                ActivityAction(id: "media.previous", title: "Back", symbol: "backward.fill"),
                ActivityAction(
                    id: "media.playPause",
                    title: snapshot.state == .playing ? "Pause" : "Play",
                    symbol: snapshot.state == .playing ? "pause.fill" : "play.fill"
                ),
                ActivityAction(id: "media.next", title: "Next", symbol: "forward.fill"),
            ]
        )
    }

    // MARK: - Artwork

    private func fetchArtwork(for snapshot: NowPlaying) {
        let key = snapshot.trackKey
        artworkTrackKey = key
        Task { @MainActor [weak self] in
            guard let self else { return }
            let data: Data?
            if let urlString = snapshot.artworkURL, let url = URL(string: urlString) {
                data = try? await URLSession.shared.data(from: url).0
            } else if snapshot.player == .music {
                data = await AppleScriptRunner.data(
                    #"tell application "Music" to return data of artwork 1 of current track"#
                )
            } else {
                data = nil
            }

            // A slow download can land after the user has skipped on.
            guard self.artworkTrackKey == key, let data, !data.isEmpty else { return }
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("islet-artwork-\(abs(key.hashValue)).png").path
            guard (try? data.write(to: URL(fileURLWithPath: path))) != nil else { return }
            self.artworkPath = path
            if let current = self.current, current.trackKey == key {
                self.store?.update(id: self.identifier, content: self.content(for: current))
            }
        }
    }

    // MARK: - Transport

    private func handleAction(_ id: String) {
        guard let player = current?.player else { return }
        let app = player.applicationName
        switch id {
        case "media.playPause":
            AppleScriptRunner.perform(#"tell application "\#(app)" to playpause"#)
        case "media.next":
            AppleScriptRunner.perform(#"tell application "\#(app)" to next track"#)
        case "media.previous":
            AppleScriptRunner.perform(#"tell application "\#(app)" to previous track"#)
        default:
            return
        }
        // Read back promptly so the button reflects reality.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.tick()
        }
    }
}

enum LiveTimeFormat {
    static func short(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
