import AppKit
import IsletUI
import SwiftUI

/// Renders the whole custom glyph family to a PNG.
///
/// Kept in the app rather than a test: an icon family is maintained by looking
/// at it, and a contact sheet is the only way to see the set as a set — whether
/// the weights match, whether the optical sizes agree, whether two marks read
/// as the same thing. Run with `Islet.app/Contents/MacOS/Islet --glyph-sheet out.png`.
@MainActor
enum GlyphSheet {
    static func render(to path: String) {
        let columns = 5
        let cell: CGFloat = 132
        let glyph: CGFloat = 44
        let rows = (IsletGlyph.allCases.count + columns - 1) / columns

        let sheet = VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < IsletGlyph.allCases.count {
                            let item = IsletGlyph.allCases[index]
                            VStack(spacing: 7) {
                                // Both weights together: the only way to see
                                // whether a solid mark still reads as the same
                                // idea as its outline.
                                HStack(spacing: 10) {
                                    IsletGlyphView(
                                        glyph: item, size: glyph, tint: .white,
                                        lineWidth: 1.9, weight: .outline
                                    )
                                    IsletGlyphView(
                                        glyph: item, size: glyph, tint: .white,
                                        lineWidth: 2.1, weight: .solid
                                    )
                                }
                                Text(item.rawValue)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(1)
                            }
                            .frame(width: cell, height: cell)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.06))

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("Couldn't render the glyph sheet.\n".utf8))
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
