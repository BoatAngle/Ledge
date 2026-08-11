import AppKit
import IsletCore
import IsletModules
import ServiceManagement
import SwiftUI

/// What the Modules tab needs to know about a provider.
struct ModuleInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var isAvailable: Bool
    var summary: String
}

/// The settings window's sections, addressable by name so `islet settings
/// --tab weather` can jump straight to one.
enum SettingsTab: String, CaseIterable {
    case general, modules, weather, about

    static func named(_ raw: String?) -> SettingsTab {
        guard let raw else { return .general }
        return SettingsTab(rawValue: raw.lowercased()) ?? .general
    }
}

struct SettingsView: View {
    @Bindable var settings: IsletSettings
    @State var tab: SettingsTab = .general
    var modules: [ModuleInfo]
    var weatherProvider: WeatherProvider?
    var onToggleModule: (String, Bool) -> Void
    var cliPath: String

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            ModuleSettings(
                settings: settings,
                modules: modules,
                onToggle: onToggleModule
            )
            .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            .tag(SettingsTab.modules)

            WeatherSettings(settings: settings, provider: weatherProvider)
                .tabItem { Label("Weather", systemImage: "cloud.sun") }
                .tag(SettingsTab.weather)

            AboutSettings(cliPath: cliPath)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 540, height: 440)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var settings: IsletSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch Islet at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Interaction") {
                Toggle("Expand when the cursor rests on the island", isOn: $settings.expandOnHover)

                HStack {
                    Text("Hover delay")
                    Slider(value: $settings.hoverDelay, in: 0...800, step: 20)
                        .disabled(!settings.expandOnHover)
                    Text("\(Int(settings.hoverDelay)) ms")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }

                Toggle("Bounce the island when something arrives", isOn: $settings.animateArrivals)
            }

            Section("Displays") {
                Toggle(
                    "Draw a virtual island on displays without a notch",
                    isOn: $settings.showOnNotchlessDisplays
                )
                Text("Applies to external monitors and Macs older than 2021. Takes effect next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset all settings", role: .destructive) {
                    settings.resetToDefaults()
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        }
        .formStyle(.grouped)
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
            loginError = "Couldn't change this: \(error.localizedDescription)"
        }
    }
}

// MARK: - Modules

private struct ModuleSettings: View {
    @Bindable var settings: IsletSettings
    var modules: [ModuleInfo]
    var onToggle: (String, Bool) -> Void

    var body: some View {
        Form {
            Section {
                ForEach(modules) { module in
                    row(module)
                }
            } header: {
                Text("Turn off anything you don't want on the island.")
            } footer: {
                Text("Greyed-out modules aren't supported on this Mac, or a permission was declined.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // `moduleRevision` is the observable stand-in for enablement, which
        // lives in UserDefaults rather than in a stored property.
        .id(settings.moduleRevision)
    }

    private func row(_ module: ModuleInfo) -> some View {
        Toggle(isOn: Binding(
            get: { settings.isModuleEnabled(module.id) },
            set: { onToggle(module.id, $0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(module.name)
                Text(module.isAvailable ? module.summary : "Not available on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!module.isAvailable)
    }
}

// MARK: - Weather

private struct WeatherSettings: View {
    @Bindable var settings: IsletSettings
    var provider: WeatherProvider?
    @State private var reading: WeatherSnapshot?

    var body: some View {
        Form {
            Section {
                Picker("Show weather", selection: $settings.weatherMode) {
                    ForEach(WeatherMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.weatherMode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.weatherMode != .off {
                Section {
                    Picker("Units", selection: $settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    Toggle("Tell me when rain or snow starts", isOn: $settings.weatherAlerts)
                }

                Section("Location") {
                    Picker("Location", selection: $settings.weatherLocationMode) {
                        ForEach(WeatherLocationMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()

                    if settings.weatherLocationMode == .manual {
                        TextField("Place name", text: $settings.manualPlaceName)
                        HStack {
                            TextField("Latitude", value: $settings.manualLatitude, format: .number)
                            TextField("Longitude", value: $settings.manualLongitude, format: .number)
                        }
                    } else {
                        Text("Your coordinates are sent to Open-Meteo to look up conditions, and nowhere else.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Button("Check now") {
                            provider?.showNow()
                            // Give the fetch a moment, then reflect it here too.
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2))
                                reading = provider?.latest
                            }
                        }
                        Spacer()
                        if let reading {
                            Label(
                                "\(reading.condition.summary), \(Int(reading.temperature.rounded()))\(settings.temperatureUnit.suffix)",
                                systemImage: reading.condition.symbol(isDay: reading.isDay)
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Weather comes from Open-Meteo, which needs no account or API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reading = provider?.latest }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var cliPath: String
    @State private var copied = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Islet \(version)")
                        .font(.title3.weight(.semibold))
                    Text("A Dynamic Island for macOS, and a live-activity API for everything else on your Mac.")
                        .foregroundStyle(.secondary)
                    Text("MIT licensed. No account, no telemetry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Command line") {
                Text("Put `islet` on your PATH:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }

            Section("API") {
                LabeledContent("Socket", value: IsletSocket.path)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private var installCommand: String {
        "sudo ln -sf \"\(cliPath)\" /usr/local/bin/islet"
    }
}
