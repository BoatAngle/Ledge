import AppKit
import IsletCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Files parked on the island.
///
/// Drag anything to the notch and it lands here: the island becomes a staging
/// area you can drag back out of, AirDrop from, or reveal in Finder. It holds
/// references only — nothing is copied, moved, or deleted.
@MainActor
@Observable
public final class DropShelf {
    public private(set) var files: [URL] = []
    /// True while a drag is hovering, so the island can open a target.
    public private(set) var isTargeted = false

    private weak var store: ActivityStore?
    private var actionObserver: NSObjectProtocol?

    public static let activityID = "system.dropShelf"
    private static let hintID = "system.dropShelf.hint"

    public init() {}

    public func attach(to store: ActivityStore) {
        self.store = store
        actionObserver = NotificationCenter.default.addObserver(
            forName: .isletActionInvoked,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let id = note.userInfo?["actionID"] as? String else { return }
            MainActor.assumeIsolated { self?.handleAction(id) }
        }
    }

    public func detach() {
        if let actionObserver { NotificationCenter.default.removeObserver(actionObserver) }
        actionObserver = nil
        store?.end(id: Self.activityID)
        store?.end(id: Self.hintID)
        store = nil
    }

    // MARK: - Drag lifecycle

    public func dragEntered() {
        isTargeted = true
        showHint()
    }

    /// Called continuously while a drag hovers, which keeps the hint's expiry
    /// pushed forward.
    ///
    /// The hint is `.transient` rather than `.ongoing` on purpose: it sits at
    /// `.critical` priority, and if AppKit ever fails to deliver
    /// `draggingExited` — which happens when a drag ends outside our window —
    /// an ongoing activity at that priority would wedge the island permanently.
    /// Expiring on its own makes the failure self-healing.
    public func dragUpdated() {
        guard isTargeted else { return }
        showHint()
    }

    private func showHint() {
        store?.present(
            Activity(
                id: Self.hintID,
                source: "system",
                kind: .transient,
                priority: .critical,
                content: ActivityContent(
                    title: files.isEmpty ? "Drop to hold" : "Add to shelf",
                    subtitle: "Release to keep these here",
                    icon: .symbol("tray.and.arrow.down.fill"),
                    tint: .accent
                ),
                nativeView: .dropZone,
                expiresAt: Date().addingTimeInterval(1.0),
                isExpandable: false
            )
        )
    }

    public func dragExited() {
        guard isTargeted else { return }
        isTargeted = false
        store?.end(id: Self.hintID)
    }

    public func accept(_ urls: [URL]) {
        dragExited()
        guard !urls.isEmpty else { return }
        // De-duplicate: dropping the same file twice shouldn't stack up.
        for url in urls where !files.contains(url) {
            files.append(url)
        }
        publish()
    }

    public func remove(_ url: URL) {
        files.removeAll { $0 == url }
        publish()
    }

    public func clear() {
        files.removeAll()
        store?.end(id: Self.activityID)
    }

    // MARK: - Presentation

    private func publish() {
        guard let store else { return }
        guard !files.isEmpty else {
            store.end(id: Self.activityID)
            return
        }

        store.present(
            Activity(
                id: Self.activityID,
                source: "system",
                kind: .ongoing,
                priority: .high,
                content: ActivityContent(
                    title: files.count == 1
                        ? files[0].lastPathComponent
                        : "\(files.count) files",
                    subtitle: "On the shelf",
                    icon: .symbol("tray.full.fill"),
                    tint: .accent,
                    actions: [
                        ActivityAction(id: "shelf.airdrop", title: "AirDrop", symbol: "airplayaudio"),
                        ActivityAction(id: "shelf.reveal", title: "Reveal", symbol: "folder"),
                        ActivityAction(id: "shelf.clear", title: "Clear", symbol: "xmark", isDestructive: true),
                    ]
                ),
                nativeView: .dropZone,
                isExpandable: true
            )
        )
    }

    private func handleAction(_ id: String) {
        switch id {
        case "shelf.airdrop": airDrop()
        case "shelf.reveal": NSWorkspace.shared.activateFileViewerSelecting(files)
        case "shelf.clear": clear()
        default: return
        }
    }

    /// Hands the shelf to AirDrop.
    ///
    /// `NSSharingService(named: .sendViaAirDrop)` is the direct route but has
    /// been unreliable across releases, so a picker anchored to the island is
    /// the fallback rather than a dead button.
    public func airDrop(anchor: NSView? = nil) {
        guard !files.isEmpty else { return }
        if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: files) {
            service.perform(withItems: files)
            return
        }
        guard let anchor else { return }
        let picker = NSSharingServicePicker(items: files)
        picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
    }
}

/// The expanded panel for the shelf: a real file list you can drag back out of.
public struct DropShelfView: View {
    public var shelf: DropShelf

    public init(shelf: DropShelf) {
        self.shelf = shelf
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(IslandPalette.defaultTint)
                Text(shelf.files.count == 1 ? "1 file" : "\(shelf.files.count) files")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IslandPalette.primaryText)
                Spacer(minLength: 0)
                Text("Drag out to move")
                    .font(.system(size: 10))
                    .foregroundStyle(IslandPalette.tertiaryText)
            }

            VStack(spacing: 4) {
                ForEach(shelf.files.prefix(4), id: \.self) { url in
                    fileRow(url)
                        .transition(.blurReplace)
                }
                if shelf.files.count > 4 {
                    Text("+ \(shelf.files.count - 4) more")
                        .font(.system(size: 10))
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.blurReplace)
                }
            }
            // Rows used to teleport in an otherwise fully-animated panel;
            // the island's height rides this list through the measured-height
            // animation on the root.
            .animation(IslandMotion.content, value: shelf.files)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ExpandedHeightKey.self, value: proxy.size.height)
            }
        )
    }

    private func fileRow(_ url: URL) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandPalette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.deletingLastPathComponent().lastPathComponent)
                    .font(.system(size: 9))
                    .foregroundStyle(IslandPalette.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                shelf.remove(url)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(IslandPalette.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        // The point of a shelf: pick things back up again.
        .draggable(url) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 32, height: 32)
        }
    }
}
