import XCTest
@testable import LedgeCore

@MainActor
final class ActivityStoreTests: XCTestCase {
    private func ongoing(
        _ id: String,
        priority: ActivityPriority = .normal,
        title: String = "Test"
    ) -> Activity {
        Activity(
            id: id,
            kind: .ongoing,
            priority: priority,
            content: ActivityContent(title: title, subtitle: "sub")
        )
    }

    func testIdleWhenEmpty() {
        let store = ActivityStore()
        XCTAssertTrue(store.composition.isIdle)
        XCTAssertEqual(store.composition.mode, .idle)
        XCTAssertNil(store.composition.primary)
    }

    func testSingleActivityIsCompact() {
        let store = ActivityStore()
        store.present(ongoing("a"))
        XCTAssertEqual(store.composition.mode, .compact)
        XCTAssertEqual(store.composition.primary?.id, "a")
        XCTAssertNil(store.composition.secondary)
    }

    func testSecondOngoingActivitySplits() {
        let store = ActivityStore()
        store.present(ongoing("a"))
        store.present(ongoing("b"))
        XCTAssertEqual(store.composition.mode, .split)
        XCTAssertEqual(store.composition.primary?.id, "b", "Most recent should lead")
        XCTAssertEqual(store.composition.secondary?.id, "a")
    }

    func testHigherPriorityTakesTheLead() {
        let store = ActivityStore()
        store.present(ongoing("low", priority: .low))
        store.present(ongoing("high", priority: .high))
        XCTAssertEqual(store.composition.primary?.id, "high")

        // Even when the lower-priority one is touched more recently.
        store.present(ongoing("low", priority: .low, title: "updated"))
        XCTAssertEqual(store.composition.primary?.id, "high")
    }

    /// The rule that makes a volume tap feel like an interruption rather than a
    /// companion: it takes the lead and pushes the incumbent to the small slot.
    func testTransientPreemptsOngoingAndNeverTakesTheMinimalSlot() {
        let store = ActivityStore()
        store.present(ongoing("music", priority: .high))
        store.flash(
            id: "volume",
            nativeView: .volume,
            content: ActivityContent(title: "Volume")
        )

        XCTAssertEqual(store.composition.primary?.id, "volume")
        XCTAssertEqual(store.composition.secondary?.id, "music")
        XCTAssertEqual(store.composition.mode, .split)
    }

    func testTransientGetsADefaultExpiry() {
        let store = ActivityStore()
        let posted = store.present(
            Activity(id: "t", kind: .transient, content: ActivityContent(title: "Flash"))
        )
        XCTAssertNotNil(posted.expiresAt, "A transient with no lifetime should be given one")
    }

    func testExpiredActivitiesAreExcluded() {
        let store = ActivityStore()
        store.present(
            Activity(
                id: "stale",
                kind: .transient,
                content: ActivityContent(title: "Gone"),
                expiresAt: Date().addingTimeInterval(-1)
            )
        )
        XCTAssertTrue(store.composition.isIdle)
    }

    func testUpdatePreservesCreationTimeAndSchedulingMetadata() {
        let store = ActivityStore()
        let original = store.present(ongoing("a", priority: .high))
        XCTAssertTrue(store.update(id: "a", content: ActivityContent(title: "Changed")))

        let updated = store.composition.primary
        XCTAssertEqual(updated?.content.title, "Changed")
        XCTAssertEqual(updated?.priority, .high)
        XCTAssertEqual(updated?.createdAt, original.createdAt)
    }

    func testUpdateUnknownIdFails() {
        let store = ActivityStore()
        XCTAssertFalse(store.update(id: "nope", content: ActivityContent(title: "x")))
    }

    func testEndAllBySource() {
        let store = ActivityStore()
        store.present(Activity(id: "a", source: "cli", content: ActivityContent(title: "A")))
        store.present(Activity(id: "b", source: "cli", content: ActivityContent(title: "B")))
        store.present(Activity(id: "c", source: "system", content: ActivityContent(title: "C")))

        XCTAssertEqual(store.endAll(source: "cli"), 2)
        XCTAssertEqual(store.composition.all.map(\.id), ["c"])
    }

    func testExpandingCollapsesWhenTheLastActivityEnds() {
        let store = ActivityStore()
        store.present(ongoing("a"))
        store.isExpanded = true
        XCTAssertEqual(store.composition.mode, .expanded)

        store.end(id: "a")
        XCTAssertFalse(store.isExpanded, "Nothing left to expand")
        XCTAssertEqual(store.composition.mode, .idle)
    }

    func testExpandableIsDerivedFromContent() {
        let bare = Activity(id: "bare", content: ActivityContent(title: "Just a title"))
        XCTAssertFalse(bare.isExpandable, "Nothing more to say than the compact slot shows")

        let rich = Activity(
            id: "rich",
            content: ActivityContent(title: "Title", subtitle: "More")
        )
        XCTAssertTrue(rich.isExpandable)
    }

    func testStructureKeyIgnoresContentChanges() {
        let store = ActivityStore()
        store.present(ongoing("a"))
        let before = store.composition.structureKey
        store.update(id: "a", content: ActivityContent(title: "Different", subtitle: "s"))
        XCTAssertEqual(store.composition.structureKey, before,
                       "Content edits must not retrigger the shape animation")
    }
}
