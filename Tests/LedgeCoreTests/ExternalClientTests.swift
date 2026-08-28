import XCTest
@testable import LedgeCore

/// The socket is owner-only, so this is not a boundary against another user —
/// it is a boundary against every process running as you, which is a much
/// larger set than the programs you would knowingly hand the island to.
final class ExternalClientSanitizationTests: XCTestCase {
    private func posted(
        module: String? = nil,
        nativeView: NativeViewKind? = nil,
        priority: ActivityPriority = .normal,
        openURL: String? = nil,
        actions: [ActivityAction] = []
    ) -> Activity {
        Activity(
            id: "x",
            content: ActivityContent(title: "Hi", actions: actions),
            nativeView: nativeView,
            module: module,
            openURL: openURL
        )
        .with(priority: priority)
    }

    func testAClientCannotClaimToBeABuiltInModule() {
        // `module` drives per-module appearance AND marks an activity as
        // system-owned, which exempts it from being cleared.
        let clean = posted(module: "system.media").sanitizedForExternalClient()
        XCTAssertNil(clean.module)
        XCTAssertFalse(clean.isModuleOwned)
    }

    func testAClientCannotClaimTheNativeRenderers() {
        // The privacy dot is the one mark on the island that must never lie.
        let clean = posted(nativeView: .privacy).sanitizedForExternalClient()
        XCTAssertNil(clean.nativeView)
    }

    func testPriorityIsClampedBelowTheSystemLevel() {
        let clean = posted(priority: .critical).sanitizedForExternalClient()
        XCTAssertEqual(clean.priority, .high)
        XCTAssertLessThan(clean.priority, .system)
    }

    func testOrdinaryPriorityIsUntouched() {
        XCTAssertEqual(posted(priority: .low).sanitizedForExternalClient().priority, .low)
    }

    func testWebAndMailLinksSurvive() {
        for url in ["https://example.com/x", "http://example.com", "mailto:a@b.co"] {
            XCTAssertEqual(
                posted(openURL: url).sanitizedForExternalClient().openURL,
                url,
                "\(url) should be openable"
            )
        }
    }

    func testFileURLsAreStripped() {
        // "Click to see your download" pointing at
        // file:///Applications/Utilities/Terminal.app is a plausible label for
        // an implausible thing to happen.
        let clean = posted(openURL: "file:///Applications/Utilities/Terminal.app")
            .sanitizedForExternalClient()
        XCTAssertNil(clean.openURL)
    }

    func testSchemelessAndScriptURLsAreStripped() {
        for url in ["javascript:alert(1)", "data:text/html,<b>x", "not a url at all"] {
            XCTAssertNil(
                posted(openURL: url).sanitizedForExternalClient().openURL,
                "\(url) should not be openable"
            )
        }
    }

    func testActionButtonURLsGetTheSameTreatment() {
        // The action row is the more likely attack surface: it comes with a
        // label the attacker chooses.
        let clean = posted(actions: [
            ActivityAction(id: "a", title: "Open", url: "https://example.com"),
            ActivityAction(id: "b", title: "Reveal", url: "file:///bin/sh"),
        ]).sanitizedForExternalClient()

        XCTAssertEqual(clean.content.actions[0].url, "https://example.com")
        XCTAssertNil(clean.content.actions[1].url)
    }
}

/// `end-all` is a display gesture. It used to be a destructive one.
final class EndAllScopeTests: XCTestCase {
    @MainActor
    private func loadedStore() -> ActivityStore {
        let store = ActivityStore()
        store.present(
            Activity(
                id: "system.timer.1",
                source: "system",
                content: ActivityContent(title: "25 minutes"),
                module: "system.timer"
            )
        )
        store.present(
            Activity(id: "cli.build", source: "cli", content: ActivityContent(title: "make all"))
        )
        return store
    }

    @MainActor
    func testClearingTheIslandSparesARunningTimer() {
        let store = loadedStore()
        XCTAssertEqual(store.endAll(), 1)
        XCTAssertNotNil(store.activities["system.timer.1"])
        XCTAssertNil(store.activities["cli.build"])
    }

    @MainActor
    func testAskingForModulesClearsThemToo() {
        let store = loadedStore()
        XCTAssertEqual(store.endAll(includingModules: true), 2)
        XCTAssertTrue(store.activities.isEmpty)
    }

    @MainActor
    func testSourceFilterStillApplies() {
        let store = loadedStore()
        XCTAssertEqual(store.endAll(source: "nobody"), 0)
        XCTAssertEqual(store.endAll(source: "cli"), 1)
    }
}

private extension Activity {
    /// Priority isn't in the memberwise position this test wants; this keeps
    /// the fixtures readable.
    func with(priority: ActivityPriority) -> Activity {
        var copy = self
        copy.priority = priority
        return copy
    }
}
