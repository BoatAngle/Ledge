import AppKit
import LedgeCore
import LedgeModules
import LedgeUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ActivityStore()
    private let settings = LedgeSettings.shared
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
        },
        onGrantPermission: { [weak self] identifier in
            await self?.grantPermission(identifier) ?? false
        }
    )
    private var appearanceObserver: NSObjectProtocol?
    private lazy var lockMonitor = LockMonitor { [weak self] isLocked in
        // Providers stand down while the machine is locked; activities already
        // on the island (a running timer, say) stay exactly where they were.
        if isLocked { self?.registry.suspendAll() } else { self?.registry.resumeAll() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A real main menu, even though the app is menu-bar-only. The settings
        // window promotes the activation policy to .regular, and without this
        // the menu bar comes up empty: ⌘W closes nothing and ⌘C/⌘V/⌘X are dead
        // in every text field — you couldn't paste coordinates into Weather.
        NSApp.mainMenu = buildMainMenu()

        // The scheduler consults per-module appearance for slot and priority
        // nudges; it takes a closure so Core never learns about settings.
        store.appearanceForModule = { [settings] identifier in
            settings.appearance(for: identifier)
        }
        windowController.show()

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .ledgeAppearanceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.refresh() }
        }

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
        }

        do {
            server.shelf = windowController.shelf
            server.openSettings = { [weak self] tab, customizing in
                self?.settingsWindow.show(
                    tab: customizing != nil ? .modules : SettingsTab.named(tab),
                    customizing: customizing
                )
            }
            try server.start()
        } catch {
            // The island is still fully useful without the API — the built-in
            // modules don't go through the socket — so this is a warning, not a
            // launch failure.
            NSLog("[Ledge] \(error)")
        }

        buildStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
        if let demoObserver { NotificationCenter.default.removeObserver(demoObserver) }
        lockMonitor.stop()
        registry.stop()
        server.stop()
        windowController.hide()
    }

    // MARK: - Main menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(
            withTitle: "About Ledge",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        app.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        app.addItem(prefs)
        app.addItem(.separator())
        app.addItem(
            withTitle: "Hide Ledge",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(hideOthers)
        app.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        app.addItem(.separator())
        app.addItem(
            withTitle: "Quit Ledge",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = app
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: "File")
        file.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileItem.submenu = file
        main.addItem(fileItem)

        // Standard Edit items, all targeting the first responder.
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(.separator())
        edit.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "capsule.fill",
            accessibilityDescription: "Ledge"
        )
        item.button?.image?.isTemplate = true
        // Rebuilt on every open via NSMenuDelegate — a baked menu shows a
        // running timer's remaining time from whenever it was last built.
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let fresh = buildMenu()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
        menu.autoenablesItems = false
    }

    /// Actions first, configuration after — the Apple status-menu shape.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // Without this, every manual isEnabled below is silently overridden
        // for any item with a live target/action.
        menu.autoenablesItems = false

        menu.addItem(NSMenuItem.sectionHeader(title: displayStatus))

        menu.addItem(timerMenuItem())

        let weather = NSMenuItem(
            title: "Show Weather",
            action: #selector(showWeather),
            keyEquivalent: ""
        )
        weather.target = self
        weather.image = NSImage(systemSymbolName: "cloud.sun", accessibilityDescription: nil)
        weather.isEnabled = settings.weatherMode != .off
        menu.addItem(weather)

        menu.addItem(.separator())

        let modules = NSMenu()
        modules.autoenablesItems = false
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
        modulesItem.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        modulesItem.submenu = modules
        menu.addItem(modulesItem)

        let demo = NSMenuItem(title: "Show Demo Activity", action: #selector(runDemo), keyEquivalent: "")
        demo.target = self
        demo.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        menu.addItem(demo)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Ledge", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private var displayStatus: String {
        windowController.isOnNotchedDisplay
            ? "Ledge — hugging the notch"
            : "Ledge — virtual island"
    }

    // MARK: - Actions

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let provider = allProviders.first(where: { $0.identifier == identifier }),
              provider.isAvailable
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
        // The status menu rebuilds itself on open (menuNeedsUpdate).
        // The settings window is NOT refreshed here: its panes observe
        // settings.moduleRevision and re-render themselves. Rebuilding its
        // content view used to teleport an open window to the Modules tab.
    }

    /// Which pane section each module belongs to: things with a lifetime
    /// (media, timers, meetings, downloads, weather) versus system state.
    private static let activityModules: Set<String> = [
        "system.media", "system.timer", "system.calendar",
        "system.downloads", "system.weather",
    ]

    private func moduleInfo() -> [ModuleInfo] {
        allProviders.map {
            ModuleInfo(
                id: $0.identifier,
                name: $0.displayName,
                isAvailable: $0.isAvailable,
                summary: $0.summary,
                group: Self.activityModules.contains($0.identifier) ? .activities : .system,
                permission: $0.permissionState
            )
        }
    }

    /// The Grant Access gesture from Settings — the explicit user intent the
    /// one-and-done permission rule waits for.
    private func grantPermission(_ identifier: String) async -> Bool {
        guard let provider = allProviders.first(where: { $0.identifier == identifier })
        else { return false }
        let granted = await provider.requestPermission()
        if granted {
            settings.markPermissionVerified(identifier)
        }
        return granted
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
        submenu.autoenablesItems = false
        for minutes in [1, 5, 10, 25, 45] {
            let item = NSMenuItem(
                title: minutes == 1 ? "1 Minute" : "\(minutes) Minutes",
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
            if running.count > 1 {
                submenu.addItem(.separator())
                let all = NSMenuItem(
                    title: "Cancel All Timers",
                    action: #selector(cancelAllTimers),
                    keyEquivalent: ""
                )
                all.target = self
                submenu.addItem(all)
            }
        }

        let item = NSMenuItem(title: "Start Timer", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
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
    }

    @objc private func cancelTimer(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        timerProvider?.cancel(id: id)
    }

    @objc private func cancelAllTimers() {
        timerProvider?.cancelAll()
    }

    private var demoObserver: NSObjectProtocol?

    @objc private func runDemo() {
        let demoID = "demo.\(UUID().uuidString.prefix(6))"
        // The demo's one button must visibly DO something — it's the first
        // action a new user ever presses, and a dead button teaches that
        // buttons are decoration.
        if demoObserver == nil {
            demoObserver = NotificationCenter.default.addObserver(
                forName: .ledgeActionInvoked,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard (note.userInfo?["actionID"] as? String) == "demo.dismiss" else { return }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for activity in self.store.composition.all where activity.source == "demo" {
                        self.store.end(id: activity.id)
                    }
                }
            }
        }
        store.present(
            Activity(
                id: demoID,
                source: "demo",
                kind: .ongoing,
                priority: .normal,
                content: ActivityContent(
                    title: "Ledge is running",
                    subtitle: "Hover or click to expand",
                    body: "Post your own activities with the ledge CLI.",
                    icon: .symbol("sparkles"),
                    tint: .accent,
                    progress: ActivityProgress(fraction: 0.62, label: "Demo activity"),
                    details: [ActivityDetail(label: "Source", value: "menu bar")],
                    actions: [ActivityAction(id: "demo.dismiss", title: "Done", symbol: "checkmark")]
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
