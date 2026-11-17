import XCTest
@testable import LedgeCore

/// The island draws above full-screen windows, which is what makes it read as
/// hardware and what makes it intolerable over a film. Suppression is how it
/// stands down — and the contract is that it hides the *presentation* without
/// touching the work underneath.
@MainActor
final class SuppressionTests: XCTestCase {
    private func ongoing(_ id: String) -> Activity {
        Activity(id: id, kind: .ongoing, content: ActivityContent(title: id, subtitle: "sub"))
    }

    func testSuppressionEmptiesTheIsland() {
        let store = ActivityStore()
        store.present(ongoing("music"))
        XCTAssertEqual(store.composition.mode, .compact)

        store.isSuppressed = true
        XCTAssertTrue(store.composition.isIdle)
        XCTAssertNil(store.composition.primary)
    }

    func testTheWorkUnderneathKeepsRunning() {
        // A timer must still be counting while a film is on, or leaving full
        // screen would show an alarm that quietly stopped existing.
        let store = ActivityStore()
        store.present(ongoing("timer"))
        store.isSuppressed = true

        XCTAssertEqual(store.activities.count, 1, "The activity is hidden, not ended")
        XCTAssertNotNil(store.activities["timer"])
    }

    func testLeavingFullScreenRestoresWhatWasMissed() {
        let store = ActivityStore()
        store.present(ongoing("download"))
        store.isSuppressed = true
        store.present(ongoing("meeting"))
        XCTAssertTrue(store.composition.isIdle, "Arrivals during a film stay quiet")

        store.isSuppressed = false
        XCTAssertFalse(store.composition.isIdle)
        XCTAssertEqual(store.composition.all.count, 2, "Both are waiting on the other side")
    }

    func testSuppressionClosesAnOpenPanel() {
        // Going full screen with the panel down has to put it away, not leave
        // 468pt of lit content hanging over the film.
        let store = ActivityStore()
        store.present(ongoing("music"))
        store.isExpanded = true
        store.focusedActivityID = "music"
        XCTAssertEqual(store.composition.mode, .expanded)

        store.isSuppressed = true
        XCTAssertFalse(store.isExpanded)
        XCTAssertNil(store.focusedActivityID)
        XCTAssertTrue(store.composition.isIdle)
    }

    func testSuppressionOutranksEvenACriticalActivity() {
        // Priority decides who gets the island; suppression decides whether
        // there is an island at all.
        let store = ActivityStore()
        store.present(
            Activity(
                id: "system.privacy",
                source: "system",
                priority: .critical,
                content: ActivityContent(title: "Camera in use"),
                module: "system.privacy"
            )
        )
        store.isSuppressed = true
        XCTAssertTrue(store.composition.isIdle)
    }

    func testTogglingBackAndForthIsStable() {
        let store = ActivityStore()
        store.present(ongoing("a"))
        for _ in 0..<5 {
            store.isSuppressed = true
            store.isSuppressed = false
        }
        XCTAssertEqual(store.composition.primary?.id, "a")
        XCTAssertEqual(store.activities.count, 1)
    }
}
