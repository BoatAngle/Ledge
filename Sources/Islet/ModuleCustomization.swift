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

/// Colour, size, and placement for one module, with a live island above the
/// controls so every change is visible as it's made.
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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    preview
                    colorSection
                    sizeSection
                    positionSection
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 460, height: 560)
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
                Text("Customised")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button("Reset to Default") {
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

    // MARK: Sections

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Preview")
            IslandPreviewStage {
                IslandStylePreview(activity: sample, style: style)
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Colour")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                swatch(nil, label: "Default")
                ForEach(IsletColor.paletteOrder, id: \.self) { name in
                    if let color = IsletColor.named[name] {
                        swatch(color, label: name)
                    }
                }
            }

            HStack {
                ColorPicker("Custom", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                Text("Custom colour")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .onChange(of: customColor) { _, newValue in
                guard let converted = IsletColor(newValue) else { return }
                appearance.tint = converted
                commit()
            }
        }
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
                    // "Default" reads as the module's own colour, struck through.
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
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Size")
            HStack(spacing: 12) {
                Image(systemName: "textformat.size.smaller")
                    .foregroundStyle(.secondary)
                Slider(
                    value: $appearance.scale,
                    in: ModuleAppearance.scaleRange,
                    step: 0.05
                ) { editing in
                    if !editing { commit() }
                }
                Image(systemName: "textformat.size.larger")
                    .foregroundStyle(.secondary)
                Text("\(Int(appearance.scale * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            Text("Scales this module's glyph and readout. The island itself keeps its size so it still lines up with the camera.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Position")
            Picker("Position", selection: $appearance.slot) {
                ForEach(ModuleSlot.allCases, id: \.self) { slot in
                    Text(slot.label).tag(slot)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: appearance.slot) { _, _ in commit() }

            Text(appearance.slot.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("Ordering")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(appearance.priorityOffset) },
                        set: { appearance.priorityOffset = Int($0) }
                    ),
                    in: Self.orderingRange,
                    step: 25
                ) { editing in
                    if !editing { commit() }
                }
                Text(orderingLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 68, alignment: .trailing)
            }
        }
    }

    private static let orderingRange =
        Double(ModuleAppearance.priorityRange.lowerBound)...Double(ModuleAppearance.priorityRange.upperBound)

    private var orderingLabel: String {
        switch appearance.priorityOffset {
        case 0: return "Normal"
        case ..<0: return "Lower"
        default: return "Higher"
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
    }

    private func commit() {
        settings.setAppearance(appearance, for: module.id)
    }
}
