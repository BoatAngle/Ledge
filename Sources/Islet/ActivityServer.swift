import Darwin
import Foundation
import IsletCore
import IsletModules
import IsletUI

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
            case .bindFailed(let detail): return "Couldn't open the Islet socket: \(detail)"
            }
        }
    }

    private let store: ActivityStore
    /// Timers need an owner with a run loop, so `.startTimer` is delegated to
    /// the provider rather than synthesised from an activity here.
    weak var timers: TimerProvider?
    weak var shelf: DropShelf?
    private var listenDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    /// Identity of the socket file we created, so shutdown can tell ours apart
    /// from a successor's.
    private var boundInode: (device: dev_t, inode: ino_t)?
    private let ioQueue = DispatchQueue(label: "com.islet.server.io", qos: .userInitiated)

    init(store: ActivityStore) {
        self.store = store
    }

    // MARK: - Lifecycle

    func start() throws {
        try? IsletSocket.ensureDirectory()
        let path = IsletSocket.path

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
        // looks alive but every client reports "Islet isn't running".
        guard let boundInode,
              let current = Self.identity(ofFileAt: IsletSocket.path),
              current == boundInode
        else { return }
        unlink(IsletSocket.path)
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

            let response: IsletResponse
            if let request = try? IsletCoding.decoder.decode(IsletRequest.self, from: line) {
                // Hop to the main actor to touch the store, then come back.
                response = DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        self?.handle(request) ?? .failure("Islet is shutting down.")
                    }
                }
            } else {
                response = .failure("Malformed request.")
            }

            if let data = try? IsletCoding.line(response) {
                Self.writeAll(data, to: client)
            }
        }
    }

    private func handle(_ request: IsletRequest) -> IsletResponse {
        switch request.command {
        case .ping:
            return IsletResponse(ok: true, message: "islet")

        case .present:
            guard let activity = request.activity else {
                return .failure("`present` needs an activity.")
            }
            let stored = store.present(activity)
            return IsletResponse(ok: true, id: stored.id)

        case .update:
            guard let id = request.id, let content = request.content else {
                return .failure("`update` needs an id and content.")
            }
            guard store.update(id: id, content: content) else {
                return .failure("No activity with id \"\(id)\".")
            }
            return IsletResponse(ok: true, id: id)

        case .end:
            guard let id = request.id else { return .failure("`end` needs an id.") }
            guard store.end(id: id) else {
                return .failure("No activity with id \"\(id)\".")
            }
            return IsletResponse(ok: true, id: id)

        case .endAll:
            let count = store.endAll(source: request.source)
            return IsletResponse(ok: true, count: count)

        case .list:
            let live = store.composition.all
            return IsletResponse(ok: true, activities: live, count: live.count)

        case .startTimer:
            guard let duration = request.duration, duration > 0 else {
                return .failure("`startTimer` needs a positive duration in seconds.")
            }
            guard let timers else {
                return .failure("The timer module is turned off.")
            }
            let id = timers.startTimer(label: request.content?.title, duration: duration)
            return IsletResponse(ok: true, id: id)

        case .shelf:
            guard let shelf else { return .failure("The shelf isn't available.") }
            let paths = request.paths ?? []
            guard !paths.isEmpty else {
                shelf.clear()
                return IsletResponse(ok: true, count: 0)
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
            return IsletResponse(ok: true, count: shelf.files.count)
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
