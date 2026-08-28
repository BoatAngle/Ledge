import Darwin
import Foundation
import LedgeCore
import LedgeModules
import LedgeUI

/// Listens on the Unix socket and applies incoming requests to the store.
///
/// One request per connection, newline-framed JSON. That keeps the CLI a single
/// blocking round trip and means a script that dies mid-run can never leave a
/// half-open connection holding state.
@MainActor
final class ActivityServer {
    enum ServerError: Error, CustomStringConvertible {
        case bindFailed(String)

        var description: String {
            switch self {
            case .bindFailed(let detail): return "Couldn't open the Ledge socket: \(detail)"
            }
        }
    }

    private let store: ActivityStore
    /// Timers need an owner with a run loop, so `.startTimer` is delegated to
    /// the provider rather than synthesised from an activity here.
    weak var timers: TimerProvider?
    weak var shelf: DropShelf?
    weak var weather: WeatherProvider?
    /// Opens the settings window. Set by the app delegate.
    /// Opens the settings window at a named tab.
    var openSettings: ((_ tab: String?, _ customizing: String?) -> Void)?
    private var listenDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    /// Identity of the socket file we created, so shutdown can tell ours apart
    /// from a successor's.
    private var boundInode: (device: dev_t, inode: ino_t)?
    private let ioQueue = DispatchQueue(label: "com.ledge.server.io", qos: .userInitiated)

    init(store: ActivityStore) {
        self.store = store
    }

    // MARK: - Lifecycle

