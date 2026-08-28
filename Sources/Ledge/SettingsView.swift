import AppKit
import LedgeCore
import LedgeModules
import LedgeUI
import ServiceManagement
import SwiftUI

// The design boundary for this window: the window CHROME speaks macOS —
// SF Symbols in the toolbar tabs, info.circle affordances, standard buttons —
// while anything DEPICTING island content speaks Ledge: glyph chips, island
// previews, the weather readout. Don't convert the chrome to the glyph family,
// and don't let SF Symbols stand in for what the island would draw.

/// What the Modules pane needs to know about a provider.
struct ModuleInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var isAvailable: Bool
    var summary: String
    var group: ModuleGroup = .system
    var permission: ModulePermissionState = .notNeeded
}

/// The two kinds of thing a module puts on the island: ongoing activities
/// with a lifetime, and system state that flashes or idles.
enum ModuleGroup: CaseIterable {
    case activities, system

    var title: String {
        switch self {
        case .activities: return "Activities"
        case .system: return "System"
        }
    }
}

/// The settings window's panes, addressable by name so `ledge settings
/// --tab weather` can jump straight to one.
enum SettingsTab: String, CaseIterable {
    case general, modules, weather, about

    static func named(_ raw: String?) -> SettingsTab {
        guard let raw else { return .general }
        return SettingsTab(rawValue: raw.lowercased()) ?? .general
    }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .modules: return "square.grid.2x2"
        case .weather: return "cloud.sun"
        case .about: return "info.circle"
        }
    }
}

/// Soft scroll-edge treatment where the system has it. The panes get this
/// through ThemedPane; the customization sheet applies it to its own Form.
struct SoftTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

/// Grouped-form section footers align trailing by default on macOS; every
/// footer in this window wants the conventional leading block instead.
struct SettingsFooter: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Customized" marker, shared between the module list and the sheet header.
struct CustomizedBadge: View {
    var body: some View {
        Text("Customized")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
            .foregroundStyle(Color.accentColor)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var settings: LedgeSettings
    @Namespace private var themeNS
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmingReset = false

    /// A representative activity so theme cards show a real island rather
    /// than an abstract swatch. All four cards render the same one, so the
    /// four positions are directly comparable.
    private var themeSample: Activity {
        ModulePreviewSample.activity(for: "system.timer")
    }

    var body: some View {
        Form {
            Section {
                themeGrid
                    .padding(.vertical, 2)
            } header: {
                Text("Theme")
            } footer: {
                // A minimum height so the layout doesn't jump between one-
                // and two-line explanations as the selection changes.
                SettingsFooter(settings.theme.explanation)
                    .frame(minHeight: 28, alignment: .topLeading)
            }

            Section("Interaction") {
                Toggle("Expand when the pointer rests on the island", isOn: $settings.expandOnHover)

                Slider(value: hoverDelay, in: 0...800) {
                    Text("Delay")
                } minimumValueLabel: {
                    Text("Short")
                } maximumValueLabel: {
                    Text("Long")
                }
                .disabled(!settings.expandOnHover)

                Toggle("Bounce the island when something arrives", isOn: $settings.animateArrivals)
            }

            Section {
                Toggle(
                    "Show an island on displays without a notch",
                    isOn: $settings.showOnNotchlessDisplays
                )
            } header: {
                Text("Displays")
            } footer: {
                SettingsFooter("Applies to external displays and Macs without a camera housing. Takes effect the next time Ledge opens.")
            }

            Section {
                Toggle("Open Ledge at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Reset All Settings…", role: .destructive) {
                    confirmingReset = true
                }
                .confirmationDialog(
                    "Reset All Settings?",
                    isPresented: $confirmingReset
                ) {
                    Button("Reset All Settings", role: .destructive) {
                        settings.resetToDefaults()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This returns every setting, module, and customization to its defaults. You can't undo this.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 700)
    }

    /// The theme cards, three up. Selection is a tinted fill that physically
    /// slides between cells via matched geometry.
    private var themeGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            ForEach(IslandThemeID.allCases, id: \.self) { id in
                ThemeCard(
                    id: id,
                    isSelected: settings.theme == id,
                    sample: themeSample,
                    ns: themeNS
                ) {
                    withAnimation(.smooth(duration: 0.32)) {
                        settings.theme = id
                    }
                }
            }
        }
    }

    /// Quantized in the binding rather than with `step:` — a stepped slider
    /// draws a 41-tick comb across the row, which Apple's timing sliders
    /// (Key Repeat, Double-Click Speed) never do.
    private var hoverDelay: Binding<Double> {
        Binding(
            get: { settings.hoverDelay },
            set: { settings.hoverDelay = ($0 / 20).rounded() * 20 }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            // Revert the toggle rather than leaving it showing a state the
            // system didn't accept.
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = "Ledge couldn't change this setting. \(error.localizedDescription)"
        }
    }
}

/// One selectable theme, shown as the thing it produces: a miniature island
/// rendered in that theme, on a strip of screen.
///
/// Selection is a highlight that physically travels between cards — a glass
/// lozenge morphing through the shared container on macOS 26, a matched-
/// geometry slide on older systems.
private struct ThemeCard: View {
    var id: IslandThemeID
    var isSelected: Bool
    var sample: Activity
    var ns: Namespace.ID
    var select: () -> Void

    @State private var isHovering = false

    private var style: ActivityStyle {
        ActivityStyle.resolve(sample, appearance: nil)
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 7) {
                IslandPreviewStage {
                    // The full preview is ~330pt wide; thumbnail it so three
                    // cards fit side by side. scaleEffect doesn't change
                    // layout size, so the frame after it does the fitting.
                    IslandStylePreview(activity: sample, style: style)
                        .scaleEffect(0.42, anchor: .top)
                        .frame(width: 140, height: 18)
                }
                .islandTheme(.preset(id))

                Text(id.label)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)
            }
            .padding(7)
            .background { selectionBackground }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(isHovering ? 0.25 : 0.12),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(isHovering && !isSelected ? 1.015 : 1)
        }
        .buttonStyle(ThemeCardPressStyle())
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.18)) { isHovering = hovering }
        }
        .accessibilityLabel(Text(id.label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // No glass here, on evidence rather than taste: an in-window glassEffect
    // lozenge behind the card blurred the card's own preview into soup in
    // Dark Mode. A traveling tinted fill communicates the same selection
    // without eating the thing being selected.
    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
                .matchedGeometryEffect(id: "theme-selection", in: ns)
        }
    }
}

