import AppKit
import IsletCore
import IsletModules
import IsletUI
import ServiceManagement
import SwiftUI

// The design boundary for this window: the window CHROME speaks macOS —
// SF Symbols in the toolbar tabs, info.circle affordances, standard buttons —
// while anything DEPICTING island content speaks Islet: glyph chips, island
// previews, the weather readout. Don't convert the chrome to the glyph family,
// and don't let SF Symbols stand in for what the island would draw.

/// What the Modules pane needs to know about a provider.
struct ModuleInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var isAvailable: Bool
    var summary: String
    var group: ModuleGroup = .system
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

/// The settings window's panes, addressable by name so `islet settings
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
    @Bindable var settings: IsletSettings
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
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    ForEach(IslandThemeID.allCases, id: \.self) { id in
                        ThemeCard(
                            id: id,
                            isSelected: settings.theme == id,
                            sample: themeSample
                        ) {
                            settings.theme = id
                        }
                    }
                }
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
                SettingsFooter("Applies to external displays and Macs without a camera housing. Takes effect the next time Islet opens.")
            }

            Section {
                Toggle("Open Islet at login", isOn: $launchAtLogin)
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
            loginError = "Islet couldn't change this setting. \(error.localizedDescription)"
        }
    }
}

/// One selectable theme, shown as the thing it produces: a miniature island
/// rendered in that theme, on a strip of screen.
private struct ThemeCard: View {
    var id: IslandThemeID
    var isSelected: Bool
    var sample: Activity
    var select: () -> Void

    private var style: ActivityStyle {
        ActivityStyle.resolve(sample, appearance: nil)
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 7) {
                IslandPreviewStage {
                    // The full preview is ~330pt wide; thumbnail it so two
                    // cards fit side by side. scaleEffect doesn't change
                    // layout size, so the frame after it does the fitting.
                    IslandStylePreview(activity: sample, style: style)
                        .scaleEffect(0.55, anchor: .top)
                        .frame(width: 184, height: 24)
                }
                .islandTheme(.preset(id))

                Text(id.label)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
            .padding(7)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(id.label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Modules

struct ModuleSettings: View {
    @Bindable var settings: IsletSettings
    var session: SettingsSession
    var modules: () -> [ModuleInfo]
    var onToggle: (String, Bool) -> Void

    @State private var editing: ModuleInfo?

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
                            SettingsFooter("Turn off anything you don't want on the island. Dimmed modules aren't available on this Mac, or Islet doesn't have permission to use them.")
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

    /// Honours `islet settings --customize <id>` whether the pane is being
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
            ModuleIconChip(module: module, appearance: appearance)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(module.name)
                    if !appearance.isDefault {
                        CustomizedBadge()
                    }
                }
                Text(module.isAvailable ? module.summary : "Not available on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                editing = module
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Color, size, and position")
            .disabled(!module.isAvailable || !isEnabled)

            Toggle(module.name, isOn: Binding(
                get: { settings.isModuleEnabled(module.id) },
                set: { onToggle(module.id, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .disabled(!module.isAvailable)
        }
        .disabled(!module.isAvailable)
    }
}

/// The module's own mark, drawn white on its effective tint — the System
/// Settings row grammar, spoken in Islet's glyph family. The chip doubles as
/// the color swatch: a tint override is visible at a glance.
private struct ModuleIconChip: View {
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
           let glyph = IsletGlyph.mapping(for: name) {
            IsletGlyphView(glyph: glyph, size: 15, tint: ink, lineWidth: 2.0, weight: .solid)
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
    @Bindable var settings: IsletSettings
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
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Check Now") { checkNow() }
                            .disabled(provider() == nil)
                    }
                }
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
                title: "Islet",
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

                    Text("Islet")
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
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installCommand, forType: .string)
                        copied = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                }
            } header: {
                Text("Command Line")
            } footer: {
                SettingsFooter("Puts the islet command on your PATH, for posting activities from scripts and Shortcuts.")
            }

            Section("API") {
                LabeledContent("Socket") {
                    Text(IsletSocket.path)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 540)
    }

    private var installCommand: String {
        "sudo ln -sf \"\(cliPath)\" /usr/local/bin/islet"
    }
}
