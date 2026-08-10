import XCTest
@testable import IsletCore

final class GeometryTests: XCTestCase {
    private let notched = IslandMetrics(
        notchSize: CGSize(width: 220, height: 38),
        screenWidth: 2056,
        hasPhysicalNotch: true
    )

    func testIdleMatchesTheNotchExactly() {
        // Idle has to be invisible against the hardware, so any deviation here
        // shows up as a black rectangle sitting on the bezel.
        XCTAssertEqual(IslandGeometry.size(mode: .idle, metrics: notched), notched.notchSize)
    }

    func testCompactGrowsSymmetrically() {
        let size = IslandGeometry.size(mode: .compact, metrics: notched)
        XCTAssertEqual(size.width, 220 + IslandGeometry.compactSidePadding * 2)
        XCTAssertEqual(size.height, 38 + IslandGeometry.compactHeightBonus)
    }

    func testSplitAddsTheDetachedCircleAndAGap() {
        let compact = IslandGeometry.size(mode: .compact, metrics: notched)
        let split = IslandGeometry.size(mode: .split, metrics: notched)
        XCTAssertEqual(
            split.width,
            compact.width + IslandGeometry.splitGap + IslandGeometry.minimalDiameter
        )
    }

    func testMinimalFrameOnlyExistsInSplit() {
        XCTAssertNil(IslandGeometry.minimalFrame(mode: .compact, metrics: notched, in: .zero))
        let frame = IslandGeometry.minimalFrame(mode: .split, metrics: notched, in: .zero)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.width, IslandGeometry.minimalDiameter)
    }

    func testExpandedHeightIsClamped() {
        let tall = IslandGeometry.size(mode: .expanded, metrics: notched, expandedHeight: 9_000)
        XCTAssertEqual(tall.height, IslandGeometry.expandedMaxHeight)

        let short = IslandGeometry.size(mode: .expanded, metrics: notched, expandedHeight: 1)
        XCTAssertEqual(short.height, IslandGeometry.expandedMinHeight)
    }

    func testSynthesizedMetricsForNotchlessDisplays() {
        let virtual = IslandMetrics.synthesized(screenWidth: 2560)
        XCTAssertFalse(virtual.hasPhysicalNotch)
        XCTAssertEqual(virtual.notchSize, IslandMetrics.standardNotch)
    }
}

final class ColorParsingTests: XCTestCase {
    func testNamedColors() {
        XCTAssertEqual(IsletColor(parsing: "green"), IsletColor.green)
        XCTAssertEqual(IsletColor(parsing: "  ORANGE "), IsletColor.orange)
    }

    func testHexWithAndWithoutHash() {
        for input in ["#FF0080", "ff0080"] {
            let color = IsletColor(parsing: input)
            XCTAssertEqual(color?.red ?? 0, 1, accuracy: 0.005, input)
            XCTAssertEqual(color?.green ?? 1, 0, accuracy: 0.005, input)
            XCTAssertEqual(color?.blue ?? 0, 0.502, accuracy: 0.005, input)
            XCTAssertEqual(color?.alpha ?? 0, 1, accuracy: 0.005, input)
        }
    }

    func testHexWithAlpha() {
        let color = IsletColor(parsing: "#00000080")
        XCTAssertEqual(color?.alpha ?? 0, 0.502, accuracy: 0.01)
    }

    func testRejectsNonsense() {
        XCTAssertNil(IsletColor(parsing: "chartreuse"))
        XCTAssertNil(IsletColor(parsing: "#12345"))
    }
}

