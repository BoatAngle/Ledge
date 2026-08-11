import XCTest
@testable import IsletCore

final class ModuleAppearanceTests: XCTestCase {
    func testDefaultIsRecognised() {
        XCTAssertTrue(ModuleAppearance.default.isDefault)
        XCTAssertFalse(ModuleAppearance(scale: 1.2).isDefault)
        XCTAssertFalse(ModuleAppearance(tint: .red).isDefault)
        XCTAssertFalse(ModuleAppearance(slot: .minimal).isDefault)
        XCTAssertFalse(ModuleAppearance(priorityOffset: 50).isDefault)
    }

    func testScaleAndOffsetAreClamped() {
        XCTAssertEqual(ModuleAppearance(scale: 99).scale, ModuleAppearance.scaleRange.upperBound)
        XCTAssertEqual(ModuleAppearance(scale: 0).scale, ModuleAppearance.scaleRange.lowerBound)
        XCTAssertEqual(
            ModuleAppearance(priorityOffset: 10_000).priorityOffset,
            ModuleAppearance.priorityRange.upperBound
        )
    }

    /// These land in UserDefaults, which anyone can write to with `defaults
    /// write` — a scale of 40 would push a glyph clean off the notch.
    func testDecodingClampsHostileValues() throws {
        let json = Data(#"{"scale":40,"priorityOffset":999999,"slot":"automatic"}"#.utf8)
        let decoded = try JSONDecoder().decode(ModuleAppearance.self, from: json)
        XCTAssertEqual(decoded.scale, ModuleAppearance.scaleRange.upperBound)
        XCTAssertEqual(decoded.priorityOffset, ModuleAppearance.priorityRange.upperBound)
    }

    func testDecodingToleratesMissingFields() throws {
        let decoded = try JSONDecoder().decode(ModuleAppearance.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.isDefault)
    }

    func testRoundTrip() throws {
        let original = ModuleAppearance(tint: .purple, scale: 1.15, slot: .minimal, priorityOffset: -75)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ModuleAppearance.self, from: data), original)
    }
}

@MainActor
final class AppearanceSchedulingTests: XCTestCase {
    private func ongoing(_ id: String, module: String, priority: ActivityPriority = .normal) -> Activity {
        Activity(
            id: id,
            kind: .ongoing,
            priority: priority,
            content: ActivityContent(title: id, subtitle: "s"),
            module: module
        )
    }

    func testSlotPreferenceMovesAModuleToTheSmallCircle() {
        let store = ActivityStore()
        store.appearanceForModule = { module in
            module == "quiet" ? ModuleAppearance(slot: .minimal) : .default
        }
        // Same priority, and the "quiet" one is newer — so without the
        // preference it would lead.
        store.present(ongoing("a", module: "loud"))
        store.present(ongoing("b", module: "quiet"))

        XCTAssertEqual(store.composition.primary?.id, "a")
        XCTAssertEqual(store.composition.secondary?.id, "b")
    }

    func testLeadingPreferenceBringsAModuleForward() {
        let store = ActivityStore()
        store.appearanceForModule = { module in
            module == "front" ? ModuleAppearance(slot: .leading) : .default
        }
        // "front" is both older and lower priority, and still leads.
        store.present(ongoing("a", module: "front", priority: .low))
        store.present(ongoing("b", module: "other", priority: .normal))

        XCTAssertEqual(store.composition.primary?.id, "a")
    }

    func testPriorityOffsetBreaksATie() {
        let store = ActivityStore()
        store.appearanceForModule = { module in
            module == "boosted" ? ModuleAppearance(priorityOffset: 100) : .default
        }
        store.present(ongoing("a", module: "boosted"))
        store.present(ongoing("b", module: "plain"))

        XCTAssertEqual(store.composition.primary?.id, "a")
    }

    func testActivitiesWithoutAModuleAreUnaffected() {
        let store = ActivityStore()
        store.appearanceForModule = { _ in ModuleAppearance(slot: .minimal) }
        // CLI activities carry no module, so nothing should apply to them.
        store.present(Activity(id: "cli", content: ActivityContent(title: "x", subtitle: "y")))
        XCTAssertEqual(store.composition.primary?.id, "cli")
    }

    func testRefreshReresolvesWithoutAnActivityChange() {
        let store = ActivityStore()
        var preferMinimal = false
        store.appearanceForModule = { module in
            module == "swing" && preferMinimal ? ModuleAppearance(slot: .minimal) : .default
        }
        store.present(ongoing("a", module: "other"))
        store.present(ongoing("b", module: "swing"))
        XCTAssertEqual(store.composition.primary?.id, "b")

        // Changing the *rules* has to trigger a pass; nothing about the
        // activities themselves changed.
        preferMinimal = true
        store.refresh()
        XCTAssertEqual(store.composition.primary?.id, "a")
    }
}
