@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptRowFactoryTests {
    func testTranscriptNoteHeightInvalidationRequestsNonAnimatedRelayout() {
        let invalidations = heightInvalidations(for: [.transcriptNote(id: "note", kind: .sessionHandoff)])

        XCTAssertTrue(
            invalidations.contains { invalidation in
                invalidation.rowID == "note" && !invalidation.animatesLayoutChanges
            }
        )
    }

    func testErrorRowHeightInvalidationRequestsNonAnimatedRelayout() {
        let invalidations = heightInvalidations(for: [.error(id: "error", message: "Session handoff send failed.")])

        XCTAssertTrue(
            invalidations.contains { invalidation in
                invalidation.rowID == "error" && !invalidation.animatesLayoutChanges
            }
        )
    }

    func testConsecutiveSessionHandoffNotesUseStandardRowSpacing() throws {
        let factory = AppKitTranscriptRowFactory()
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        container.configure(
            rows: factory.makeRows(
                for: [
                    .transcriptNote(id: "first-handoff", kind: .sessionHandoff),
                    .transcriptNote(id: "second-handoff", kind: .sessionHandoff)
                ],
                configuration: .init()
            ),
            preserveBottomIfFollowing: false
        )

        let firstFrame = try XCTUnwrap(container.rowFrame(for: "first-handoff"))
        let secondFrame = try XCTUnwrap(container.rowFrame(for: "second-handoff"))
        XCTAssertLessThanOrEqual(firstFrame.height, 32)
        XCTAssertLessThanOrEqual(secondFrame.height, 32)
        XCTAssertEqual(secondFrame.minY - firstFrame.maxY, 12, accuracy: 0.5)
    }

    func testSessionHandoffNoteVisualGapIsBalancedBetweenBubbles() throws {
        let factory = AppKitTranscriptRowFactory()
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = 480
        container.configure(
            rows: factory.makeRows(
                for: [
                    .assistantMessage(
                        id: "before",
                        text: (0..<30).map { "Long assistant line \($0)" }.joined(separator: "\n\n")
                    ),
                    .transcriptNote(id: "handoff", kind: .sessionHandoff),
                    .assistantMessage(id: "after", text: "Primary goal:\n\nFinish the session handoff work.")
                ],
                configuration: configuration
            ),
            preserveBottomIfFollowing: false
        )

        let beforeBubble = try visibleBubbleFrame(in: container, rowID: "before")
        let noteLabel = try visibleNoteLabelFrame(in: container, rowID: "handoff")
        let afterBubble = try visibleBubbleFrame(in: container, rowID: "after")
        let topGap = noteLabel.minY - beforeBubble.maxY
        let bottomGap = afterBubble.minY - noteLabel.maxY

        XCTAssertEqual(topGap, 16, accuracy: 0.5)
        XCTAssertEqual(bottomGap, 16, accuracy: 0.5)
    }

    private func heightInvalidations(for items: [ChatItem]) -> [(rowID: String, animatesLayoutChanges: Bool)] {
        let factory = AppKitTranscriptRowFactory()
        var invalidations: [(rowID: String, animatesLayoutChanges: Bool)] = []
        _ = factory.makeRows(
            for: items,
            configuration: .init(onRowHeightInvalidated: { rowID, animatesLayoutChanges in
                invalidations.append((rowID, animatesLayoutChanges))
            })
        )
        return invalidations
    }

    private func visibleBubbleFrame(
        in container: AppKitTranscriptScrollContainerView,
        rowID: String
    ) throws -> CGRect {
        let row = try XCTUnwrap(container.transcriptDocumentView.subviews.first { $0.identifier?.rawValue == rowID })
        let bubble = try XCTUnwrap(row as? AppKitTranscriptTextBubbleRowView)
        return bubble.bubbleFrameForTesting.offsetBy(dx: row.frame.minX, dy: row.frame.minY)
    }

    private func visibleNoteLabelFrame(
        in container: AppKitTranscriptScrollContainerView,
        rowID: String
    ) throws -> CGRect {
        let row = try XCTUnwrap(container.transcriptDocumentView.subviews.first { $0.identifier?.rawValue == rowID })
        let label = try XCTUnwrap(descendants(of: NSTextField.self, in: row).first)
        return label.frame.offsetBy(dx: row.frame.minX, dy: row.frame.minY)
    }

    private func descendants<ViewType: NSView>(
        of type: ViewType.Type,
        in view: NSView
    ) -> [ViewType] {
        view.subviews.flatMap { child -> [ViewType] in
            var matches = descendants(of: type, in: child)
            if let child = child as? ViewType {
                matches.insert(child, at: 0)
            }
            return matches
        }
    }
}
