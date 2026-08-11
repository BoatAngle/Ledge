import XCTest
@testable import IsletCore
@testable import IsletUI

@MainActor
final class DropShelfTests: XCTestCase {
    private func fileURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/islet-tests/\(name)")
    }

    func testAcceptAddsFiles() {
        let shelf = DropShelf()
        shelf.accept([fileURL("a.txt"), fileURL("b.txt")])
        XCTAssertEqual(shelf.files.count, 2)
    }

    func testAcceptDeduplicates() {
        let shelf = DropShelf()
        shelf.accept([fileURL("a.txt")])
        shelf.accept([fileURL("a.txt"), fileURL("b.txt")])
        XCTAssertEqual(shelf.files.map(\.lastPathComponent), ["a.txt", "b.txt"])
    }

    func testRemoveAndClear() {
        let shelf = DropShelf()
        shelf.accept([fileURL("a.txt"), fileURL("b.txt")])
        shelf.remove(fileURL("a.txt"))
        XCTAssertEqual(shelf.files.map(\.lastPathComponent), ["b.txt"])
        shelf.clear()
        XCTAssertTrue(shelf.files.isEmpty)
    }

    func testEmptyDropIsIgnored() {
        let shelf = DropShelf()
        shelf.accept([])
        XCTAssertTrue(shelf.files.isEmpty)
    }

    /// The hint must expire on its own. It sits at `.critical`, so if AppKit
    /// ever fails to deliver `draggingExited` an ongoing one would wedge the
    /// island permanently.
    func testHoverHintExpiresOnItsOwn() {
        let store = ActivityStore()
        let shelf = DropShelf()
        shelf.attach(to: store)
        shelf.dragEntered()

        let hint = store.composition.primary
        XCTAssertEqual(hint?.kind, .transient)
        XCTAssertNotNil(hint?.expiresAt)
    }

    func testDropClearsTheHint() {
        let store = ActivityStore()
        let shelf = DropShelf()
        shelf.attach(to: store)
        shelf.dragEntered()
        shelf.accept([fileURL("a.txt")])

        XCTAssertFalse(shelf.isTargeted)
        XCTAssertEqual(store.composition.primary?.id, DropShelf.activityID)
    }
}

@MainActor
final class SplitLayoutTests: XCTestCase {
    private let metrics = IslandMetrics(
        notchSize: CGSize(width: 220, height: 38),
        screenWidth: 2056,
        hasPhysicalNotch: true
    )

    /// In `.split` the compact body must stay centred on the camera housing.
    ///
    /// The island is centred in its window, so if the footprint simply grew to
    /// the right the body would slide left by half the circle's width and the
    /// notch gap would no longer sit over the actual notch.
    func testSplitKeepsTheBodyCentredOnTheNotch() {
        let compact = IslandGeometry.size(mode: .compact, metrics: metrics)
        let total = IslandGeometry.size(mode: .split, metrics: metrics)
        let reserve = IslandGeometry.splitGap + IslandGeometry.minimalDiameter

        // Footprint as the renderer builds it, ignoring the symmetric fillets.
        let footprintWidth = total.width + reserve
        // Where the body sits inside that footprint.
        let bodyMid = reserve + compact.width / 2

        XCTAssertEqual(bodyMid, footprintWidth / 2, accuracy: 0.001,
                       "Body centre must coincide with the footprint centre")
    }
}

final class IslandThemeTests: XCTestCase {
    func testEveryThemeIDHasAPreset() {
        for id in IslandThemeID.allCases {
            XCTAssertEqual(IslandTheme.preset(id).id, id)
        }
    }

    /// The quieter themes strip `.fill` so modules don't have to know about
    /// themes — but only where an unfilled twin actually exists.
    func testSymbolVariantsFollowTheTheme() {
        XCTAssertEqual(IslandTheme.vivid.symbolName("bolt.fill"), "bolt.fill")
        XCTAssertEqual(IslandTheme.system.symbolName("bolt.fill"), "bolt")
        XCTAssertEqual(IslandTheme.system.symbolName("timer"), "timer")
    }

    func testSymbolsWithNoUnfilledTwinKeepTheirFill() {
        // `capslock.fill` has a twin; a made-up one must not become a blank box.
        let invented = "not.a.real.symbol.fill"
        XCTAssertEqual(IslandTheme.system.symbolName(invented), invented)
    }

    /// Sparing themes keep glyphs monochrome but must still colour anything
    /// that encodes state — that's what the accent is for.
    func testAccentUsageSeparatesGlyphsFromState() {
        let style = ActivityStyle(tint: .red)
        XCTAssertEqual(style.glyphColor(.vivid), style.tint)
        XCTAssertNotEqual(style.glyphColor(.system), style.tint)
        XCTAssertEqual(style.accentColor, style.tint, "State colour is never suppressed")
        XCTAssertEqual(style.glow(.editorial), 0)
    }
}
