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

    func testTranscriptImageAttachmentIndexMergesPersistedAndRuntimeAttachments() {
        let persisted = localImageAttachment(label: "persisted.png", path: "/tmp/persisted.png")
        let runtime = localImageAttachment(label: "runtime.png", path: "/tmp/runtime.png")
        let screenshot = localImageAttachment(label: "appshot.png", path: "/tmp/appshot.png")
        let message = ConversationEventRecord(conversationId: "conversation", type: "message", role: "user", content: "Describe")
        message.persistedImageAttachments = [persisted, runtime]
        let appShot = AppShotAttachment(
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Preview",
            screenshot: screenshot,
            axTreeText: "standard window Preview",
            focusedElementSummary: "standard window Preview",
            attachmentStoreRoot: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )

        let attachmentsByID = ChatTranscriptView.imageAttachmentsByUserMessageID(
            events: [message],
            runtimeImageAttachments: [message.id: [runtime]],
            runtimeAppShots: [message.id: [appShot]]
        )

        XCTAssertEqual(attachmentsByID[message.id], [persisted, runtime, screenshot])
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
