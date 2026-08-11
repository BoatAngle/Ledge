import AppKit
import IsletCore
import SwiftUI

/// Resolves the four `ActivityIcon` cases into something drawable.
///
/// App icons and files are cached: a download activity updating ten times a
/// second must not hit the filesystem ten times a second.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var images: [String: NSImage] = [:]

    func image(for icon: ActivityIcon) -> NSImage? {
        switch icon {
        case .symbol:
            return nil // Rendered by SwiftUI directly.
        case .bundleIdentifier(let identifier):
            return cached("bundle:\(identifier)") {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
                else { return nil }
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        case .file(let path):
            return cached("file:\(path)") { NSImage(contentsOfFile: path) }
        case .data(let base64):
            // Keyed by a prefix — full base64 strings make poor dictionary keys
            // and album art changes with the track anyway.
            return cached("data:\(base64.prefix(64))#\(base64.count)") {
                guard let data = Data(base64Encoded: base64) else { return nil }
                return NSImage(data: data)
            }
        }
    }

    private func cached(_ key: String, _ make: () -> NSImage?) -> NSImage? {
        if let hit = images[key] { return hit }
        guard let made = make() else { return nil }
        if images.count > 64 { images.removeAll(keepingCapacity: true) }
        images[key] = made
        return made
    }
}

/// Draws an activity's icon at a given size, tinted when it's a symbol.
public struct ActivityIconView: View {
    @Environment(\.islandTheme) private var theme
    public var icon: ActivityIcon?
    public var size: CGFloat
    public var tint: Color

    public init(icon: ActivityIcon?, size: CGFloat, tint: Color = IslandPalette.primaryText) {
        self.icon = icon
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Group {
            switch icon {
            case .symbol(let name):
                // Islet's own family where one exists; Apple's where it doesn't,
                // so an unmapped `--icon symbol:foo` still renders something.
                if let glyph = IsletGlyph.mapping(for: name) {
                    IsletGlyphView(
                        glyph: glyph,
                        size: size,
                        tint: tint,
                        lineWidth: theme.glyphLineWidth
                    )
                } else {
                    Image(systemName: theme.symbolName(name))
                        .font(.system(size: size * 0.72, weight: theme.glyphWeight))
                        .foregroundStyle(tint)
                        .frame(width: size, height: size)
                }
            case .some(let other):
                if let image = IconCache.shared.image(for: other) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                } else {
                    fallback
                }
            case .none:
                fallback
            }
        }
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.22))
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .fill(tint)
                    .frame(width: size * 0.28, height: size * 0.28)
            }
    }
}
