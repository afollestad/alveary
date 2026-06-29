@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptTextBubbleRowTests {
    func testFileOnlyUserMessageRendersRightAlignedCardWithoutBubble() throws {
        let fileAttachment = textBubbleFileAttachment(label: "design-notes.pdf", path: "/tmp/design-notes.pdf")
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        row.configure(
            .init(
                role: .user,
                markdown: "",
                fileAttachments: [fileAttachment]
            )
        )
        row.layoutSubtreeIfNeeded()

        let stripFrame = row.imageAttachmentStripFrameForTesting
        let fileFrame = try XCTUnwrap(row.fileAttachmentChipFramesForTesting.first)
        XCTAssertTrue(row.isBubbleHiddenForTesting)
        XCTAssertEqual(row.bubbleFrameForTesting, .zero)
        XCTAssertEqual(stripFrame.maxX, row.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(fileFrame.width, AppKitFileAttachmentChipView.preferredSize.width, accuracy: 0.5)
        XCTAssertEqual(fileFrame.height, AppKitFileAttachmentChipView.preferredSize.height, accuracy: 0.5)
        XCTAssertEqual(row.intrinsicContentSize.height, AppKitFileAttachmentChipView.preferredSize.height, accuracy: 0.5)
    }

    func testNarrowUserFileCardCapsWidthWithoutOverflowing() throws {
        let fileAttachment = textBubbleFileAttachment(label: "long-report-name.pdf", path: "/tmp/long-report-name.pdf")
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 220, height: 300)
        row.configure(
            .init(
                role: .user,
                markdown: "",
                fileAttachments: [fileAttachment]
            )
        )
        row.layoutSubtreeIfNeeded()

        let stripFrame = row.imageAttachmentStripFrameForTesting
        let fileFrame = try XCTUnwrap(row.fileAttachmentChipFramesForTesting.first)
        XCTAssertEqual(stripFrame.maxX, row.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(fileFrame.width, row.bounds.width - userBubbleLeadingClearance, accuracy: 0.5)
        XCTAssertLessThanOrEqual(stripFrame.maxX, row.bounds.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(stripFrame.minX, 0)
    }

    func testFileCardOpenCallbackReceivesAttachment() {
        let fileAttachment = textBubbleFileAttachment(label: "report.pdf", path: "/tmp/report.pdf")
        let row = AppKitTranscriptTextBubbleRowView()
        var openedAttachment: LocalFileAttachment?
        row.onOpenFileAttachment = { openedAttachment = $0 }
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        row.configure(
            .init(
                role: .user,
                markdown: "",
                fileAttachments: [fileAttachment]
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.openFileAttachmentForTesting(at: 0))
        XCTAssertEqual(openedAttachment, fileAttachment)
        XCTAssertEqual(row.fileAttachmentChipHitTargetsForTesting, [true])
    }
}

private func textBubbleFileAttachment(label: String, path: String) -> LocalFileAttachment {
    LocalFileAttachment(
        id: label,
        fileURL: URL(fileURLWithPath: path),
        label: label,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}
