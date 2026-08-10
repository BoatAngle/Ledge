import AppKit
import IsletCore
import IsletModules
import IsletUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ActivityStore()
    private let registry = ProviderRegistry()
    private lazy var windowController = IslandWindowController(store: store)
    private lazy var server = ActivityServer(store: store)
    private var statusItem: NSStatusItem?
    private var allProviders: [any SystemProvider] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController.show()

        allProviders = ProviderRegistry.standard()
        registry.start(allProviders.filter(isEnabled), store: store)

        do {
            try server.start()
        } catch {
            // The island is still fully useful without the API — the built-in
            // modules don't go through the socket — so this is a warning, not a
            // launch failure.
            NSLog("[Islet] \(error)")
        }

        buildStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry.stop()
        server.stop()
        windowController.hide()
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "capsule.fill",
            accessibilityDescription: "Islet"
        )
        item.button?.image?.isTemplate = true
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: displayStatus, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let modules = NSMenu()
        for provider in allProviders {
            let item = NSMenuItem(
                title: provider.displayName,
                action: #selector(toggleModule(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = provider.identifier
            if provider.isAvailable {
                item.state = isEnabled(provider) ? .on : .off
            } else {
                item.isEnabled = false
                item.toolTip = "Not available on this Mac."
            }
            modules.addItem(item)
        }
        let modulesItem = NSMenuItem(title: "Modules", action: nil, keyEquivalent: "")
        modulesItem.submenu = modules
        menu.addItem(modulesItem)

        let demo = NSMenuItem(title: "Run Demo Activity", action: #selector(runDemo), keyEquivalent: "")
        demo.target = self
        menu.addItem(demo)

        let install = NSMenuItem(
            title: "Copy CLI Install Command",
            action: #selector(copyInstallCommand),
            keyEquivalent: ""
        )
        install.target = self
        menu.addItem(install)

        menu.addItem(.separator())

        let login = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Islet", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private var displayStatus: String {
        windowController.isOnNotchedDisplay
            ? "Islet — hugging the notch"
            : "Islet — virtual island"
    }

    // MARK: - Actions

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let provider = allProviders.first(where: { $0.identifier == identifier })
        else { return }

        let nowEnabled = !isEnabled(provider)
        UserDefaults.standard.set(nowEnabled, forKey: Self.defaultsKey(for: identifier))
        sender.state = nowEnabled ? .on : .off

        // Simplest correct thing: restart the set. Providers are cheap to
        // construct and this avoids partial-teardown bugs.
        registry.stop()
        allProviders = ProviderRegistry.standard()
        registry.start(allProviders.filter(isEnabled), store: store)
        statusItem?.menu = buildMenu()
    }

    @objc private func runDemo() {
        store.present(
            Activity(
                id: "demo.\(UUID().uuidString.prefix(6))",
                source: "demo",
                kind: .ongoing,
                priority: .normal,
                content: ActivityContent(
                    title: "Islet is running",
                    subtitle: "Hover to expand, click to dismiss",
                    body: "Post your own activities with the islet CLI.",
                    icon: .symbol("sparkles"),
                    tint: .accent,
                    progress: ActivityProgress(fraction: 0.62, label: "Demo activity"),
                    details: [ActivityDetail(label: "Source", value: "menu bar")],
                    actions: [ActivityAction(id: "demo.dismiss", title: "Nice", symbol: "hand.thumbsup")]
                ),
                expiresAt: Date().addingTimeInterval(12)
            )
        )
    }

    @objc private func copyInstallCommand() {
        let binary = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/islet").path
        let command = "sudo ln -sf \"\(binary)\" /usr/local/bin/islet"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Install command copied"
        alert.informativeText = """
        Paste this into Terminal to put `islet` on your PATH:

        \(command)

        It creates a symlink to the CLI inside Islet.app — nothing is \
        downloaded, and you can read the command before you run it.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("[Islet] launch at login: \(error)")
        }
        statusItem?.menu = buildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Preferences

    private static func defaultsKey(for identifier: String) -> String {
        "module.\(identifier).enabled"
    }

    /// Modules are on unless the user has turned them off.
    private func isEnabled(_ provider: any SystemProvider) -> Bool {
        let key = Self.defaultsKey(for: provider.identifier)
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
}
