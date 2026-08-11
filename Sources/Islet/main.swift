import AppKit

@main
@MainActor
enum IsletApp {
    static func main() {
        // Developer flag: render the icon contact sheet and exit.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--glyph-sheet"), index + 1 < arguments.count {
            GlyphSheet.render(to: arguments[index + 1])
            exit(0)
        }

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
