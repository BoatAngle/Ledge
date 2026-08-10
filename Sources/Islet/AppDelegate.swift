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
    private var timerProvider: TimerProvider?
    private lazy var lockMonitor = LockMonitor { [weak self] isLocked in
        // Providers stand down while the machine is locked; activities already
        // on the island (a running timer, say) stay exactly where they were.
        if isLocked { self?.registry.suspendAll() } else { self?.registry.resumeAll() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController.show()

        // Providers start on the *next* run-loop turn, never inline here.
        //
        // Several of them touch TCC-protected resources — the Downloads folder,
        // Calendar, Apple Events. Triggering a consent prompt from inside
        // `applicationDidFinishLaunching` deadlocks: the app hasn't finished
        // launching, so the prompt can't be presented, so launch never
        // finishes. It looks exactly like a hang with no crash log.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.allProviders = ProviderRegistry.standard()
            self.registry.start(self.allProviders.filter(self.isEnabled), store: self.store)
            self.timerProvider = self.registry.providers.compactMap { $0 as? TimerProvider }.first
            self.server.timers = self.timerProvider
            self.lockMonitor.start()
            self.statusItem?.menu = self.buildMenu()
        }

        do {
            server.shelf = windowController.shelf
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
        lockMonitor.stop()
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

        menu.addItem(timerMenuItem())

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
        timerProvider = registry.providers.compactMap { $0 as? TimerProvider }.first
        server.timers = timerProvider
        statusItem?.menu = buildMenu()
    }

    private func timerMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for minutes in [1, 5, 10, 25, 45] {
            let item = NSMenuItem(
                title: "\(minutes) minutes",
                action: #selector(startTimer(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = minutes
            submenu.addItem(item)
        }

        let running = timerProvider?.running ?? []
        if !running.isEmpty {
            submenu.addItem(.separator())
            for timer in running {
                let item = NSMenuItem(
                    title: "Cancel \(timer.label) — \(Self.clock(timer.remaining)) left",
                    action: #selector(cancelTimer(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = timer.id
                submenu.addItem(item)
            }
        }

        let item = NSMenuItem(title: "Start Timer", action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.isEnabled = timerProvider != nil
        return item
    }

    private static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        timerProvider?.startTimer(label: nil, duration: TimeInterval(minutes * 60))
        statusItem?.menu = buildMenu()
    }

    @objc private func cancelTimer(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        timerProvider?.cancel(id: id)
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
