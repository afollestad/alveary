@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptRowFactoryTests {
    func testStreamingTransientRowTakesPriorityOverThought() {
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(
                isTurnActive: true,
                streamingText: "Streaming",
                thoughtText: "Thinking",
                thoughtSequence: 1
            ),
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), [AppKitTranscriptTransientRows.streamingRowID])
        XCTAssertTrue(rows[0].view is AppKitTranscriptStreamingBubbleView)
    }

    func testCompletedThoughtRendersBeforeStreamingText() {
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(
                streamingText: "Streaming",
                completedThoughtText: "Plan",
                completedThoughtSequence: 4
            ),
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), [
            AppKitTranscriptTransientRows.thoughtRowID(sequence: 4),
            AppKitTranscriptTransientRows.streamingRowID
        ])
        XCTAssertTrue(rows[0].view is AppKitTranscriptToolHeaderRowView)
        XCTAssertTrue(rows[1].view is AppKitTranscriptStreamingBubbleView)
    }

    func testThoughtTransientRowTakesPriorityOverThinking() {
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(isTurnActive: true, thoughtText: "Thinking", thoughtSequence: 3),
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), [AppKitTranscriptTransientRows.thoughtRowID(sequence: 3)])
        XCTAssertTrue(rows[0].view is AppKitTranscriptToolHeaderRowView)
    }

    func testThoughtTransientRowSequenceControlsIdentityAndCacheReset() {
        let factory = AppKitTranscriptRowFactory()

        let firstRows = factory.makeRows(
            for: [],
            transientRows: .init(thoughtText: "Plan", thoughtSequence: 1),
            configuration: .init()
        )
        let firstView = firstRows[0].view

        let appendedRows = factory.makeRows(
            for: [],
            transientRows: .init(thoughtText: "Plan more", thoughtSequence: 1),
            configuration: .init()
        )
        let nextRows = factory.makeRows(
            for: [],
            transientRows: .init(thoughtText: "Next", thoughtSequence: 2),
            configuration: .init()
        )
        let laterFirstSequenceRows = factory.makeRows(
            for: [],
            transientRows: .init(thoughtText: "Later", thoughtSequence: 1),
            configuration: .init()
        )

        XCTAssertEqual(firstRows.map(\.id), [AppKitTranscriptTransientRows.thoughtRowID(sequence: 1)])
        XCTAssertTrue(appendedRows[0].view === firstView)
        XCTAssertEqual(nextRows.map(\.id), [AppKitTranscriptTransientRows.thoughtRowID(sequence: 2)])
        XCTAssertFalse(nextRows[0].view === firstView)
        XCTAssertFalse(laterFirstSequenceRows[0].view === firstView)
    }

    func testThoughtHeightInvalidationRequestsNonAnimatedRelayout() {
        let factory = AppKitTranscriptRowFactory()
        var invalidations: [(rowID: String, animatesLayoutChanges: Bool)] = []

        _ = factory.makeRows(
            for: [],
            transientRows: .init(thoughtText: "Thinking", thoughtSequence: 7),
            configuration: .init(onRowHeightInvalidated: { rowID, animatesLayoutChanges in
                invalidations.append((rowID, animatesLayoutChanges))
            })
        )

        XCTAssertTrue(
            invalidations.contains {
                $0.rowID == AppKitTranscriptTransientRows.thoughtRowID(sequence: 7) && !$0.animatesLayoutChanges
            }
        )
    }

    func testThoughtTransientRowUsesIconlessPulsingToolSummary() throws {
        var settings = AppSettings()
        settings.chatFontSize = 18
        let typography = TranscriptTypography(settings: settings)
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(
                thoughtText: """
                ## Plan

                - Check **runtime** path
                - Run `swift test`
                """,
                thoughtSequence: 9
            ),
            configuration: .init(typography: typography)
        )

        let header = try XCTUnwrap(rows.first?.view as? AppKitTranscriptToolHeaderRowView)
        header.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        header.layoutSubtreeIfNeeded()
        let statusView = try XCTUnwrap(header.descendants(of: AppKitTranscriptToolStatusIndicatorView.self).first)
        let summaryField = try XCTUnwrap(header.descendants(of: NSTextField.self).first { !$0.stringValue.isEmpty })

        XCTAssertFalse(header.showsLeadingIconForTesting)
        XCTAssertTrue(header.isSummaryPulseVisibleForTesting)
        XCTAssertEqual(summaryField.lineBreakMode, .byWordWrapping)
        XCTAssertEqual(summaryField.maximumNumberOfLines, 0)
        XCTAssertEqual(statusView.frame, .zero)
        XCTAssertNil(statusView.statusSymbolSystemNameForTesting)
        XCTAssertEqual(summaryField.stringValue, "Run swift test")
        let summaryFont = try XCTUnwrap(summaryField.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(summaryFont.pointSize, typography.nsFont(.inlineToolText).pointSize)
    }

    func testThoughtTransientRowWrapsWithinBubbleMaxWidth() throws {
        let factory = AppKitTranscriptRowFactory()
        let maxWidth: CGFloat = 180

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(
                thoughtText: String(repeating: "Long thought segment needs room to wrap ", count: 5),
                thoughtSequence: 10
            ),
            configuration: .init(bubbleMaxWidth: maxWidth)
        )

        let header = try XCTUnwrap(rows.first?.view as? AppKitTranscriptToolHeaderRowView)
        header.frame = NSRect(x: 0, y: 0, width: 520, height: 240)
        header.layoutSubtreeIfNeeded()
        let summaryField = try XCTUnwrap(header.descendants(of: NSTextField.self).first { !$0.stringValue.isEmpty })
        let summaryFont = try XCTUnwrap(summaryField.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        XCTAssertLessThanOrEqual(summaryField.frame.width, maxWidth + 0.5)
        XCTAssertGreaterThan(summaryField.frame.height, summaryFont.pointSize * 2)
        XCTAssertGreaterThan(header.intrinsicContentSize.height, 50)
    }

    func testCompletedThoughtTransientRowUsesIconlessPulsingToolSummary() throws {
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(
                completedThoughtText: "Finished plan",
                completedThoughtSequence: 10
            ),
            configuration: .init()
        )

        let header = try XCTUnwrap(rows.first?.view as? AppKitTranscriptToolHeaderRowView)
        header.frame = NSRect(x: 0, y: 0, width: 420, height: 80)
        header.layoutSubtreeIfNeeded()
        let statusView = try XCTUnwrap(header.descendants(of: AppKitTranscriptToolStatusIndicatorView.self).first)
        let summaryField = try XCTUnwrap(header.descendants(of: NSTextField.self).first { !$0.stringValue.isEmpty })

        XCTAssertEqual(rows.map(\.id), [AppKitTranscriptTransientRows.thoughtRowID(sequence: 10)])
        XCTAssertFalse(header.showsLeadingIconForTesting)
        XCTAssertTrue(header.isSummaryPulseVisibleForTesting)
        XCTAssertEqual(summaryField.lineBreakMode, .byWordWrapping)
        XCTAssertEqual(summaryField.maximumNumberOfLines, 0)
        XCTAssertEqual(statusView.frame, .zero)
        XCTAssertNil(statusView.statusSymbolSystemNameForTesting)
        XCTAssertEqual(summaryField.stringValue, "Finished plan")
    }

    func testThoughtSummaryTextStripsMarkdownAndRendersOnlyTheNewestLine() {
        XCTAssertEqual(
            appKitTranscriptLiveThoughtSummaryText(
                from: """
                # Heading

                > quoted **idea**
                1. Inspect `AgentCLIKit`
                2. Validate [events](https://example.com)
                """
            ),
            "Validate events"
        )
    }

    func testThoughtSummaryTextRendersOnlyTheNewestReasoningSection() {
        XCTAssertEqual(
            appKitTranscriptLiveThoughtSummaryText(
                from: "**Verifying Node.js version strategy**\n\n**Finalizing plan details**"
            ),
            "Finalizing plan details"
        )
    }

    func testThoughtSummaryTextIgnoresTrailingBlankAndFencedLines() {
        XCTAssertEqual(
            appKitTranscriptLiveThoughtSummaryText(
                from: """
                Checking the transcript width

                ```swift
                """
            ),
            "Checking the transcript width"
        )
    }

    func testThoughtSummaryTextTreatsTouchingEmphasisAsASectionBoundary() {
        XCTAssertEqual(
            appKitTranscriptLiveThoughtSummaryText(
                from: "**Assessing methods to list PRs****Checking available GitHub tools**"
            ),
            "Checking available GitHub tools"
        )
        XCTAssertEqual(
            appKitTranscriptLiveThoughtSummaryText(
                from: "__Assessing methods to list PRs____Checking available GitHub tools__"
            ),
            "Checking available GitHub tools"
        )
        // A reasoning item can hold more than two parts, so only the last one is the newest section.
        XCTAssertEqual(
            appKitTranscriptLiveThoughtSummaryText(
                from: "**Assessing methods****Listing tools****Checking available GitHub tools**"
            ),
            "Checking available GitHub tools"
        )
    }

    func testThoughtSummaryTextKeepsSeparatedEmphasisRunsIntact() {
        XCTAssertEqual(
            appKitTranscriptLiveThoughtSummaryText(from: "**Note** **Detail**"),
            "Note Detail"
        )
    }
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