/// Press feedback for the theme cards: quick in, springy out.
private struct ThemeCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(
                configuration.isPressed ? IslandMotion.pressIn : IslandMotion.pressRelease,
                value: configuration.isPressed
            )
    }
}

// MARK: - Modules

struct ModuleSettings: View {
    @Bindable var settings: LedgeSettings
    var session: SettingsSession
    var modules: () -> [ModuleInfo]
    var onToggle: (String, Bool) -> Void
    var onGrant: (String) async -> Bool

    @State private var editing: ModuleInfo?
    @State private var granting: String?

    var body: some View {
        // Read the revisions so @Observable registers dependencies on state
        // that actually lives in UserDefaults. This replaces the old `.id(...)`
        // identity reset, which rebuilt the whole Form — and its scroll
        // position — on every slider release in the customization sheet.
        let _ = settings.moduleRevision
        let _ = settings.appearanceRevision
        let all = modules()

        Form {
            ForEach(ModuleGroup.allCases, id: \.self) { group in
                let members = all.filter { $0.group == group }
                if !members.isEmpty {
                    if group == ModuleGroup.allCases.last {
                        Section {
                            ForEach(members) { row($0) }
                        } header: {
                            Text(group.title)
                        } footer: {
                            SettingsFooter("Turn off anything you don't want on the island. Dimmed modules aren't available on this Mac, or Ledge doesn't have permission to use them.")
                        }
                    } else {
                        Section(group.title) {
                            ForEach(members) { row($0) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 600)
        .sheet(item: $editing) { module in
            ModuleCustomizationSheet(module: module, settings: settings) {
                editing = nil
            }
        }
        .onAppear { openRequestedCustomizer() }
        .onChange(of: session.customizing) { _, _ in openRequestedCustomizer() }
    }

    private func summaryLine(_ module: ModuleInfo) -> String {
        if !module.isAvailable {
            return module.permission == .denied
                ? "Access was declined. Grant it in System Settings, then relaunch Ledge."
                : "Not available on this Mac"
        }
        return module.summary
    }

    /// The explicit gesture the one-and-done permission rule waits for: a
    /// module that still needs its system permission gets a Grant Access
    /// link; one that was declined gets the road to System Settings.
    @ViewBuilder
    private func permissionAffordance(_ module: ModuleInfo, isEnabled: Bool) -> some View {
        if module.isAvailable, isEnabled, module.permission == .needsRequest {
            Button {
                granting = module.id
                Task { @MainActor in
                    _ = await onGrant(module.id)
                    granting = nil
                }
            } label: {
                if granting == module.id {
                    Text("Waiting for permission…")
                        .font(.caption)
                } else {
                    Text("Grant Access…")
                        .font(.caption)
                }
            }
            .buttonStyle(.link)
            .disabled(granting != nil)
        } else if module.permission == .denied {
            Button("Open System Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    /// Honours `ledge settings --customize <id>` whether the pane is being
    /// shown fresh or is already on screen.
    private func openRequestedCustomizer() {
        guard let id = session.customizing else { return }
        session.customizing = nil
        editing = modules().first { $0.id == id }
    }

    private func row(_ module: ModuleInfo) -> some View {
        let appearance = settings.appearance(for: module.id)
        let isEnabled = settings.isModuleEnabled(module.id)

        return HStack(spacing: 10) {
            // The chip dims and desaturates with the switch, so cause and
            // effect read as one gesture.
            ModuleIconChip(module: module, appearance: appearance)
                .opacity(isEnabled || !module.isAvailable ? 1 : 0.4)
                .saturation(isEnabled || !module.isAvailable ? 1 : 0)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(module.name)
                        .foregroundStyle(isEnabled || !module.isAvailable ? .primary : .secondary)
                    if !appearance.isDefault {
                        CustomizedBadge()
                            .transition(BlurReplaceTransition(configuration: .downUp)
                                .combined(with: ScaleTransition(0.85)))
                    }
                }
                .animation(.snappy(duration: 0.25), value: appearance.isDefault)
                Text(summaryLine(module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                permissionAffordance(module, isEnabled: isEnabled)
            }

            Spacer()

            InfoButton(disabled: !module.isAvailable || !isEnabled) {
                editing = module
            }

            Toggle(module.name, isOn: Binding(
                get: { settings.isModuleEnabled(module.id) },
                set: { newValue in
                    withAnimation(.smooth(duration: 0.25)) {
                        onToggle(module.id, newValue)
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .disabled(!module.isAvailable)
        }
        .disabled(!module.isAvailable)
    }
}

/// The "this row has more settings" affordance, filling on hover the way
/// System Settings' own info buttons acknowledge the pointer.
private struct InfoButton: View {
    var disabled: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: hovering && !disabled ? "info.circle.fill" : "info.circle")
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(hovering && !disabled ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help("Color, size, and position")
        .disabled(disabled)
        .onHover { isIn in
            withAnimation(.snappy(duration: 0.15)) { hovering = isIn }
        }
    }
}

/// The module's own mark, drawn white on its effective tint — the System
/// Settings row grammar, spoken in Ledge's glyph family. The chip doubles as
/// the color swatch: a tint override is visible at a glance. Internal, not
/// private: the customization sheet reuses it as a live header readout.
struct ModuleIconChip: View {
    @Environment(\.islandTheme) private var theme
    var module: ModuleInfo
    var appearance: ModuleAppearance

    private var sample: Activity { ModulePreviewSample.activity(for: module.id) }

    private var fill: Color {
        guard module.isAvailable else { return Color(nsColor: .quaternaryLabelColor) }
        let color = appearance.tint ?? sample.content.tint ?? .accent
        return Color(color)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
            .fill(fill)
            .frame(width: 26, height: 26)
            .overlay { mark }
    }

    @ViewBuilder
    private var mark: some View {
        let ink: Color = module.isAvailable ? .white : .secondary
        if case .symbol(let name) = sample.content.icon,
           let glyph = LedgeGlyph.mapping(for: name) {
            LedgeGlyphView(glyph: glyph, size: 15, tint: ink, lineWidth: 2.0, weight: .solid)
        } else if case .symbol(let name) = sample.content.icon {
            // Future modules whose mark isn't in the family yet.
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink)
        }
    }
}

// MARK: - Weather

struct WeatherSettings: View {
    @Bindable var settings: LedgeSettings
    var provider: () -> WeatherProvider?
    @State private var reading: WeatherSnapshot?
    @State private var isChecking = false

    var body: some View {
        Form {
            Section {
                Picker("Show weather", selection: $settings.weatherMode) {
                    ForEach(WeatherMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                SettingsFooter(settings.weatherMode.explanation)
            }

            // Disabled rather than hidden while weather is off: the pane keeps
            // its shape, and dimmed rows say "off" better than absence does.
            Section {
                Picker("Units", selection: $settings.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                Toggle("Notify when rain or snow starts", isOn: $settings.weatherAlerts)
            }
            .disabled(settings.weatherMode == .off)

            Section {
                Picker("Source", selection: $settings.weatherLocationMode) {
                    ForEach(WeatherLocationMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if settings.weatherLocationMode == .manual {
                    TextField("Place name", text: $settings.manualPlaceName)
                    TextField("Latitude", value: $settings.manualLatitude, format: .number)
                    TextField("Longitude", value: $settings.manualLongitude, format: .number)
                }
            } header: {
                Text("Location")
            } footer: {
                SettingsFooter("Your coordinates are sent to Open-Meteo to look up conditions, and nowhere else.")
            }
            .disabled(settings.weatherMode == .off)

            Section {
                HStack {
                    if let reading {
                        HStack(spacing: 6) {
                            // The island's own weather mark, not a generic
                            // symbol — the readout should draw exactly what
                            // the island would.
                            ActivityIconView(
                                icon: .symbol(reading.condition.symbol(isDay: reading.isDay)),
                                size: 15,
                                tint: Color(nsColor: .secondaryLabelColor)
                            )
                            Text("\(reading.condition.summary), \(Int(reading.temperature.rounded()))\(settings.temperatureUnit.suffix)")
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(.secondary)
                        .transition(BlurReplaceTransition(configuration: .downUp))
                    }
                    Spacer()
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .transition(BlurReplaceTransition(configuration: .downUp))
                    } else {
                        Button("Check Now") { checkNow() }
                            .disabled(provider() == nil)
                            .transition(BlurReplaceTransition(configuration: .downUp))
                    }
                }
                .animation(.smooth(duration: 0.22), value: isChecking)
                .animation(.smooth(duration: 0.22), value: reading)
            } footer: {
                SettingsFooter("Weather data comes from Open-Meteo. No account or API key required.")
            }
            .disabled(settings.weatherMode == .off)
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 500)
        .onAppear { reading = provider()?.latest }
    }

    private func checkNow() {
        guard let provider = provider() else { return }
        isChecking = true
        Task { @MainActor in
            reading = await provider.refresh()
            isChecking = false
        }
    }
}

// MARK: - About

struct AboutSettings: View {
    var cliPath: String
    @State private var copied = false

    private var version: String? {
        guard let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return nil }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    /// The product's identity is a drawn object one tab away — so About is
    /// anchored by the island itself, rendered in the user's own theme.
    private var identitySample: Activity {
        Activity(
            id: "preview.about",
            content: ActivityContent(
                title: "Ledge",
                subtitle: "Dynamic Island for macOS",
                icon: .symbol("sparkles"),
                tint: .accent
            ),
            module: "about"
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    IslandPreviewStage {
                        IslandStylePreview(
                            activity: identitySample,
                            style: ActivityStyle.resolve(identitySample, appearance: nil)
                        )
                    }
                    .padding(.bottom, 8)

                    Text("Ledge")
                        .font(.title2.weight(.semibold))
                    if let version {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("A Dynamic Island for macOS, and a live-activity API for everything else on your Mac.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                        .padding(.top, 6)
                    Text("MIT licensed. No account, no telemetry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                HStack {
                    Text(installCommand)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installCommand, forType: .string)
                        copied = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        // The fixed width stops the button jumping between
                        // the two labels; each swaps through a blur.
                        ZStack {
                            if copied {
                                Text("Copied")
                                    .transition(BlurReplaceTransition(configuration: .downUp))
                            } else {
                                Text("Copy")
                                    .transition(BlurReplaceTransition(configuration: .downUp))
                            }
                        }
                        .frame(minWidth: 52)
                        .animation(.smooth(duration: 0.2), value: copied)
                    }
                }
            } header: {
                Text("Command Line")
            } footer: {
                SettingsFooter("Puts the ledge command on your PATH, for posting activities from scripts and Shortcuts.")
            }

            Section("API") {
                LabeledContent("Socket") {
                    Text(LedgeSocket.path)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section {
                Link("GitHub", destination: Self.repoURL)
                Link("Report an Issue", destination: Self.repoURL.appendingPathComponent("issues"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 560)
    }

    private static let repoURL = URL(string: "https://github.com/BoatAngle/Ledge")!

    private var installCommand: String {
        "sudo ln -sf \"\(cliPath)\" /usr/local/bin/ledge"
    }
}
