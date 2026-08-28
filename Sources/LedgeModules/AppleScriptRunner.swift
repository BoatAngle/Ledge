import AppKit
import Foundation

/// Runs AppleScript off the main thread and hands back plain values.
///
/// `NSAppleScript` blocks its caller, and a media poll that stalls the main
/// thread would stutter every animation in the island. Everything here is
/// funnelled through one serial queue and returns `Sendable` results only.
enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "com.ledge.applescript", qos: .utility)

    /// Compiled scripts, keyed by source.
    ///
    /// `NSAppleScript(source:)` *compiles*, and the media poller was paying for
    /// a fresh compile of the same twelve-line script once a second — 86,400
    /// identical compilations a day for a value that changes on a human
    /// timescale. Compiled scripts are reusable; only the execution has to
    /// repeat.
    ///
    /// Confined to `queue`, which is serial, so the cache needs no lock of its
    /// own — and `NSAppleScript` is not thread-safe anyway, which is the more
    /// important reason every touch of it stays on that one queue.
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]

    /// Fetch or build the compiled form. Must be called on `queue`.
    private static func script(for source: String) -> NSAppleScript? {
        if let existing = compiled[source] { return existing }
        guard let script = NSAppleScript(source: source) else { return nil }
        // Compile eagerly so a syntax error surfaces here rather than being
        // re-discovered on every execution.
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { return nil }
        compiled[source] = script
        return script
    }

    /// Whether an app is running, checked without touching AppleScript.
    ///
    /// This matters for more than speed: querying a *stopped* app through
    /// AppleScript can launch it, and an island that boots Music because you
    /// glanced at the notch would be a bug worth apologising for.
    @MainActor
    static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Executes `source`, returning its result coerced to a string.
    static func string(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = script(for: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? result?.stringValue : nil)
            }
        }
    }

    /// Executes `source`, returning its result as raw bytes — used for artwork.
    static func data(_ source: String) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = script(for: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? result?.data : nil)
            }
        }
    }

    /// Fire-and-forget, for playback controls where the return value is noise.
    static func perform(_ source: String) {
        queue.async {
            var error: NSDictionary?
            _ = script(for: source)?.executeAndReturnError(&error)
        }
    }
}
