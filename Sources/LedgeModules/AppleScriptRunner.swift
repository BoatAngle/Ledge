import AppKit
import Foundation

/// Runs AppleScript off the main thread and hands back plain values.
///
/// `NSAppleScript` blocks its caller, and a media poll that stalls the main
/// thread would stutter every animation in the island. Everything here is
/// funnelled through one serial queue and returns `Sendable` results only.
enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "com.ledge.applescript", qos: .utility)

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
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? result?.stringValue : nil)
            }
        }
    }

    /// Executes `source`, returning its result as raw bytes — used for artwork.
    static func data(_ source: String) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? result?.data : nil)
            }
        }
    }

    /// Fire-and-forget, for playback controls where the return value is noise.
    static func perform(_ source: String) {
        queue.async {
            var error: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}
