import SwiftUI
import XCTest
@testable import LedgeUI

final class LedgeGlyphTests: XCTestCase {
    private let box = CGRect(x: 0, y: 0, width: 24, height: 24)

    /// A glyph that draws nothing renders as an empty square, which looks like
    /// a layout bug rather than a missing icon.
    func testEveryGlyphDrawsSomethingInBothWeights() {
        for glyph in LedgeGlyph.allCases {
            for weight in [GlyphWeight.outline, .solid] {
                let (stroke, fill, _) = glyph.paths(in: box, weight: weight)
                XCTAssertFalse(
                    stroke.isEmpty && fill.isEmpty,
                    "\(glyph.rawValue) draws nothing at \(weight)"
                )
            }
        }
    }

    /// Holes are subtracted from the fill. One that lands outside the fill is
    /// silently doing nothing, which means the detail it was meant to carve is
    /// missing.
    func testHolesAlwaysLandInsideTheirFill() {
        for glyph in LedgeGlyph.allCases {
            let (_, fill, holes) = glyph.paths(in: box, weight: .solid)
            guard !holes.isEmpty else { continue }
            XCTAssertFalse(fill.isEmpty, "\(glyph.rawValue) punches a hole in nothing")
            XCTAssertTrue(
                fill.boundingRect.insetBy(dx: -0.5, dy: -0.5).contains(holes.boundingRect),
                "\(glyph.rawValue)'s hole falls outside its silhouette"
            )
        }
    }

    /// The regression that shipped in the first solid pass: the battery's
    /// charge level was drawn into the fill and then erased by a knockout
    /// covering the whole interior, leaving an empty shell.
    func testSolidBatteryKeepsItsChargeLevel() {
        let (_, fill, holes) = LedgeGlyph.battery.paths(in: box, weight: .solid)
        XCTAssertFalse(holes.isEmpty, "The empty portion should be knocked out")
        // The knockout must cover only part of the cell, not all of it.
        XCTAssertLessThan(
            holes.boundingRect.width,
            fill.boundingRect.width * 0.55,
            "The knockout swallows the charge level"
        )
    }

    /// Marks with no enclosed area gain nothing from a solid weight, so they
    /// stay identical rather than being bulked up into something misshapen.
    func testPurelyLinearMarksAreIdenticalInBothWeights() {
        for glyph in [LedgeGlyph.check, .cross, .refresh, .gauge] {
            let outline = glyph.paths(in: box, weight: .outline)
            let solid = glyph.paths(in: box, weight: .solid)
            XCTAssertEqual(
                outline.stroke.description, solid.stroke.description,
                "\(glyph.rawValue) should not change shape when filled"
            )
            XCTAssertTrue(outline.fill.isEmpty && solid.fill.isEmpty)
        }
    }

    /// Solid marks need actual mass; a "solid" glyph that is still all stroke
    /// gives Vivid nothing over the outline weight.
    func testMarksThatShouldGainMassDo() {
        let expectedSolid: [LedgeGlyph] = [
            .arrowUp, .arrowDown, .download, .musicNote, .timer, .calendar,
            .video, .battery, .sun, .moon, .cloud, .mic, .camera, .capslock,
            .tray, .folder, .film, .terminal,
        ]
        for glyph in expectedSolid {
            let (_, fill, _) = glyph.paths(in: box, weight: .solid)
            XCTAssertFalse(fill.isEmpty, "\(glyph.rawValue) has no mass when solid")
        }
    }

    /// Everything has to sit inside the 24pt box, or it clips against a
    /// neighbouring glyph in the compact strip.
    func testGlyphsStayWithinTheirBox() {
        for glyph in LedgeGlyph.allCases {
            for weight in [GlyphWeight.outline, .solid] {
                let (stroke, fill, _) = glyph.paths(in: box, weight: weight)
                for rect in [stroke.boundingRect, fill.boundingRect] where !rect.isEmpty {
                    XCTAssertTrue(
                        box.insetBy(dx: -1.5, dy: -1.5).contains(rect),
                        "\(glyph.rawValue) at \(weight) overflows its box: \(rect)"
                    )
                }
            }
        }
    }

    func testThemesPickTheirGlyphWeight() {
        XCTAssertEqual(IslandTheme.vivid.glyphFill, .solid)
        XCTAssertEqual(IslandTheme.glass.glyphFill, .solid)
        XCTAssertEqual(IslandTheme.system.glyphFill, .outline)
        XCTAssertEqual(IslandTheme.editorial.glyphFill, .outline)
    }
}