    func start() throws {
        try? LedgeSocket.ensureDirectory()
        let path = LedgeSocket.path

        // A socket file left behind by a crash would make bind fail; the path
        // is ours by construction, so reclaiming it is safe.
        unlink(path)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw ServerError.bindFailed(String(cString: strerror(errno)))
        }

        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            throw ServerError.bindFailed("socket path too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, size)
            }
        }
        guard bound == 0 else {
            let message = String(cString: strerror(errno))
            close(descriptor)
            throw ServerError.bindFailed(message)
        }

        // Owner-only. Nothing else on the machine gets to draw on the island.
        chmod(path, 0o600)

        guard listen(descriptor, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(descriptor)
            throw ServerError.bindFailed(message)
        }

        listenDescriptor = descriptor
        boundInode = Self.identity(ofFileAt: path)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.acceptPending() }
        }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenDescriptor >= 0 { close(listenDescriptor) }
        listenDescriptor = -1

        // Only remove the socket if it is still the one we created.
        //
        // Relaunching kills the old process and starts a new one, and the two
        // overlap: the newcomer binds a fresh socket while the outgoing app is
        // still tearing down. An unconditional `unlink` here deletes the *new*
        // app's socket, leaving it listening on an unreachable inode — the app
        // looks alive but every client reports "Ledge isn't running".
        guard let boundInode,
              let current = Self.identity(ofFileAt: LedgeSocket.path),
              current == boundInode
        else { return }
        unlink(LedgeSocket.path)
    }

    private static func identity(ofFileAt path: String) -> (device: dev_t, inode: ino_t)? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return (info.st_dev, info.st_ino)
    }

    // MARK: - Connections

    private func acceptPending() {
        let client = accept(listenDescriptor, nil, nil)
        guard client >= 0 else { return }

        ioQueue.async { [weak self] in
            defer { close(client) }
            guard let line = Self.readLine(from: client), !line.isEmpty else { return }

            let response: LedgeResponse
            if let request = try? LedgeCoding.decoder.decode(LedgeRequest.self, from: line) {
                // Hop to the main actor to touch the store, then come back.
                response = DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        self?.handle(request) ?? .failure("Ledge is shutting down.")
                    }
                }
            } else {
                response = .failure("Malformed request.")
            }

            if let data = try? LedgeCoding.line(response) {
                Self.writeAll(data, to: client)
            }
        }
    }

    private func handle(_ request: LedgeRequest) -> LedgeResponse {
        switch request.command {
        case .ping:
            return LedgeResponse(ok: true, message: "ledge")

        case .present:
            guard let activity = request.activity else {
                return .failure("`present` needs an activity.")
            }
            let stored = store.present(activity)
            return LedgeResponse(ok: true, id: stored.id)

        case .update:
            guard let id = request.id, let content = request.content else {
                return .failure("`update` needs an id and content.")
            }
            guard store.update(id: id, content: content) else {
                return .failure("No activity with id \"\(id)\".")
            }
            return LedgeResponse(ok: true, id: id)

        case .end:
            guard let id = request.id else { return .failure("`end` needs an id.") }
            guard store.end(id: id) else {
                return .failure("No activity with id \"\(id)\".")
            }
            return LedgeResponse(ok: true, id: id)

        case .endAll:
            let count = store.endAll(source: request.source)
            return LedgeResponse(ok: true, count: count)

        case .list:
            let live = store.composition.all
            return LedgeResponse(ok: true, activities: live, count: live.count)

        case .startTimer:
            guard let duration = request.duration, duration > 0 else {
                return .failure("`startTimer` needs a positive duration in seconds.")
            }
            guard let timers else {
                return .failure("The timer module is turned off.")
            }
            let id = timers.startTimer(label: request.content?.title, duration: duration)
            return LedgeResponse(ok: true, id: id)

        case .shelf:
            guard let shelf else { return .failure("The shelf isn't available.") }
            let paths = request.paths ?? []
            guard !paths.isEmpty else {
                shelf.clear()
                return LedgeResponse(ok: true, count: 0)
            }
            // Resolve and reject anything that isn't actually there, rather
            // than shelving a broken reference the user can't act on.
            let urls = paths.compactMap { path -> URL? in
                let expanded = (path as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded).standardizedFileURL
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
            guard !urls.isEmpty else { return .failure("None of those paths exist.") }
            shelf.accept(urls)
            return LedgeResponse(ok: true, count: shelf.files.count)

        case .weather:
            guard let weather else {
                return .failure("The weather module is turned off.")
            }
            weather.showNow()
            guard let reading = weather.latest else {
                // Not an error: the first call usually arrives before the first
                // fetch has landed.
                return LedgeResponse(ok: true, message: "Fetching…")
            }
            return LedgeResponse(
                ok: true,
                message: "\(reading.condition.summary), \(Int(reading.temperature.rounded()))°"
            )

        case .expand:
            guard !store.composition.isIdle else {
                return .failure("Nothing on the island to expand.")
            }
            if let id = request.id {
                guard store.activities[id] != nil else {
                    return .failure("No activity with id \"\(id)\".")
                }
                store.focusedActivityID = id
            }
            store.isExpanded = true
            return LedgeResponse(ok: true, id: store.composition.expandedActivity?.id)

        case .collapse:
            store.isExpanded = false
            store.focusedActivityID = nil
            return LedgeResponse(ok: true)

        case .settings:
            guard let openSettings else { return .failure("Settings aren't available.") }
            // `id` carries the tab name, `source` the module to customise.
            openSettings(request.id, request.source)
            return LedgeResponse(ok: true, message: "opened")
        }
    }

    // MARK: - Framing

    nonisolated private static func readLine(from descriptor: Int32) -> Data? {
        var accumulated = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(descriptor, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { break }
            accumulated.append(contentsOf: chunk[0..<count])
            if let newline = accumulated.firstIndex(of: 0x0A) {
                return accumulated[accumulated.startIndex..<newline]
            }
            // A client that never sends a newline shouldn't be able to make us
            // buffer without bound.
            if accumulated.count > 4_000_000 { return nil }
        }
        return accumulated
    }

    nonisolated private static func writeAll(_ data: Data, to descriptor: Int32) {
        var remaining = data
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return write(descriptor, base, buffer.count)
            }
            if written <= 0 {
                if errno == EINTR { continue }
                return
            }
            remaining.removeFirst(written)
        }
    }
}
