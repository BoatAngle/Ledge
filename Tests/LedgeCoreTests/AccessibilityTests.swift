import XCTest
@testable import LedgeCore

/// `spokenSummary` is what a VoiceOver user gets instead of the island, so the
/// edge cases matter more than usual: a stuttered percentage or a repeated word
/// is the difference between a readout and a nuisance.
final class SpokenSummaryTests: XCTestCase {
    func testTitleAlone() {
        let content = ActivityContent(title: "Downloading")
        XCTAssertEqual(content.spokenSummary, "Downloading")
    }

    func testTitleSubtitleAndTrailingReadInReadingOrder() {
        let content = ActivityContent(
            title: "Bohemian Rhapsody",
            subtitle: "Queen",
            trailingText: "3:42"
        )
        XCTAssertEqual(content.spokenSummary, "Bohemian Rhapsody, Queen, 3:42")
    }

    func testTrailingTextIsNotRepeatedWhenTheTitleAlreadySaysIt() {
        // The battery module puts "84%" in both slots. Speaking it twice is the
        // kind of thing that makes people turn a feature off.
        let content = ActivityContent(title: "Battery 84%", trailingText: "84%")
        XCTAssertEqual(content.spokenSummary, "Battery 84%")
    }

    func testProgressIsSpokenAsAPercentage() {
        let content = ActivityContent(
            title: "Xcode.dmg",
            progress: ActivityProgress(fraction: 0.615)
        )
        XCTAssertEqual(content.spokenSummary, "Xcode.dmg, 62 percent")
    }

    func testIndeterminateProgressPrefersItsLabel() {
        let content = ActivityContent(
            title: "Syncing",
            progress: ActivityProgress(fraction: nil, label: "Waiting for the server")
        )
        XCTAssertEqual(content.spokenSummary, "Syncing, Waiting for the server")
    }

    func testIndeterminateProgressWithNoLabelStillSaysSomething() {
        let content = ActivityContent(
            title: "Syncing",
            progress: ActivityProgress(fraction: nil)
        )
        XCTAssertEqual(content.spokenSummary, "Syncing, in progress")
    }

    func testDuplicatePartsCollapse() {
        // Weather puts the condition in the title and the subtitle when there
        // is nothing else to say.
        let content = ActivityContent(title: "Clear", subtitle: "clear")
        XCTAssertEqual(content.spokenSummary, "Clear")
    }

    func testEmptyStringsAreNotSpokenAsPauses() {
        let content = ActivityContent(title: "Timer", subtitle: "", trailingText: "")
        XCTAssertEqual(content.spokenSummary, "Timer")
    }
}