final class WireProtocolTests: XCTestCase {
    func testActivityRoundTripsThroughTheWire() throws {
        let original = Activity(
            id: "deploy",
            source: "cli",
            kind: .ongoing,
            priority: .high,
            content: ActivityContent(
                title: "Deploying",
                subtitle: "prod",
                icon: .symbol("arrow.up"),
                tint: .blue,
                progress: ActivityProgress(fraction: 0.4, label: "3 of 7"),
                details: [ActivityDetail(label: "Region", value: "us-east-1")],
                actions: [ActivityAction(id: "cancel", title: "Cancel", isDestructive: true)]
            ),
            openURL: "https://example.com"
        )

        let line = try IsletCoding.line(IsletRequest(command: .present, activity: original))
        XCTAssertEqual(line.last, 0x0A, "Framing depends on the trailing newline")

        let decoded = try IsletCoding.decoder.decode(
            IsletRequest.self,
            from: line.dropLast()
        )
        XCTAssertEqual(decoded.command, .present)
        let activity = try XCTUnwrap(decoded.activity)

        XCTAssertEqual(activity.id, original.id)
        XCTAssertEqual(activity.source, original.source)
        XCTAssertEqual(activity.kind, original.kind)
        XCTAssertEqual(activity.priority, original.priority)
        XCTAssertEqual(activity.openURL, original.openURL)
        XCTAssertEqual(activity.isExpandable, original.isExpandable)
        // Content carries no dates here, so it must survive exactly.
        XCTAssertEqual(activity.content, original.content)

        // Dates go over the wire as ISO 8601 text, so the guarantee is
        // millisecond fidelity — not bit-identical `Date` values, which no text
        // format can promise.
        XCTAssertEqual(
            activity.createdAt.timeIntervalSinceReferenceDate,
            original.createdAt.timeIntervalSinceReferenceDate,
            accuracy: 0.001
        )
    }

    func testFractionalSecondsSurviveEncoding() throws {
        // The reason for the custom strategy: `.iso8601` would round this to
        // whole seconds and quietly shorten every sub-second dwell.
        let target = Date(timeIntervalSinceReferenceDate: 800_000.75)
        let content = ActivityContent(title: "Timer", countdownTarget: target)
        let data = try IsletCoding.encoder.encode(content)
        let decoded = try IsletCoding.decoder.decode(ActivityContent.self, from: data)

        XCTAssertEqual(
            try XCTUnwrap(decoded.countdownTarget).timeIntervalSinceReferenceDate,
            800_000.75,
            accuracy: 0.001
        )
    }

    func testWholeSecondDatesFromHandWrittenJSONStillParse() throws {
        let json = Data(#"{"title":"Manual","countdownTarget":"2026-08-10T12:00:00Z"}"#.utf8)
        let content = try IsletCoding.decoder.decode(ActivityContent.self, from: json)
        XCTAssertNotNil(content.countdownTarget)
    }

    func testProgressIsClampedOnTheWayIn() {
        XCTAssertEqual(ActivityProgress(fraction: 2.5).fraction, 1)
        XCTAssertEqual(ActivityProgress(fraction: -1).fraction, 0)
        XCTAssertTrue(ActivityProgress().isIndeterminate)
    }

    func testSocketPathFitsInSockaddrUn() {
        // sockaddr_un caps the path at 104 bytes; exceeding it fails at bind
        // time with a confusing error, so assert it here instead.
        XCTAssertLessThan(IsletSocket.path.utf8.count, 104)
    }
}

extension WireProtocolTests {
    /// The minimum a script should have to write.
    func testMinimalHandWrittenJSON() throws {
        let json = Data(#"{"title":"Hello"}"#.utf8)
        let content = try IsletCoding.decoder.decode(ActivityContent.self, from: json)
        XCTAssertEqual(content.title, "Hello")
        XCTAssertTrue(content.details.isEmpty)
        XCTAssertTrue(content.actions.isEmpty)
        XCTAssertFalse(content.hasExpandedContent)
    }

    func testTitleIsTheOnlyRequiredField() {
        let json = Data(#"{"subtitle":"no title"}"#.utf8)
        XCTAssertThrowsError(try IsletCoding.decoder.decode(ActivityContent.self, from: json))
    }
}
