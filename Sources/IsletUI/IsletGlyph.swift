import SwiftUI

/// Outline or solid.
///
/// A solid icon is not "the outline, filled" — filling a battery outline gives
/// a black lozenge, not a battery. Solid marks are drawn as silhouettes with
/// their interior detail subtracted, which is different geometry, not a
/// different paint.
public enum GlyphWeight: Sendable, Equatable {
    case outline
    case solid
}

/// Islet's own icon family.
///
/// Drawn rather than borrowed. SF Symbols are excellent but they carry Apple's
/// optical conventions, and at 20pt against black they read as *system* icons
/// on someone else's surface. These are built on one geometric grid so the
/// island's marks look like a set rather than a selection.
///
/// Conventions, held across every glyph:
/// - A 24×24 box with the mark living inside 20×20 (2pt optical margin).
/// - Round caps and joins throughout.
/// - Circles run slightly larger than squares of the same nominal size, because
///   they read smaller.
/// - In the solid weight, *enclosed forms* become silhouettes while *linear
///   detail* stays stroked. A speaker's cone fills; its sound waves do not.
///   Filling everything turns small marks into blobs.
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
    /// Three paths, not one. `stroke` is linear detail, `fill` is solid mass,
    /// and `holes` is subtracted from the fill. The subtraction is a separate
    /// path rather than an even-odd winding trick because even-odd cancels
    /// wherever two *intended* solids overlap — a music note's stem crossing
    /// its head would punch a hole through both.
    public func paths(
        in rect: CGRect,
        weight: GlyphWeight = .outline
    ) -> (stroke: Path, fill: Path, holes: Path) {
        var path = Path()
        var solid = Path()
        var holes = Path()
        let isSolid = weight == .solid

        let s = min(rect.width, rect.height) / 24
        let ox = rect.minX + (rect.width - 24 * s) / 2
        let oy = rect.minY + (rect.height - 24 * s) / 2
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        /// Arcs are specified in degrees, clockwise on screen, 0° at 3 o'clock.
        func arc(into target: inout Path, _ cx: Double, _ cy: Double, _ r: Double,
                 _ from: Double, _ to: Double) {
            target.addArc(
                center: p(cx, cy), radius: r * s,
                startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false
            )
        }
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            path.move(to: p(x1, y1))
            path.addLine(to: p(x2, y2))
        }
        func circle(into target: inout Path, _ cx: Double, _ cy: Double, _ r: Double) {
            target.addEllipse(in: CGRect(
                x: ox + (cx - r) * s, y: oy + (cy - r) * s,
                width: 2 * r * s, height: 2 * r * s
            ))
        }
        func roundedRect(into target: inout Path, _ x: Double, _ y: Double,
                         _ w: Double, _ h: Double, _ r: Double) {
            target.addRoundedRect(
                in: CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s),
                cornerSize: CGSize(width: r * s, height: r * s),
                style: .continuous
            )
        }
        func polygon(into target: inout Path, _ points: [(Double, Double)]) {
            guard let first = points.first else { return }
            target.move(to: p(first.0, first.1))
            for point in points.dropFirst() { target.addLine(to: p(point.0, point.1)) }
            target.closeSubpath()
        }
        /// Turns a polyline into a fillable outline, so linear detail can be
        /// subtracted from a silhouette at a controlled width.
        func strokedShape(_ points: [(Double, Double)], _ width: Double) -> Path {
            var line = Path()
            line.move(to: p(points[0].0, points[0].1))
            for point in points.dropFirst() { line.addLine(to: p(point.0, point.1)) }
            return line.strokedPath(
                StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round)
            )
        }

        // Convenience wrappers for the common targets.
        func stroke(_ cx: Double, _ cy: Double, _ r: Double, _ from: Double, _ to: Double) {
            arc(into: &path, cx, cy, r, from, to)
        }
        func circleO(_ cx: Double, _ cy: Double, _ r: Double) { circle(into: &path, cx, cy, r) }
        func circleF(_ cx: Double, _ cy: Double, _ r: Double) { circle(into: &solid, cx, cy, r) }
        func circleH(_ cx: Double, _ cy: Double, _ r: Double) { circle(into: &holes, cx, cy, r) }
        func rectO(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) {
            roundedRect(into: &path, x, y, w, h, r)
        }
        func rectF(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) {
            roundedRect(into: &solid, x, y, w, h, r)
        }
        func rectH(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) {
            roundedRect(into: &holes, x, y, w, h, r)
        }
        func polyO(_ points: [(Double, Double)]) { polygon(into: &path, points) }
        func polyF(_ points: [(Double, Double)]) { polygon(into: &solid, points) }
        func holeLine(_ points: [(Double, Double)], _ width: Double) {
            holes.addPath(strokedShape(points, width))
        }

        /// A crescent drawn as two bulging curves meeting at the tips.
        ///
        /// Building it from two circle arcs requires solving for where the
        /// circles intersect; placing the tips directly is both easier to
        /// control and easier to read at 20pt.
        func crescent(into target: inout Path, cx: Double = 12, cy: Double = 12,
                      scale k: Double = 1) {
            let tipX = cx + 2.6 * k, top = cy - 7.6 * k, bottom = cy + 7.6 * k
            target.move(to: p(tipX, top))
            target.addCurve(
                to: p(tipX, bottom),
                control1: p(cx - 6.8 * k, cy - 5.6 * k),
                control2: p(cx - 6.8 * k, cy + 5.6 * k)
            )
            target.addCurve(
                to: p(tipX, top),
                control1: p(cx - 1.4 * k, cy + 4.6 * k),
                control2: p(cx - 1.4 * k, cy - 4.6 * k)
            )
            target.closeSubpath()
        }
        /// Cloud outline shared by the weather glyphs, offset so variants can
        /// sit it higher and leave room for what falls out of it.
        func cloud(into target: inout Path, _ dy: Double = 0, scale k: Double = 1) {
            let cx = 12.0, cy = 13.0 + dy
            target.move(to: p(cx - 6.4 * k, cy + 4.0 * k))
            arc(into: &target, cx - 4.2 * k, cy + 1.4 * k, 3.0 * k, 122, 250)
            arc(into: &target, cx + 0.2 * k, cy - 1.6 * k, 4.4 * k, 202, 330)
            arc(into: &target, cx + 4.6 * k, cy + 1.8 * k, 2.8 * k, 300, 62)
            target.addLine(to: p(cx - 6.4 * k, cy + 4.0 * k))
        }
        /// Draws the cloud into whichever path the current weight calls for.
        func weatherCloud(_ dy: Double = 0, scale k: Double = 1) {
            if isSolid { cloud(into: &solid, dy, scale: k) } else { cloud(into: &path, dy, scale: k) }
        }

        switch self {

        // MARK: Arrows

        case .arrowUp:
            if isSolid {
                polyF([(12, 4.2), (19.6, 12.2), (15.1, 12.2), (15.1, 20),
                       (8.9, 20), (8.9, 12.2), (4.4, 12.2)])
            } else {
                // Open chevron head, matching arrowDown — the closed triangle
                // made the up arrow visibly heavier than its twin.
                line(12, 20, 12, 5.4)
                path.move(to: p(6.2, 11.2)); path.addLine(to: p(12, 5.2))
                path.addLine(to: p(17.8, 11.2))
            }
        case .upload:
            // Mirrors .download — a tray you lift out of, not a bare arrow.
            if isSolid {
                polyF([(12, 2.8), (18.4, 9.4), (14.6, 9.4), (14.6, 15.6),
                       (9.4, 15.6), (9.4, 9.4), (5.6, 9.4)])
                rectF(3.6, 17.4, 16.8, 2.8, 1.4)
            } else {
                line(12, 3.2, 12, 14.6)
                path.move(to: p(7.4, 7.6)); path.addLine(to: p(12, 3))
                path.addLine(to: p(16.6, 7.6))
                path.move(to: p(4.2, 16.4)); path.addLine(to: p(4.2, 19.4))
                path.addLine(to: p(19.8, 19.4)); path.addLine(to: p(19.8, 16.4))
            }
        case .arrowDown:
            if isSolid {
                polyF([(12, 19.8), (19.6, 11.8), (15.1, 11.8), (15.1, 4),
                       (8.9, 4), (8.9, 11.8), (4.4, 11.8)])
            } else {
                line(12, 4, 12, 18.6)
                path.move(to: p(6.2, 12.8)); path.addLine(to: p(12, 18.8))
                path.addLine(to: p(17.8, 12.8))
            }
        case .download:
            if isSolid {
                polyF([(12, 15.8), (18.4, 9.2), (14.6, 9.2), (14.6, 3),
                       (9.4, 3), (9.4, 9.2), (5.6, 9.2)])
                rectF(3.6, 17.4, 16.8, 2.8, 1.4)
            } else {
                line(12, 3.4, 12, 14.6)
                path.move(to: p(7.4, 10.4)); path.addLine(to: p(12, 15))
                path.addLine(to: p(16.6, 10.4))
                path.move(to: p(4.2, 16.4)); path.addLine(to: p(4.2, 19.4))
                path.addLine(to: p(19.8, 19.4)); path.addLine(to: p(19.8, 16.4))
            }

        // MARK: Media

        case .musicNote:
            if isSolid {
                circleF(10.6, 17.2, 3.3)
                polyF([(12.6, 17.2), (12.6, 5.2), (14.9, 5.2), (14.9, 17.2)])
                polyF([(14.9, 5.2), (19.8, 8.2), (19.8, 11.0), (14.9, 8.0)])
            } else {
                line(13.6, 17.2, 13.6, 5.2)
                path.move(to: p(13.6, 5.2))
                path.addQuadCurve(to: p(19.4, 8.6), control: p(17.4, 5.0))
                circleO(10.9, 17.3, 2.8)
            }
        case .play:
            polyF([(8, 5.2), (19, 12), (8, 18.8)])
        case .pause:
            if isSolid {
                rectF(7.4, 5.2, 3.8, 13.6, 1.9)
                rectF(12.8, 5.2, 3.8, 13.6, 1.9)
            } else {
                line(9, 5.6, 9, 18.4)
                line(15, 5.6, 15, 18.4)
            }
        case .next:
            polyF([(6.5, 5.6), (15, 12), (6.5, 18.4)])
            if isSolid { rectF(16.4, 5.6, 2.8, 12.8, 1.4) } else { line(17.8, 5.6, 17.8, 18.4) }
        case .previous:
            polyF([(17.5, 5.6), (9, 12), (17.5, 18.4)])
            if isSolid { rectF(4.8, 5.6, 2.8, 12.8, 1.4) } else { line(6.2, 5.6, 6.2, 18.4) }

        // MARK: Time and events

        case .timer:
            if isSolid {
                circleF(12, 13.4, 7.9)
                holeLine([(12, 13.4), (12, 8.6)], 1.9)
                rectF(9.2, 2.0, 5.6, 2.4, 1.2)
                rectF(10.7, 3.6, 2.6, 2.8, 0.9)
            } else {
                circleO(12, 13.4, 7.6)
                line(9.4, 3.2, 14.6, 3.2)
                line(12, 3.2, 12, 5.8)
                line(12, 13.4, 12, 8.8)
            }
        case .calendar:
            if isSolid {
                rectF(3.6, 5.4, 16.8, 15, 3.4)
                holeLine([(4.4, 10.2), (19.6, 10.2)], 1.6)
                rectF(7.2, 2.4, 2.4, 4.6, 1.2)
                rectF(14.4, 2.4, 2.4, 4.6, 1.2)
            } else {
                rectO(3.6, 5.4, 16.8, 15, 3.4)
                line(3.6, 10.2, 20.4, 10.2)
                line(8.4, 3.2, 8.4, 7)
                line(15.6, 3.2, 15.6, 7)
            }
        case .video:
            if isSolid {
                rectF(2.8, 6.6, 12.4, 10.8, 2.8)
                polyF([(15.6, 10.4), (21.2, 7.2), (21.2, 16.8), (15.6, 13.6)])
            } else {
                rectO(2.8, 6.6, 12.4, 10.8, 2.8)
                polyO([(15.2, 10.4), (21.2, 7.2), (21.2, 16.8), (15.2, 13.6)])
            }

        // MARK: Power

        case .bolt:
            polyF([(13.4, 2.8), (6.2, 13.6), (11.4, 13.6),
                   (10.6, 21.2), (17.8, 10.4), (12.6, 10.4)])
        case .battery:
            if isSolid {
                // Knock out only the *empty* part of the cell. The first pass
                // hollowed the whole interior and then drew the charge level
                // back into the fill — where the punch promptly erased it.
                rectF(2.4, 8, 16.8, 8, 2.6)
                rectH(12.2, 9.8, 5.4, 4.4, 1.4)
                rectF(19.6, 10.3, 2.2, 3.4, 1.0)
            } else {
                rectO(2.4, 8, 16.8, 8, 2.6)
                path.move(to: p(20.8, 10.4)); path.addLine(to: p(20.8, 13.6))
                line(5.4, 12, 12.6, 12)
            }

        // MARK: Sound

        case .speaker:
            // The cone gains mass; the waves stay linear in both weights —
            // filled sound waves read as a solid fan, which means nothing.
            let cone: [(Double, Double)] = [
                (3.2, 9.6), (6.8, 9.6), (11.4, 5.6), (11.4, 18.4), (6.8, 14.4), (3.2, 14.4),
            ]
            if isSolid { polyF(cone) } else { polyO(cone) }
            stroke(13.4, 12, 3.2, -52, 52)
            stroke(13.4, 12, 6.2, -50, 50)
        case .speakerMute:
            let cone: [(Double, Double)] = [
                (3.2, 9.6), (6.8, 9.6), (11.4, 5.6), (11.4, 18.4), (6.8, 14.4), (3.2, 14.4),
            ]
            if isSolid { polyF(cone) } else { polyO(cone) }
            line(15.2, 9.4, 20.6, 14.8)
            line(20.6, 9.4, 15.2, 14.8)

        // MARK: Sky

        case .sun:
            if isSolid { circleF(12, 12, 4.9) } else { circleO(12, 12, 4.4) }
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                line(12 + cos(a) * 6.8, 12 + sin(a) * 6.8, 12 + cos(a) * 9.2, 12 + sin(a) * 9.2)
            }
        case .sunLow:
            // Eight short rays around a smaller disc, rather than four
            // diagonals — four read as a cross struck through a circle, which
            // says "disabled", not "dimmed".
            if isSolid { circleF(12, 12, 3.7) } else { circleO(12, 12, 3.3) }
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                line(12 + cos(a) * 5.2, 12 + sin(a) * 5.2, 12 + cos(a) * 6.5, 12 + sin(a) * 6.5)
            }
        case .moon:
            if isSolid { crescent(into: &solid) } else { crescent(into: &path) }

        case .cloud:
            weatherCloud()
        case .cloudSun:
            if isSolid { circleF(8.0, 6.8, 3.2) } else { circleO(8.0, 6.8, 2.9) }
            // Only the rays that clear the cloud below; the rest would cross it.
            for degrees in [150.0, 195.0, 240.0, 285.0, 330.0] {
                let a = degrees * .pi / 180
                line(8.0 + cos(a) * 4.5, 6.8 + sin(a) * 4.5, 8.0 + cos(a) * 6.1, 6.8 + sin(a) * 6.1)
            }
            weatherCloud(2.0, scale: 0.84)
        case .cloudMoon:
            // Bigger and further out than the first attempt, which tucked a
            // tiny crescent behind the cloud and read as a smudge.
            if isSolid {
                crescent(into: &solid, cx: 6.9, cy: 5.6, scale: 0.62)
            } else {
                crescent(into: &path, cx: 6.9, cy: 5.6, scale: 0.62)
            }
            weatherCloud(2.9, scale: 0.78)
        case .cloudRain:
            weatherCloud(-1.8, scale: 0.86)
            line(8.6, 17.4, 7.4, 20.6)
            line(12.4, 17.4, 11.2, 20.6)
            line(16.2, 17.4, 15.0, 20.6)
        case .cloudSnow:
            // Fewer, larger, further apart. Three tight asterisks at the old
            // spacing merged into a dotted line at notch size.
            weatherCloud(-2.2, scale: 0.84)
            for x in [8.4, 15.6] {
                let r = 2.1
                for degrees in [90.0, 210.0, 330.0] {
                    let a = degrees * .pi / 180
                    line(x - cos(a) * r, 19.8 - sin(a) * r, x + cos(a) * r, 19.8 + sin(a) * r)
                }
            }
        case .cloudFog:
            weatherCloud(-2.2, scale: 0.86)
            line(6.4, 18.4, 17.6, 18.4)
            line(8.4, 21.2, 15.6, 21.2)
        case .cloudBolt:
            weatherCloud(-2.4, scale: 0.84)
            polyF([(13.4, 16.2), (9.6, 20.0), (12.0, 20.0),
                   (11.2, 22.6), (15.0, 18.6), (12.6, 18.6)])

        // MARK: Privacy

        case .mic:
            if isSolid { rectF(9.2, 2.8, 5.6, 11.2, 2.8) } else { rectO(9.2, 2.8, 5.6, 11.2, 2.8) }
            stroke(12, 12.2, 5.6, 0, 180)
            line(12, 17.8, 12, 21)
        case .camera:
            if isSolid {
                rectF(2.6, 6.6, 18.8, 12.4, 3.2)
                polyF([(8.6, 6.8), (10, 4.2), (14, 4.2), (15.4, 6.8)])
                circleH(12, 12.8, 3.9)
                circleF(12, 12.8, 1.7)
            } else {
                rectO(2.6, 6.6, 18.8, 12.4, 3.2)
                circleO(12, 12.8, 3.6)
                path.move(to: p(8.6, 6.6)); path.addLine(to: p(10, 4.2))
                path.addLine(to: p(14, 4.2)); path.addLine(to: p(15.4, 6.6))
            }

        // MARK: Objects

        case .capslock:
            let arrow: [(Double, Double)] = [
                (4.8, 11.4), (12, 3.8), (19.2, 11.4), (15, 11.4),
                (15, 15.6), (9, 15.6), (9, 11.4),
            ]
            if isSolid {
                polyF(arrow)
                rectF(9, 17.8, 6, 3.0, 1.3)
            } else {
                polyO(arrow)
                rectO(9, 18, 6, 2.8, 1.2)
            }
        case .tray:
            if isSolid {
                rectF(3.2, 4.6, 17.6, 14.8, 3.4)
                rectH(5.4, 6.5, 13.2, 6.3, 2.0)
            } else {
                rectO(3.2, 4.6, 17.6, 14.8, 3.4)
                path.move(to: p(3.2, 13.6)); path.addLine(to: p(8.2, 13.6))
                path.addLine(to: p(9.6, 15.8)); path.addLine(to: p(14.4, 15.8))
                path.addLine(to: p(15.8, 13.6)); path.addLine(to: p(20.8, 13.6))
            }
        case .folder:
            let shape: [(Double, Double)] = [
                (2.8, 18.6), (2.8, 6.2), (9.2, 6.2), (11.2, 8.8), (21.2, 8.8), (21.2, 18.6),
            ]
            if isSolid { polyF(shape) } else { polyO(shape) }

        // MARK: Marks

        case .check:
            // Purely linear — a filled tick is just a heavier tick.
            path.move(to: p(4.8, 12.6)); path.addLine(to: p(9.8, 17.6))
            path.addLine(to: p(19.2, 6.6))
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
            if isSolid {
                rectF(3, 5, 18, 14, 2.8)
                rectH(9.4, 7.2, 5.2, 9.6, 1.2)
                for y in [7.0, 10.6, 14.2] {
                    rectH(5.0, y, 2.6, 2.6, 0.8)
                    rectH(16.4, y, 2.6, 2.6, 0.8)
                }
            } else {
                rectO(3, 5, 18, 14, 2.8)
                line(7.4, 5, 7.4, 19)
                line(16.6, 5, 16.6, 19)
                line(7.4, 12, 16.6, 12)
            }
        case .terminal:
            if isSolid {
                rectF(2.6, 4.4, 18.8, 15.2, 3.2)
                holes.addPath(strokedShape([(7.4, 9.8), (10.8, 12.8), (7.4, 15.8)], 1.9))
                holeLine([(13.0, 15.8), (17.0, 15.8)], 1.9)
            } else {
                rectO(2.6, 4.4, 18.8, 15.2, 3.2)
                path.move(to: p(7, 10)); path.addLine(to: p(10.4, 13))
                path.addLine(to: p(7, 16))
                line(12.6, 16, 17, 16)
            }
        case .refresh:
            stroke(12, 12, 7.4, 60, -20)
            path.move(to: p(17.6, 3.8)); path.addLine(to: p(18.8, 9.2))
            path.addLine(to: p(13.4, 9.6))
        case .gauge:
            stroke(12, 14.4, 7.6, 180, 0)
            line(12, 14.4, 15.6, 9.8)
        case .dot:
            circleF(12, 12, isSolid ? 4.2 : 3.6)
        }
        return (path, solid, holes)
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
        "sparkles": .sparkle, "film": .film, "terminal": .terminal,
        "arrow.clockwise": .refresh, "gauge": .gauge, "circle": .dot,
        "briefcase": .tray,
        "bed.double": .moon, "book": .calendar,
    ]
}

