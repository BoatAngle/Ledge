import AppKit
import Foundation
import IsletCore

/// In-progress downloads.
///
/// Watches the Downloads folder for the partial files every browser leaves
/// behind, rather than reading any one browser's database. Safari's download
/// list lives inside its container and needs Full Disk Access to read; the
/// partial files need only the Downloads folder, and the same code covers
/// Chrome, Firefox, Arc, Orion, curl, and anything else that writes there.
@MainActor
public final class DownloadsProvider: SystemProvider {
    public let identifier = "system.downloads"
    public let displayName = "Downloads"
    public let summary = "Downloads in progress, from any browser"
    /// Always offered.
    ///
    /// Deliberately does *not* stat the folder: reading `~/Downloads` is
    /// TCC-gated, and probing it to answer "is this module available" would
    /// raise a consent prompt at the worst possible moment. Access is attempted
    /// once the app is up, and declining simply means no downloads ever appear.
    public let isAvailable = true

    /// Suffixes browsers use while a file is still arriving.
    private static let partialSuffixes = [
        ".crdownload",  // Chrome, Edge, Brave, Arc
        ".part",        // Firefox
        ".download",    // Safari (a bundle, not a file)
        ".opdownload",  // Opera
        ".partial",
        ".aria2",
    ]

    private static var downloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    private struct InFlight {
        var url: URL
        var displayName: String
        var bytes: Int64
        var startedAt: Date
    }

