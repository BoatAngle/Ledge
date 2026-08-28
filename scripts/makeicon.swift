import AppKit
import SwiftUI

// The island's own silhouette, hanging from the icon's top edge the way it
// hangs from the screen's — the app icon is a picture of the product.
struct NotchShape: Shape {
    var topFillet: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let fillet = max(0, min(topFillet, rect.width / 2, rect.height))
        let bodyWidth = rect.width - fillet * 2
        let radius = max(0, min(bottomRadius, bodyWidth / 2, rect.height - fillet))
        let left = rect.minX + fillet
        let right = rect.maxX - fillet
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + fillet),
                          control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: rect.maxY),
                          control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - radius),
                          control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + fillet))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct Icon: View {
    // Big Sur-era icon grid: 1024 canvas, content in an ~832pt rounded rect.
    let canvas: CGFloat = 1024
    let plate: CGFloat = 832
    let corner: CGFloat = 186

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.15, blue: 0.23),
                            Color(red: 0.05, green: 0.06, blue: 0.10),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    // The preview stage's off-axis glow, so the black island
                    // has something to be black against.
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.38, green: 0.42, blue: 0.60).opacity(0.70), .clear],
                                center: UnitPoint(x: 0.74, y: 0.05),
                                startRadius: 30,
                                endRadius: 700
                            )
                        )
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.52, green: 0.38, blue: 0.33).opacity(0.30), .clear],
                                center: UnitPoint(x: 0.12, y: 0.95),
                                startRadius: 30,
                                endRadius: 540
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 3)
                }
                .frame(width: plate, height: plate)

            // The island: body + detached circle, in the split state that is
            // the product's signature.
            // The pill dead-centered on the plate; the circle hangs to its
            // right INSIDE the plate, the way the real island carries its
            // second activity.
            ZStack(alignment: .top) {
                NotchShape(topFillet: 46, bottomRadius: 86)
                    .fill(Color.black)
                    .frame(width: 460, height: 168)
                NotchShape(topFillet: 46, bottomRadius: 86)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0), location: 0),
                                .init(color: .white.opacity(0), location: 0.5),
                                .init(color: .white.opacity(0.34), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 460, height: 168)
                Circle()
                    .fill(Color.black)
                    .overlay {
                        Circle().stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0), location: 0),
                                    .init(color: .white.opacity(0.30), location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 4
                        )
                    }
                    .frame(width: 112, height: 112)
                    .offset(x: 230 + 28 + 56)
            }
            .offset(y: (canvas - plate) / 2)
            .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
        }
        .frame(width: canvas, height: canvas)
    }
}

@MainActor
func main() {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("wrote \(CommandLine.arguments[1])")
}
MainActor.assumeIsolated { main() }
