import Darwin
import Foundation

/// A tiny blocking client for the island's Unix socket.
///
/// Deliberately synchronous and dependency-free: the CLI's whole job is one
/// round trip, and a shell script calling `islet update` in a loop should not
/// pay for a runloop to do it.
public struct IsletClient: Sendable {
    public enum ClientError: Error, CustomStringConvertible {
        case notRunning
        case io(String)
        case malformedResponse
        case rejected(String)
        case timedOut

        public var description: String {
            switch self {
            case .notRunning:
                return "Islet isn't running. Launch Islet.app and try again."
            case .io(let detail):
                return "Socket error: \(detail)"
            case .malformedResponse:
                return "Islet sent a response this client couldn't parse."
            case .rejected(let reason):
                return reason
            case .timedOut:
                return """
                Islet didn't respond in time. It may be waiting on a permission \
                prompt — check for a dialog, then try again.
                """
            }
        }
    }

    public var socketPath: String
    /// Give up rather than block forever.
    ///
    /// The server answers on the main thread, so anything that blocks it — a
    /// permission prompt waiting on the user, most memorably — would otherwise
    /// leave `islet` wedged in a shell script with no way out.
    public var timeout: TimeInterval

    public init(socketPath: String = IsletSocket.path, timeout: TimeInterval = 5) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    /// True when something is listening. Cheap enough to call before each use.
    public var isRunning: Bool {
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }
        guard let fd = try? connectSocket() else { return false }
        close(fd)
        return true
    }

    @discardableResult
    public func send(_ request: IsletRequest) throws -> IsletResponse {
        let fd = try connectSocket()
        defer { close(fd) }

        let payload = try IsletCoding.line(request)
        try writeAll(fd: fd, data: payload)

        guard let line = try readLine(fd: fd) else { throw ClientError.malformedResponse }
        guard let response = try? IsletCoding.decoder.decode(IsletResponse.self, from: line) else {
            throw ClientError.malformedResponse
        }
        guard response.ok else {
            throw ClientError.rejected(response.message ?? "Islet rejected the request.")
        }
        return response
    }

    // MARK: - POSIX plumbing

    private func connectSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.io(String(cString: strerror(errno))) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else {
            close(fd)
            throw ClientError.io("Socket path is too long for sockaddr_un.")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPointer in
                Darwin.connect(fd, sockPointer, size)
            }
        }
        guard result == 0 else {
            let err = errno
            close(fd)
            if err == ECONNREFUSED || err == ENOENT { throw ClientError.notRunning }
            throw ClientError.io(String(cString: strerror(err)))
        }

        var tv = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - floor(timeout)) * 1_000_000)
        )
        let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, timeoutSize)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, timeoutSize)
        return fd
    }

    private func writeAll(fd: Int32, data: Data) throws {
        var remaining = data
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return Darwin.write(fd, base, buffer.count)
            }
            if written <= 0 {
                if errno == EINTR { continue }
                throw ClientError.io(String(cString: strerror(errno)))
            }
            remaining.removeFirst(written)
        }
    }

    private func readLine(fd: Int32) throws -> Data? {
        var accumulated = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw ClientError.timedOut }
                throw ClientError.io(String(cString: strerror(errno)))
            }
            if count == 0 { break }
            accumulated.append(contentsOf: chunk[0..<count])
            if let newline = accumulated.firstIndex(of: 0x0A) {
                return accumulated[accumulated.startIndex..<newline]
            }
        }
        return accumulated.isEmpty ? nil : accumulated
    }
}
