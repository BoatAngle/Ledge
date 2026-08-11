import SwiftUI

/// Islet's own icon family.
///
/// Drawn rather than borrowed. SF Symbols are excellent but they carry Apple's
/// optical conventions, and at 20pt against black they read as *system* icons
/// on someone else's surface. These are built on one geometric grid with a
/// single stroke weight, so the island's marks look like a set rather than a
/// selection.
///
/// Conventions, held across every glyph:
/// - A 24×24 box with the mark living inside 20×20 (2pt optical margin).
/// - Stroked, never filled. Weight comes from the theme, which means the quiet
///   themes get a lighter set for free instead of needing a second family.
/// - Round caps and joins throughout.
/// - Circles run slightly larger than squares of the same nominal size, because
///   they read smaller.
public enum IsletGlyph: String, CaseIterable, Sendable {
    case arrowUp, arrowDown, download, upload
    case musicNote, play, pause, next, previous
    case timer, calendar, video
    case bolt, battery
    case speaker, speakerMute
    case sun, sunLow, moon
    case cloud, cloudSun, cloudMoon, cloudRain, cloudSnow, cloudFog, cloudBolt
    case mic, camera
    case capslock, tray, folder
    case check, cross, sparkle, film, terminal, refresh, gauge, dot

    // MARK: Geometry

