import AppKit
import IsletCore
import IsletModules
import SwiftUI

/// Ferries `islet settings --customize <id>` into the Modules pane.
///
/// An observable object rather than a view rebuild: the window's hierarchy
/// stays alive for its whole life, so deep links have to *flow into* the
/// existing panes instead of recreating them around the parameter.
@MainActor
@Observable
final class SettingsSession {
    var customizing: String?
}

/// Hosts the settings window for a menu-bar-only app.
///
/// Islet runs as an accessory (`LSUIElement`), which normally has no menu bar
/// and no Dock icon. A settings window in that state can't be brought to the
/// front properly — so the activation policy is promoted to `.regular` while
/// the window is open and dropped back when it closes. (⌘W and the Edit-menu
/// shortcuts come from the main menu AppDelegate installs.)
///
/// The panes are NSTabViewController tabs with `tabStyle = .toolbar` — the
/// native settings idiom (Safari, Mail, Notes): icon-and-label items in the
/// window toolbar, the window title tracking the selected pane, and the window
/// height animating to each pane's own size. SwiftUI's `TabView` can't produce
/// that outside a `Settings` scene, which an LSUIElement app with a
/// hand-managed window doesn't get.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var tabController: NSTabViewController?
    private let session = SettingsSession()
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

    func show(tab: SettingsTab = .general, customizing: String? = nil) {
        if window == nil { build() }
        guard let window, let tabController else { return }

        // Session first, selection second: if the Modules pane is about to
        // attach, its .onAppear must already see the request.
        session.customizing = customizing
        if let index = SettingsTab.allCases.firstIndex(of: tab) {
            tabController.selectedTabViewItemIndex = index
            window.title = tab.title
        }
        promote()
        window.makeKeyAndOrderFront(nil)
    }

    /// Builds the window once; it is never rebuilt afterwards. Panes react to
    /// model changes through observation, so replacing content views — which
    /// would tear down sheets, focus, and scroll position under the user — is
    /// never necessary.
    private func build() {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: pane(for: tab))
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.tabbingMode = .disallowed
        window.title = SettingsTab.general.title
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        self.window = window
        self.tabController = tabs
    }

    @ViewBuilder
    private func paneContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettings(settings: settings)
        case .modules:
            ModuleSettings(
                settings: settings,
                session: session,
                modules: modules,
                onToggle: onToggleModule
            )
        case .weather:
            WeatherSettings(settings: settings, provider: weatherProvider)
        case .about:
            AboutSettings(cliPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers/islet").path)
        }
    }

    private func pane(for tab: SettingsTab) -> AnyView {
        AnyView(ThemedPane(settings: settings) { paneContent(for: tab) })
    }

    private func promote() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        // Back to menu-bar-only, so Islet stops appearing in the Dock and the
        // app switcher the moment settings is dismissed.
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Keeps the window title equal to the selected pane's name — the settings
/// convention everywhere on macOS: the title *is* the pane.
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let label = tabViewItem?.label {
            view.window?.title = label
        }
    }
}

/// Applies the user's island theme to a whole settings pane.
///
/// Sheets inherit the presenting view's environment, so this one modifier is
/// what makes the customization sheet's live preview — and every island
/// preview in settings — render in the theme the user actually chose, rather
/// than the library default.
struct ThemedPane<Content: View>: View {
    var settings: IsletSettings
    @ViewBuilder var content: Content

    var body: some View {
        // Read inside body so @Observable registers the dependency and the
        // pane re-renders when the theme changes.
        content.islandTheme(.preset(settings.theme))
    }
}
