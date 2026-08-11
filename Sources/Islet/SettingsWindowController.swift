import AppKit
import IsletCore
import IsletModules
import SwiftUI

/// Hosts the settings window for a menu-bar-only app.
///
/// Islet runs as an accessory (`LSUIElement`), which normally has no menu bar
/// and no Dock icon. A settings window in that state can't be brought to the
/// front properly and gets no ⌘W — so the activation policy is promoted to
/// `.regular` while the window is open and dropped back when it closes.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: IsletSettings
    private let modules: () -> [ModuleInfo]
    private let weatherProvider: () -> WeatherProvider?
    private let onToggleModule: (String, Bool) -> Void

    init(
        settings: IsletSettings,
        modules: @escaping () -> [ModuleInfo],
        weatherProvider: @escaping () -> WeatherProvider?,
        onToggleModule: @escaping (String, Bool) -> Void
    ) {
        self.settings = settings
        self.modules = modules
        self.weatherProvider = weatherProvider
        self.onToggleModule = onToggleModule
    }

    func show(tab: SettingsTab = .general) {
        if let window {
            // Rebuild so the requested tab is the one on screen.
            window.contentView = NSHostingView(rootView: makeRoot(tab: tab))
            promote()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = makeRoot(tab: tab)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Islet Settings"
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window

        promote()
        window.makeKeyAndOrderFront(nil)
    }

    /// Rebuild the root view so a freshly toggled module list is reflected.
    func refresh() {
        guard let window else { return }
        window.contentView = NSHostingView(rootView: makeRoot(tab: .modules))
    }

    private func makeRoot(tab: SettingsTab) -> SettingsView {
        SettingsView(
            settings: settings,
            tab: tab,
            modules: modules(),
            weatherProvider: weatherProvider(),
            onToggleModule: onToggleModule,
            cliPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers/islet").path
        )
    }

    private func promote() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to menu-bar-only, so Islet stops appearing in the Dock and the
        // app switcher the moment settings is dismissed.
        NSApp.setActivationPolicy(.accessory)
    }
}