    /// The mark, in a 24×24 space scaled to `rect`.
    ///
    /// Returns two paths because several marks are genuinely mixed: a skip
    /// glyph is a solid triangle *and* a stroked bar. Filling one path with
    /// both in it erases the bar, which has no area.
    public func paths(in rect: CGRect) -> (stroke: Path, fill: Path) {
        var path = Path()
        var solid = Path()
        let s = min(rect.width, rect.height) / 24
        let ox = rect.minX + (rect.width - 24 * s) / 2
        let oy = rect.minY + (rect.height - 24 * s) / 2
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        /// Arcs are specified in degrees, clockwise on screen, 0° at 3 o'clock.
        func arc(_ cx: Double, _ cy: Double, _ r: Double, _ from: Double, _ to: Double) {
            path.addArc(
                center: p(cx, cy),
                radius: r * s,
                startAngle: .degrees(from),
                endAngle: .degrees(to),
                clockwise: false
            )
        }
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            path.move(to: p(x1, y1))
            path.addLine(to: p(x2, y2))
        }
        func circle(_ cx: Double, _ cy: Double, _ r: Double) {
            path.addEllipse(in: CGRect(
                x: ox + (cx - r) * s, y: oy + (cy - r) * s,
                width: 2 * r * s, height: 2 * r * s
            ))
        }
        func roundedRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) {
            path.addRoundedRect(
                in: CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s),
                cornerSize: CGSize(width: r * s, height: r * s),
                style: .continuous
            )
        }
        /// Adds a closed, filled polygon — used where a mark wants mass.
        func fillPolygon(_ points: [(Double, Double)]) {
            guard let first = points.first else { return }
            solid.move(to: p(first.0, first.1))
            for point in points.dropFirst() { solid.addLine(to: p(point.0, point.1)) }
            solid.closeSubpath()
        }
        /// A crescent drawn as two bulging curves meeting at the tips.
        ///
        /// Building it from two circle arcs requires solving for where the
        /// circles intersect; placing the tips directly is both easier to
        /// control and easier to read at 20pt.
        func crescent(cx: Double = 12, cy: Double = 12, scale k: Double = 1) {
            let tipX = cx + 2.6 * k, top = cy - 7.6 * k, bottom = cy + 7.6 * k
            path.move(to: p(tipX, top))
            path.addCurve(
                to: p(tipX, bottom),
                control1: p(cx - 6.8 * k, cy - 5.6 * k),
                control2: p(cx - 6.8 * k, cy + 5.6 * k)
            )
            path.addCurve(
                to: p(tipX, top),
                control1: p(cx - 1.4 * k, cy + 4.6 * k),
                control2: p(cx - 1.4 * k, cy - 4.6 * k)
            )
            path.closeSubpath()
        }
        /// Cloud outline shared by the weather glyphs, offset so variants can
        /// sit it higher and leave room for what falls out of it.
        func cloud(_ dy: Double = 0, scale k: Double = 1) {
            let cx = 12.0, cy = 13.0 + dy
            path.move(to: p(cx - 6.4 * k, cy + 4.0 * k))
            arc(cx - 4.2 * k, cy + 1.4 * k, 3.0 * k, 122, 250)
            arc(cx + 0.2 * k, cy - 1.6 * k, 4.4 * k, 202, 330)
            arc(cx + 4.6 * k, cy + 1.8 * k, 2.8 * k, 300, 62)
            path.addLine(to: p(cx - 6.4 * k, cy + 4.0 * k))
        }

        switch self {
        case .arrowUp, .upload:
            line(12, 20, 12, 5.4)
            path.move(to: p(6.2, 11.2)); path.addLine(to: p(12, 5.2)); path.addLine(to: p(17.8, 11.2))
        case .arrowDown:
            line(12, 4, 12, 18.6)
            path.move(to: p(6.2, 12.8)); path.addLine(to: p(12, 18.8)); path.addLine(to: p(17.8, 12.8))
        case .download:
            line(12, 3.4, 12, 14.6)
            path.move(to: p(7.4, 10.4)); path.addLine(to: p(12, 15)); path.addLine(to: p(16.6, 10.4))
            path.move(to: p(4.2, 16.4)); path.addLine(to: p(4.2, 19.4))
            path.addLine(to: p(19.8, 19.4)); path.addLine(to: p(19.8, 16.4))

        case .musicNote:
            line(13.6, 17.2, 13.6, 5.2)
            path.move(to: p(13.6, 5.2))
            path.addQuadCurve(to: p(19.4, 8.6), control: p(17.4, 5.0))
            circle(10.9, 17.3, 2.8)
        case .play:
            fillPolygon([(8, 5.2), (19, 12), (8, 18.8)])
        case .pause:
            line(9, 5.6, 9, 18.4)
            line(15, 5.6, 15, 18.4)
        case .next:
            fillPolygon([(6.5, 5.6), (15, 12), (6.5, 18.4)])
            line(17.8, 5.6, 17.8, 18.4)
        case .previous:
            fillPolygon([(17.5, 5.6), (9, 12), (17.5, 18.4)])
            line(6.2, 5.6, 6.2, 18.4)

        case .timer:
            circle(12, 13.4, 7.6)
            line(9.4, 3.2, 14.6, 3.2)
            line(12, 3.2, 12, 5.8)
            line(12, 13.4, 12, 8.8)
        case .calendar:
            roundedRect(3.6, 5.4, 16.8, 15, 3.4)
            line(3.6, 10.2, 20.4, 10.2)
            line(8.4, 3.2, 8.4, 7)
            line(15.6, 3.2, 15.6, 7)
        case .video:
            roundedRect(2.8, 6.6, 12.4, 10.8, 2.8)
            path.move(to: p(15.2, 10.4)); path.addLine(to: p(21.2, 7.2))
            path.addLine(to: p(21.2, 16.8)); path.addLine(to: p(15.2, 13.6))
            path.closeSubpath()

        case .bolt:
            fillPolygon([
                (13.4, 2.8), (6.2, 13.6), (11.4, 13.6),
                (10.6, 21.2), (17.8, 10.4), (12.6, 10.4),
            ])
        case .battery:
            roundedRect(2.4, 8, 16.8, 8, 2.6)
            path.move(to: p(20.8, 10.4)); path.addLine(to: p(20.8, 13.6))
            line(5.4, 12, 12.6, 12)

        case .speaker:
            path.move(to: p(3.2, 9.6)); path.addLine(to: p(6.8, 9.6))
            path.addLine(to: p(11.4, 5.6)); path.addLine(to: p(11.4, 18.4))
            path.addLine(to: p(6.8, 14.4)); path.addLine(to: p(3.2, 14.4))
            path.closeSubpath()
            arc(13.4, 12, 3.2, -52, 52)
            arc(13.4, 12, 6.2, -50, 50)
        case .speakerMute:
            path.move(to: p(3.2, 9.6)); path.addLine(to: p(6.8, 9.6))
            path.addLine(to: p(11.4, 5.6)); path.addLine(to: p(11.4, 18.4))
            path.addLine(to: p(6.8, 14.4)); path.addLine(to: p(3.2, 14.4))
            path.closeSubpath()
            line(15.2, 9.4, 20.6, 14.8)
            line(20.6, 9.4, 15.2, 14.8)

        case .sun:
            circle(12, 12, 4.4)
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                line(12 + cos(a) * 6.8, 12 + sin(a) * 6.8, 12 + cos(a) * 9.2, 12 + sin(a) * 9.2)
            }
        case .sunLow:
            circle(12, 12, 4.4)
            for i in 0..<4 {
                let a = Double(i) * .pi / 2 + .pi / 4
                line(12 + cos(a) * 6.8, 12 + sin(a) * 6.8, 12 + cos(a) * 8.6, 12 + sin(a) * 8.6)
            }
        case .moon:
            crescent()

        case .cloud:
            cloud()
        case .cloudSun:
            circle(8.0, 7.0, 2.9)
            // Only the rays that clear the cloud below; the rest would cross it.
            for degrees in [150.0, 195.0, 240.0, 285.0, 330.0] {
                let a = degrees * .pi / 180
                line(8.0 + cos(a) * 4.3, 7.0 + sin(a) * 4.3, 8.0 + cos(a) * 5.9, 7.0 + sin(a) * 5.9)
            }
            cloud(1.8, scale: 0.86)
        case .cloudMoon:
            crescent(cx: 8.4, cy: 7.2, scale: 0.52)
            cloud(1.8, scale: 0.86)
        case .cloudRain:
            cloud(-1.8, scale: 0.86)
            line(8.6, 17.4, 7.4, 20.6)
            line(12.4, 17.4, 11.2, 20.6)
            line(16.2, 17.4, 15.0, 20.6)
        case .cloudSnow:
            cloud(-2.0, scale: 0.86)
            for x in [8.2, 12.0, 15.8] {
                let r = 1.7
                for degrees in [90.0, 210.0, 330.0] {
                    let a = degrees * .pi / 180
                    line(x - cos(a) * r, 19.4 - sin(a) * r, x + cos(a) * r, 19.4 + sin(a) * r)
                }
            }
        case .cloudFog:
            cloud(-2.2, scale: 0.86)
            line(6.4, 18.4, 17.6, 18.4)
            line(8.4, 21.2, 15.6, 21.2)
        case .cloudBolt:
            cloud(-2.4, scale: 0.84)
            path.move(to: p(13.4, 16.2)); path.addLine(to: p(9.6, 20.0))
            path.addLine(to: p(12.0, 20.0)); path.addLine(to: p(11.2, 22.6))
            path.addLine(to: p(15.0, 18.6)); path.addLine(to: p(12.6, 18.6))
            path.closeSubpath()

        case .mic:
            roundedRect(9.2, 2.8, 5.6, 11.2, 2.8)
            arc(12, 12.2, 5.6, 0, 180)
            line(12, 17.8, 12, 21)
        case .camera:
            roundedRect(2.6, 6.6, 18.8, 12.4, 3.2)
            circle(12, 12.8, 3.6)
            path.move(to: p(8.6, 6.6)); path.addLine(to: p(10, 4.2))
            path.addLine(to: p(14, 4.2)); path.addLine(to: p(15.4, 6.6))

        case .capslock:
            path.move(to: p(4.8, 11.4)); path.addLine(to: p(12, 3.8)); path.addLine(to: p(19.2, 11.4))
            path.addLine(to: p(15, 11.4)); path.addLine(to: p(15, 15.6)); path.addLine(to: p(9, 15.6))
            path.addLine(to: p(9, 11.4))
            path.closeSubpath()
            roundedRect(9, 18, 6, 2.8, 1.2)
        case .tray:
            roundedRect(3.2, 4.6, 17.6, 14.8, 3.4)
            path.move(to: p(3.2, 13.6)); path.addLine(to: p(8.2, 13.6))
            path.addLine(to: p(9.6, 15.8)); path.addLine(to: p(14.4, 15.8))
            path.addLine(to: p(15.8, 13.6)); path.addLine(to: p(20.8, 13.6))
        case .folder:
            path.move(to: p(2.8, 18.6)); path.addLine(to: p(2.8, 6.2))
            path.addLine(to: p(9.2, 6.2)); path.addLine(to: p(11.2, 8.8))
            path.addLine(to: p(21.2, 8.8)); path.addLine(to: p(21.2, 18.6))
            path.closeSubpath()

        case .check:
            path.move(to: p(4.8, 12.6)); path.addLine(to: p(9.8, 17.6)); path.addLine(to: p(19.2, 6.6))
        case .cross:
            line(6.4, 6.4, 17.6, 17.6)
            line(17.6, 6.4, 6.4, 17.6)
        case .sparkle:
            solid.move(to: p(12, 3.2))
            solid.addQuadCurve(to: p(20.8, 12), control: p(13.4, 10.6))
            solid.addQuadCurve(to: p(12, 20.8), control: p(13.4, 13.4))
            solid.addQuadCurve(to: p(3.2, 12), control: p(10.6, 13.4))
            solid.addQuadCurve(to: p(12, 3.2), control: p(10.6, 10.6))
            solid.closeSubpath()
        case .film:
            roundedRect(3, 5, 18, 14, 2.8)
            line(7.4, 5, 7.4, 19)
            line(16.6, 5, 16.6, 19)
            line(7.4, 12, 16.6, 12)
        case .terminal:
            roundedRect(2.6, 4.4, 18.8, 15.2, 3.2)
            path.move(to: p(7, 10)); path.addLine(to: p(10.4, 13)); path.addLine(to: p(7, 16))
            line(12.6, 16, 17, 16)
        case .refresh:
            arc(12, 12, 7.4, 60, -20)
            path.move(to: p(17.6, 3.8)); path.addLine(to: p(18.8, 9.2)); path.addLine(to: p(13.4, 9.6))
        case .gauge:
            arc(12, 14.4, 7.6, 180, 0)
            line(12, 14.4, 15.6, 9.8)
        case .dot:
            solid.addEllipse(in: CGRect(
                x: ox + 8.4 * s, y: oy + 8.4 * s, width: 7.2 * s, height: 7.2 * s
            ))
        }
        return (path, solid)
    }

    // MARK: SF Symbol bridge

    /// Maps the SF Symbol names modules and CLI callers use onto this set.
    ///
    /// Keeping the public API in SF Symbol names means `islet start --icon
    /// symbol:bolt.fill` keeps working and anything unmapped still renders —
    /// it just falls back to Apple's glyph rather than failing.
    public static func mapping(for symbolName: String) -> IsletGlyph? {
        let base = symbolName.hasSuffix(".fill")
            ? String(symbolName.dropLast(5))
            : symbolName
        return table[base]
    }

    private static let table: [String: IsletGlyph] = [
        "arrow.up": .arrowUp, "arrow.up.circle": .arrowUp, "arrow.up.square": .arrowUp,
        "arrow.down": .arrowDown, "arrow.down.circle": .download,
        "square.and.arrow.down": .download, "square.and.arrow.up": .upload,
        "music.note": .musicNote, "play": .play, "pause": .pause,
        "forward": .next, "backward": .previous,
        "timer": .timer, "timer.circle": .timer, "hourglass": .timer,
        "calendar": .calendar, "video": .video,
        "bolt": .bolt, "battery.100": .battery, "battery.25": .battery,
        "battery.100.bolt": .bolt,
        "speaker.wave.1": .speaker, "speaker.wave.2": .speaker,
        "speaker.wave.3": .speaker, "speaker.slash": .speakerMute,
        "airpods": .speaker, "airpodspro": .speaker, "airpods.max": .speaker,
        "headphones": .speaker, "beats.headphones": .speaker, "display": .speaker,
        "sun.max": .sun, "sun.min": .sunLow, "moon": .moon, "moon.slash": .moon,
        "cloud": .cloud, "cloud.sun": .cloudSun, "cloud.moon": .cloudMoon,
        "cloud.rain": .cloudRain, "cloud.drizzle": .cloudRain,
        "cloud.sun.rain": .cloudRain, "cloud.moon.rain": .cloudRain,
        "cloud.snow": .cloudSnow, "cloud.sleet": .cloudSnow,
        "cloud.fog": .cloudFog, "cloud.bolt.rain": .cloudBolt, "cloud.bolt": .cloudBolt,
        "moon.stars": .moon,
        "mic": .mic, "video.badge.waveform": .camera, "camera": .camera,
        "capslock": .capslock,
        "tray": .tray, "tray.full": .tray, "tray.and.arrow.down": .tray,
        "folder": .folder,
        "checkmark": .check, "checkmark.circle": .check, "checkmark.seal": .check,
        "xmark": .cross, "xmark.circle": .cross, "xmark.octagon": .cross,
        "exclamationmark.triangle": .cross,
        "sparkles": .sparkle, "film": .film, "terminal": .terminal,
        "arrow.clockwise": .refresh, "gauge": .gauge, "circle": .dot,
        "briefcase": .tray, "person": .dot, "figure.run": .dot,
        "gamecontroller": .dot, "bed.double": .moon, "book": .calendar,
        "car": .dot, "brain.head.profile": .dot,
    ]
}

/// Renders an `IsletGlyph` at a given size.
public struct IsletGlyphView: View {
    public var glyph: IsletGlyph
    public var size: CGFloat
    public var tint: Color
    public var lineWidth: CGFloat

    public init(glyph: IsletGlyph, size: CGFloat, tint: Color, lineWidth: CGFloat = 1.8) {
        self.glyph = glyph
        self.size = size
        self.tint = tint
        self.lineWidth = lineWidth
    }

    public var body: some View {
        // Stroke scales with the glyph so a 40pt mark isn't hairline and a
        // 14pt one isn't a blob.
        let weight = lineWidth * (size / 24)
        Canvas { context, canvasSize in
            let (stroke, fill) = glyph.paths(in: CGRect(origin: .zero, size: canvasSize))
            if !fill.isEmpty {
                context.fill(fill, with: .color(tint))
            }
            if !stroke.isEmpty {
                context.stroke(
                    stroke,
                    with: .color(tint),
                    style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: size, height: size)
    }
}
