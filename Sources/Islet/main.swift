import AppKit

@main
@MainActor
enum IsletApp {
    static func main() {
        let application = NSApplication.shared
        // Menu-bar only: the island *is* the interface, and a Dock icon for it
        // would be noise.
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        // Held so ARC doesn't reclaim the delegate the moment `main` returns
        // into the run loop.
        Self.delegate = delegate
        application.run()
    }

    private static var delegate: AppDelegate?
}
