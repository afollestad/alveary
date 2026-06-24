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

    func testThoughtTransientRowTakesPriorityOverThinking() {
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(isTurnActive: true, thoughtText: "Thinking", thoughtSequence: 3),
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), [AppKitTranscriptTransientRows.thoughtRowID(sequence: 3)])
        XCTAssertTrue(rows[0].view is AppKitTranscriptStreamingBubbleView)
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

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(thoughtText: "Thinking", thoughtSequence: 7),
            configuration: .init(onRowHeightInvalidated: { rowID, animatesLayoutChanges in
                invalidations.append((rowID, animatesLayoutChanges))
            })
        )

        let thoughtBubble = rows.first?.view as? AppKitTranscriptStreamingBubbleView
        thoughtBubble?.configure(
            .init(
                text: "Thinking " + String(repeating: "through the implementation ", count: 30),
                bubbleMaxWidth: 220,
                variant: .thought
            )
        )

        XCTAssertTrue(
            invalidations.contains {
                $0.rowID == AppKitTranscriptTransientRows.thoughtRowID(sequence: 7) && !$0.animatesLayoutChanges
            }
        )
    }
}
