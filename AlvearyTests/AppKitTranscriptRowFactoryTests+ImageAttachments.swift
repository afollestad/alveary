@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptRowFactoryTests {
    func testUserMessagePassesConfiguredImageAttachmentsOutsideMarkdown() throws {
        let factory = AppKitTranscriptRowFactory()
        let attachment = localImageAttachment(label: "diagram] one.png", path: "/tmp/diagram>one.png")
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.imageAttachmentsByMessageID = ["user": [attachment]]

        let rows = factory.makeRows(for: [.userMessage(id: "user", text: "Describe this")], configuration: configuration)

        let bubble = try XCTUnwrap(rows[0].view as? AppKitTranscriptTextBubbleRowView)
        XCTAssertEqual(bubble.configuration?.markdown, "Describe this")
        XCTAssertEqual(bubble.configuration?.imageAttachments, [attachment])
    }

    func testUserMessageMarkdownPreparationExcludesConfiguredImageAttachments() {
        let factory = AppKitTranscriptRowFactory()
        let attachment = localImageAttachment(label: "screen.png", path: "/tmp/screen.png")
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.imageAttachmentsByMessageID = ["user": [attachment]]

        let requests = factory.markdownPreparationRequests(
            for: [.userMessage(id: "user", text: "Describe this")],
            configuration: configuration
        )

        XCTAssertEqual(requests.map(\.markdown), ["Describe this"])
    }

    func testTranscriptImageAttachmentIndexMergesPersistedAndRuntimeAttachmentsForAnyMessageRole() {
        let persisted = localImageAttachment(label: "persisted.png", path: "/tmp/persisted.png")
        let assistantPersisted = localImageAttachment(label: "assistant.png", path: "/tmp/assistant.png")
        let runtime = localImageAttachment(label: "runtime.png", path: "/tmp/runtime.png")
        let screenshot = localImageAttachment(label: "appshot.png", path: "/tmp/appshot.png")
        let message = ConversationEventRecord(conversationId: "conversation", type: "message", role: "user", content: "Describe")
        message.persistedImageAttachments = [persisted, runtime]
        let assistantMessage = ConversationEventRecord(
            conversationId: "conversation",
            type: "message",
            role: "assistant",
            content: "Generated image"
        )
        assistantMessage.persistedImageAttachments = [assistantPersisted]
        let appShot = AppShotAttachment(
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Preview",
            screenshot: screenshot,
            axTreeText: "standard window Preview",
            focusedElementSummary: "standard window Preview",
            attachmentStoreRoot: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )

        let attachmentsByID = ChatTranscriptView.imageAttachmentsByMessageID(
            events: [message, assistantMessage],
            runtimeImageAttachments: [message.id: [runtime]],
            runtimeAppShots: [message.id: [appShot]]
        )

        XCTAssertEqual(attachmentsByID[message.id], [persisted, runtime, screenshot])
        XCTAssertEqual(attachmentsByID[assistantMessage.id], [assistantPersisted])
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
