import IsletCore
import IsletUI
import SwiftUI

/// Representative activities for the Settings preview.
///
/// Each mirrors what its module actually posts — same glyph, same trailing
/// treatment, same native view — so tuning against the preview tunes against
/// the real thing rather than a stand-in that happens to look similar.
enum ModulePreviewSample {
    static func activity(for identifier: String) -> Activity {
        let content: ActivityContent
        let native: NativeViewKind?

        switch identifier {
        case "system.media":
            content = ActivityContent(
                title: "Midnight City", subtitle: "M83",
                icon: .symbol("music.note"), tint: IsletColor(red: 0.98, green: 0.19, blue: 0.35)
            )
            native = .media
        case "system.timer":
            content = ActivityContent(
                title: "25 minute timer", subtitle: "Timer",
                icon: .symbol("timer"), tint: .orange,
                countdownTarget: Date().addingTimeInterval(1_500)
            )
            native = .timer
        case "system.calendar":
            content = ActivityContent(
                title: "Design review", subtitle: "Upcoming",
                icon: .symbol("video.fill"), tint: .blue,
                countdownTarget: Date().addingTimeInterval(480)
            )
            native = .calendar
        case "system.downloads":
            content = ActivityContent(
                title: "ventura.dmg", subtitle: "Downloading — 214 MB",
                icon: .symbol("arrow.down.circle.fill"), tint: .teal,
                progress: ActivityProgress()
            )
            native = .download
        case "system.weather":
            content = ActivityContent(
                title: "Partly cloudy", subtitle: "San Francisco",
                icon: .symbol("cloud.sun.fill"), trailingText: "68°", tint: .cyan
            )
            native = .weather
        case "system.battery":
            content = ActivityContent(
                title: "Charging", subtitle: "1h 12m until full",
                icon: .symbol("bolt.fill"), trailingText: "84%", tint: .green
            )
            native = .battery
        case "system.volume":
            content = ActivityContent(
                title: "Volume", icon: .symbol("speaker.wave.2.fill"),
                trailingText: "60%", tint: .cyan,
                progress: ActivityProgress(fraction: 0.6)
            )
            native = .volume
        case "system.brightness":
            content = ActivityContent(
                title: "Brightness", icon: .symbol("sun.max.fill"),
                trailingText: "75%", tint: .yellow,
                progress: ActivityProgress(fraction: 0.75)
            )
            native = .brightness
        case "system.focus":
            content = ActivityContent(
                title: "Do Not Disturb", subtitle: "Notifications silenced",
                icon: .symbol("moon.fill"), tint: .indigo
            )
            native = .focus
        case "system.capsLock":
            content = ActivityContent(
                title: "Caps Lock On", icon: .symbol("capslock.fill"),
                trailingText: "ON", tint: .green
            )
            native = .capsLock
        case "system.privacy":
            content = ActivityContent(
                title: "Microphone in use", icon: .symbol("mic.fill"), tint: .orange
            )
            native = .privacy
        default:
            content = ActivityContent(
                title: "Activity", icon: .symbol("sparkles"), tint: .accent
            )
            native = nil
        }

        return Activity(
            id: "preview.\(identifier)",
            content: content,
            nativeView: native,
            module: identifier
        )
    }
}

/// Color, size, and placement for one module, with a live island above the
/// controls so every change is visible as it's made.
///
/// The middle is a grouped Form like every pane behind it — the sheet must
/// read as part of the same window, not a different app. Its fixed height must
/// stay comfortably under the Modules pane height (600), or the sheet hangs
/// past the window's bottom edge and reads as broken.
struct ModuleCustomizationSheet: View {
    var module: ModuleInfo
    @Bindable var settings: IsletSettings
    var onDone: () -> Void

    @State private var appearance: ModuleAppearance = .default
    @State private var customColor: Color = .blue

