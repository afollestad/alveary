@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptRowFactoryTests {
    func testUserMessageRendersConfiguredImageAttachmentsAsDisplayOnlyMarkdown() throws {
        let factory = AppKitTranscriptRowFactory()
        let attachment = localImageAttachment(label: "diagram] one.png", path: "/tmp/diagram>one.png")
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.imageAttachmentsByUserMessageID = ["user": [attachment]]

        let rows = factory.makeRows(for: [.userMessage(id: "user", text: "Describe this")], configuration: configuration)

        let bubble = try XCTUnwrap(rows[0].view as? AppKitTranscriptTextBubbleRowView)
        XCTAssertEqual(bubble.configuration?.markdown, "\(attachment.markdownImageLink)\n\nDescribe this")
    }

    func testUserMessageMarkdownPreparationIncludesConfiguredImageAttachments() {
        let factory = AppKitTranscriptRowFactory()
        let attachment = localImageAttachment(label: "screen.png", path: "/tmp/screen.png")
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.imageAttachmentsByUserMessageID = ["user": [attachment]]

        let requests = factory.markdownPreparationRequests(
            for: [.userMessage(id: "user", text: "")],
            configuration: configuration
        )

        XCTAssertEqual(requests.map(\.markdown), [attachment.markdownImageLink])
    }

    private func localImageAttachment(label: String, path: String) -> LocalImageAttachment {
        LocalImageAttachment(
            id: UUID().uuidString,
            fileURL: URL(fileURLWithPath: path),
            label: label,
            createdAt: Date()
        )
    }
}