    private weak var store: ActivityStore?
    private var watcher: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var inFlight: [String: InFlight] = [:]
    private var actionObserver: NSObjectProtocol?
    private var lastCompletedURL: URL?
    /// Only runs while something is downloading — see `syncPoller()`.
    private lazy var poller = PollTimer(interval: 0.6) { [weak self] in self?.scan() }

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store
        // First filesystem touch happens off the main thread, after launch.
        //
        // Opening a TCC-protected folder blocks the calling thread until the
        // user answers the consent dialog. On the main thread that freezes the
        // island, the menu bar item, and the API for as long as the prompt sits
        // there — so the blocking call goes to a background queue and only the
        // result comes back.
        Task { @MainActor [weak self] in
            guard let self, self.store != nil else { return }
            let descriptor = await Self.openDownloadsFolder()
            guard self.store != nil, descriptor >= 0 else { return }
            self.startWatching(descriptor: descriptor)
            self.scan()
        }

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
        watcher?.cancel()
        watcher = nil
        if descriptor >= 0 { close(descriptor) }
        descriptor = -1
        if let actionObserver { NotificationCenter.default.removeObserver(actionObserver) }
        actionObserver = nil
        store?.end(id: identifier)
        store = nil
    }

    public func suspend() { poller.suspend() }
    public func resume() {
        poller.resume()
        scan()
    }

    // MARK: - Watching

    /// The blocking part: returns -1 if the user declines.
    private static func openDownloadsFolder() async -> CInt {
        let path = downloadsURL.path
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: open(path, O_EVTONLY))
            }
        }
    }

    private func startWatching(descriptor fd: CInt) {
        descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.resume()
        watcher = source
    }

    // MARK: - Scanning

    private func scan() {
        guard let store else { return }
        let found = currentPartials()

        // Anything that vanished since the last pass has finished (or been
        // cancelled) — either way it's no longer in flight.
        let finished = inFlight.keys.filter { found[$0] == nil }
        for key in finished {
            guard let entry = inFlight.removeValue(forKey: key) else { continue }
            announceCompletion(entry)
        }

        for (key, entry) in found {
            if var existing = inFlight[key] {
                existing.bytes = entry.bytes
                inFlight[key] = existing
            } else {
                inFlight[key] = entry
            }
        }

        syncPoller()

        guard !inFlight.isEmpty else {
            store.end(id: identifier)
            return
        }
        publish()
    }

    /// Polling only earns its keep while bytes are moving; the directory
    /// watcher handles the idle case for free.
    private func syncPoller() {
        if inFlight.isEmpty {
            poller.stop()
        } else {
            poller.start()
        }
    }

    private func currentPartials() -> [String: InFlight] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: Self.downloadsURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var result: [String: InFlight] = [:]
        for url in entries {
            let name = url.lastPathComponent
            guard let suffix = Self.partialSuffixes.first(where: { name.hasSuffix($0) }) else {
                continue
            }
            let display = String(name.dropLast(suffix.count))
            result[url.path] = InFlight(
                url: url,
                displayName: display.isEmpty ? name : display,
                bytes: Self.size(of: url),
                startedAt: inFlight[url.path]?.startedAt ?? Date()
            )
        }
        return result
    }

    /// Byte count, walking into Safari's `.download` bundles.
    private static func size(of url: URL) -> Int64 {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }

        if !isDirectory.boolValue {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Presenting

    private func publish() {
        guard let store else { return }
        let entries = inFlight.values.sorted { $0.startedAt < $1.startedAt }
        let total = entries.reduce(Int64(0)) { $0 + $1.bytes }

        let title: String
        let subtitle: String
        if entries.count == 1, let only = entries.first {
            title = only.displayName
            subtitle = "Downloading — \(Self.byteFormatter.string(fromByteCount: only.bytes))"
        } else {
            title = "\(entries.count) downloads"
            subtitle = "\(Self.byteFormatter.string(fromByteCount: total)) so far"
        }

        store.present(
            Activity(
                id: identifier,
                source: "system",
                kind: .ongoing,
                priority: .normal,
                content: ActivityContent(
                    title: title,
                    subtitle: subtitle,
                    icon: .symbol("arrow.down.circle.fill"),
                    tint: .teal,
                    // Indeterminate on purpose: a partial file tells us how many
                    // bytes have landed but never how many are coming, and a
                    // progress bar built on a guess is worse than none.
                    progress: ActivityProgress(label: entries.count == 1 ? nil : "\(entries.count) files"),
                    details: {
                        var rows = entries.prefix(4).map {
                            ActivityDetail(
                                label: $0.displayName,
                                value: Self.byteFormatter.string(fromByteCount: $0.bytes)
                            )
                        }
                        // Same elision convention as the shelf's "+ N more".
                        if entries.count > 4 {
                            rows.append(ActivityDetail(label: "+ \(entries.count - 4) more", value: ""))
                        }
                        return rows
                    }(),
                    actions: [
                        ActivityAction(
                            id: "downloads.reveal",
                            title: "Show in Finder",
                            symbol: "folder"
                        )
                    ]
                ),
                nativeView: .download,
                module: identifier,
                isExpandable: true
            )
        )
    }

    private func announceCompletion(_ entry: InFlight) {
        guard let store else { return }
        let finished = Self.downloadsURL.appendingPathComponent(entry.displayName)
        let exists = FileManager.default.fileExists(atPath: finished.path)
        // No finished file means the download was cancelled, not completed —
        // announcing "Downloaded" there would be a lie.
        guard exists else { return }
        lastCompletedURL = finished

        store.flash(
            id: "downloads.finished",
            nativeView: .download,
            module: identifier,
            content: ActivityContent(
                title: entry.displayName,
                subtitle: "Downloaded — \(Self.byteFormatter.string(fromByteCount: Self.size(of: finished)))",
                icon: .symbol("checkmark.circle.fill"),
                tint: .green,
                actions: [
                    ActivityAction(id: "downloads.revealLast", title: "Show in Finder", symbol: "folder")
                ]
            ),
            priority: .normal,
            dwell: 4
        )
    }

    private func handleAction(_ id: String) {
        switch id {
        case "downloads.reveal":
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Self.downloadsURL.path)
        case "downloads.revealLast":
            if let lastCompletedURL {
                NSWorkspace.shared.activateFileViewerSelecting([lastCompletedURL])
            }
        default:
            return
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}