/// Renders an `IsletGlyph` at a given size.
public struct IsletGlyphView: View {
    public var glyph: IsletGlyph
    public var size: CGFloat
    public var tint: Color
    public var lineWidth: CGFloat
    public var weight: GlyphWeight

    public init(
        glyph: IsletGlyph,
        size: CGFloat,
        tint: Color,
        lineWidth: CGFloat = 1.8,
        weight: GlyphWeight = .outline
    ) {
        self.glyph = glyph
        self.size = size
        self.tint = tint
        self.lineWidth = lineWidth
        self.weight = weight
    }

    public var body: some View {
        // Stroke scales with the glyph so a 40pt mark isn't hairline and a
        // 14pt one isn't a blob.
        let stroke = lineWidth * (size / 24)
        Canvas { context, canvasSize in
            let (outline, fill, holes) = glyph.paths(
                in: CGRect(origin: .zero, size: canvasSize),
                weight: weight
            )
            if !fill.isEmpty {
                // Punched with a blend mode rather than an even-odd winding:
                // even-odd would also cancel wherever two *intended* solids
                // overlap, so a stem crossing a note head would vanish.
                context.drawLayer { layer in
                    layer.fill(fill, with: .color(tint))
                    if !holes.isEmpty {
                        layer.blendMode = .destinationOut
                        layer.fill(holes, with: .color(.black))
                    }
                }
            }
            if !outline.isEmpty {
                context.stroke(
                    outline,
                    with: .color(tint),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: size, height: size)
    }
}
