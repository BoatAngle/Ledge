import AppKit
import IsletCore
import IsletModules
import IsletUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ActivityStore()
    private let settings = IsletSettings.shared
    private let registry = ProviderRegistry()
    private lazy var windowController = IslandWindowController(store: store)
    private lazy var server = ActivityServer(store: store)
    private var statusItem: NSStatusItem?
    private var allProviders: [any SystemProvider] = []
    private var timerProvider: TimerProvider?
    private var weatherProvider: WeatherProvider?
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        modules: { [weak self] in self?.moduleInfo() ?? [] },
        weatherProvider: { [weak self] in self?.weatherProvider },
        onToggleModule: { [weak self] identifier, enabled in
            self?.setModule(identifier, enabled: enabled)
        }
    )
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
            self.weatherProvider = self.registry.providers.compactMap { $0 as? WeatherProvider }.first
            self.server.timers = self.timerProvider
            self.server.weather = self.weatherProvider
            self.lockMonitor.start()
            self.statusItem?.menu = self.buildMenu()
        }

        do {
            server.shelf = windowController.shelf
            server.openSettings = { [weak self] tab in
                self?.settingsWindow.show(tab: SettingsTab.named(tab))
            }
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

        let weather = NSMenuItem(
            title: "Show Weather",
            action: #selector(showWeather),
            keyEquivalent: ""
        )
        weather.target = self
        weather.isEnabled = settings.weatherMode != .off
        menu.addItem(weather)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

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
        setModule(identifier, enabled: !isEnabled(provider))
    }

    /// Enable or disable a module and restart the set.
    ///
    /// Restarting everything rather than starting/stopping the one provider:
    /// they are cheap to construct, and this rules out partial-teardown bugs
    /// where a stopped provider leaves an activity or a timer behind.
    private func setModule(_ identifier: String, enabled: Bool) {
        settings.setModule(identifier, enabled: enabled)
        registry.stop()
        allProviders = ProviderRegistry.standard()
        registry.start(allProviders.filter(isEnabled), store: store)
        timerProvider = registry.providers.compactMap { $0 as? TimerProvider }.first
        weatherProvider = registry.providers.compactMap { $0 as? WeatherProvider }.first
        server.timers = timerProvider
        server.weather = weatherProvider
        statusItem?.menu = buildMenu()
        settingsWindow.refresh()
    }

    private func moduleInfo() -> [ModuleInfo] {
        allProviders.map {
            ModuleInfo(
                id: $0.identifier,
                name: $0.displayName,
                isAvailable: $0.isAvailable,
                summary: $0.summary
            )
        }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func showWeather() {
        weatherProvider?.showNow()
    }

    @objc private func openWeatherSettings() {
        settingsWindow.show(tab: .weather)
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

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Preferences

    private func isEnabled(_ provider: any SystemProvider) -> Bool {
        settings.isModuleEnabled(provider.identifier)
    }
}