    private var sample: Activity { ModulePreviewSample.activity(for: module.id) }
    private var style: ActivityStyle {
        ActivityStyle.resolve(sample, appearance: appearance)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            // The preview is pinned OUTSIDE the scrolling form, the way System
            // Settings pins the wallpaper preview: the controls may scroll, but
            // the thing they change never leaves the screen.
            IslandPreviewStage {
                IslandStylePreview(activity: sample, style: style)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 4)

            Form {
                Section("Color") {
                    swatchGrid
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(value: scale, in: ModuleAppearance.scaleRange) { editing in
                            if !editing { commit() }
                        }
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                        Text("\(Int(appearance.scale * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                } header: {
                    Text("Size")
                } footer: {
                    SettingsFooter("Scales this module's glyph and readout. The island itself keeps its size so it still lines up with the camera.")
                }

                Section {
                    Picker("Position", selection: $appearance.slot) {
                        ForEach(ModuleSlot.allCases, id: \.self) { slot in
                            Text(slot.label).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: appearance.slot) { _, _ in commit() }

                    HStack(spacing: 12) {
                        Text("Priority")
                        Slider(value: priority, in: Self.priorityRange) { editing in
                            if !editing { commit() }
                        }
                        Text(priorityLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                } header: {
                    Text("Position")
                } footer: {
                    SettingsFooter(appearance.slot.explanation)
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(width: 460, height: 580)
        .onExitCommand(perform: onDone)
        .onAppear {
            appearance = settings.appearance(for: module.id)
            customColor = appearance.tint.map(Color.init) ?? .blue
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(module.name).font(.headline)
                Text(module.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !appearance.isDefault {
                CustomizedBadge()
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button("Restore Defaults") {
                appearance = .default
                commit()
            }
            .disabled(appearance.isDefault)
            Spacer()
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: Color

    /// Default, the twelve palette colors, and the custom well — one grid,
    /// two rows, no separate "custom" row hanging beneath.
    private var swatchGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(30), spacing: 10), count: 8),
            spacing: 10
        ) {
            swatch(nil, label: "Default")
            ForEach(IsletColor.paletteOrder, id: \.self) { name in
                if let color = IsletColor.named[name] {
                    swatch(color, label: name)
                }
            }
            ColorPicker("Custom color", selection: $customColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 26, height: 26)
                .help("Custom color")
                .onChange(of: customColor) { _, newValue in
                    guard let converted = IsletColor(newValue) else { return }
                    appearance.tint = converted
                    commit()
                }
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ color: IsletColor?, label: String) -> some View {
        let isSelected = appearance.tint == color
        return Button {
            appearance.tint = color
            commit()
        } label: {
            ZStack {
                if let color {
                    Circle().fill(Color(color))
                } else {
                    // "Default" reads as the module's own color, struck through.
                    Circle()
                        .fill(Color(sample.content.tint ?? .accent))
                        .overlay {
                            Image(systemName: "line.diagonal")
                                .font(.system(size: 16, weight: .light))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                }
            }
            .frame(width: 26, height: 26)
            .overlay {
                Circle().strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                    lineWidth: isSelected ? 2.5 : 0.5
                )
            }
            .help(label.capitalized)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label.capitalized))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Bindings

    /// Both sliders quantize in the binding rather than with `step:`, which
    /// would draw tick combs across the rows.
    private var scale: Binding<Double> {
        Binding(
            get: { appearance.scale },
            set: { appearance.scale = ($0 / 0.05).rounded() * 0.05 }
        )
    }

    private var priority: Binding<Double> {
        Binding(
            get: { Double(appearance.priorityOffset) },
            set: { appearance.priorityOffset = Int(($0 / 25).rounded()) * 25 }
        )
    }

    private static let priorityRange =
        Double(ModuleAppearance.priorityRange.lowerBound)...Double(ModuleAppearance.priorityRange.upperBound)

    private var priorityLabel: String {
        switch appearance.priorityOffset {
        case 0: return "Normal"
        case ..<0: return "Lower"
        default: return "Higher"
        }
    }

    private func commit() {
        settings.setAppearance(appearance, for: module.id)
    }
}
