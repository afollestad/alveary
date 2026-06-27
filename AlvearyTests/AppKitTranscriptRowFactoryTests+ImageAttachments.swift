@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptRowFactoryTests {
    func testUserMessagePassesConfiguredImageAttachmentsOutsideMarkdown() throws {
        let factory = AppKitTranscriptRowFactory()
        let attachment = localImageAttachment(label: "diagram] one.png", path: "/tmp/diagram>one.png")
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.transcriptImageAttachmentsByMessageID = [
            "user": [TranscriptImageAttachment(localImageAttachment: attachment)]
        ]

        let rows = factory.makeRows(for: [.userMessage(id: "user", text: "Describe this")], configuration: configuration)

        let bubble = try XCTUnwrap(rows[0].view as? AppKitTranscriptTextBubbleRowView)
        XCTAssertEqual(bubble.configuration?.markdown, "Describe this")
        XCTAssertEqual(
            bubble.configuration?.imageAttachments,
            [TranscriptImageAttachment(localImageAttachment: attachment)]
        )
    }

    func testUserMessageMarkdownPreparationExcludesConfiguredImageAttachments() {
        let factory = AppKitTranscriptRowFactory()
        let attachment = localImageAttachment(label: "screen.png", path: "/tmp/screen.png")
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.transcriptImageAttachmentsByMessageID = [
            "user": [TranscriptImageAttachment(localImageAttachment: attachment)]
        ]

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
        message.setPersistedPlainImageAttachments([persisted, runtime])
        let assistantMessage = ConversationEventRecord(
            conversationId: "conversation",
            type: "message",
            role: "assistant",
            content: "Generated image"
        )
        assistantMessage.setPersistedPlainImageAttachments([assistantPersisted])
        let appShot = AppShotAttachment(
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Preview",
            screenshot: screenshot,
            axTreeText: "standard window Preview",
            focusedElementSummary: "standard window Preview",
            attachmentStoreRoot: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )

        let attachmentsByID = ChatTranscriptView.transcriptImageAttachmentsByMessageID(
            events: [message, assistantMessage],
            runtimeImageAttachments: [message.id: [runtime]],
            runtimeAppShots: [message.id: [appShot]]
        )

        XCTAssertEqual(attachmentsByID[message.id]?.map(\.image), [persisted, runtime, screenshot])
        XCTAssertEqual(attachmentsByID[message.id]?.last?.appShot, PersistedAppShotAttachment(appShot: appShot))
        XCTAssertEqual(attachmentsByID[assistantMessage.id]?.map(\.image), [assistantPersisted])
    }

    func testTranscriptImageAttachmentIndexUpgradesDuplicatePlainScreenshotWithAppShotMetadata() {
        let screenshot = localImageAttachment(label: "appshot.png", path: "/tmp/appshot.png")
        let message = ConversationEventRecord(conversationId: "conversation", type: "message", role: "user", content: "Describe")
        message.setPersistedPlainImageAttachments([screenshot])
        let appShot = AppShotAttachment(
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Window title",
            screenshot: screenshot,
            axTreeText: "standard window Preview",
            focusedElementSummary: "standard window Preview",
            attachmentStoreRoot: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )

        let attachmentsByID = ChatTranscriptView.transcriptImageAttachmentsByMessageID(
            events: [message],
            runtimeImageAttachments: [:],
            runtimeAppShots: [message.id: [appShot]]
        )

        XCTAssertEqual(attachmentsByID[message.id], [TranscriptImageAttachment(appShot: PersistedAppShotAttachment(appShot: appShot))])
    }

    func testTranscriptImageAttachmentIndexKeepsDuplicateAppShotMetadataWithAXTreeText() {
        let screenshot = localImageAttachment(label: "appshot.png", path: "/tmp/appshot.png")
        let message = ConversationEventRecord(conversationId: "conversation", type: "message", role: "user", content: "Describe")
        message.setPersistedTranscriptAttachments(
            images: [],
            persistedAppShots: [
                PersistedAppShotAttachment(
                    screenshot: screenshot,
                    appName: "Preview",
                    bundleIdentifier: "com.apple.Preview",
                    windowTitle: "Window title"
                )
            ]
        )
        let runtimeAppShot = AppShotAttachment(
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Window title",
            screenshot: screenshot,
            axTreeText: "AX window tree",
            focusedElementSummary: "focused button",
            attachmentStoreRoot: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )

        let attachmentsByID = ChatTranscriptView.transcriptImageAttachmentsByMessageID(
            events: [message],
            runtimeImageAttachments: [:],
            runtimeAppShots: [message.id: [runtimeAppShot]]
        )

        XCTAssertEqual(attachmentsByID[message.id]?.first?.appShot?.axTreeText, "AX window tree")
    }

    func testTextBubbleRenderedContentChangesWhenAppShotMetadataChanges() {
        let screenshot = localImageAttachment(label: "appshot.png", path: "/tmp/appshot.png")
        let first = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "user",
            role: .user,
            markdown: "Describe",
            imageAttachments: [
                TranscriptImageAttachment(appShot: PersistedAppShotAttachment(
                    screenshot: screenshot,
                    appName: "Preview",
                    bundleIdentifier: "com.apple.Preview",
                    windowTitle: "First"
                ))
            ]
        )
        let second = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "user",
            role: .user,
            markdown: "Describe",
            imageAttachments: [
                TranscriptImageAttachment(appShot: PersistedAppShotAttachment(
                    screenshot: screenshot,
                    appName: "Preview",
                    bundleIdentifier: "com.apple.Preview",
                    windowTitle: "Second"
                ))
            ]
        )

        XCTAssertFalse(first.hasSameRenderedContent(as: second))
    }

    func testTextBubbleRenderedContentChangesWhenAppShotAXTreeTextChanges() {
        let screenshot = localImageAttachment(label: "appshot.png", path: "/tmp/appshot.png")
        let first = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "user",
            role: .user,
            markdown: "Describe",
            imageAttachments: [
                TranscriptImageAttachment(appShot: PersistedAppShotAttachment(
                    screenshot: screenshot,
                    appName: "Preview",
                    bundleIdentifier: "com.apple.Preview",
                    windowTitle: "Window",
                    axTreeText: "First AX tree"
                ))
            ]
        )
        let second = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "user",
            role: .user,
            markdown: "Describe",
            imageAttachments: [
                TranscriptImageAttachment(appShot: PersistedAppShotAttachment(
                    screenshot: screenshot,
                    appName: "Preview",
                    bundleIdentifier: "com.apple.Preview",
                    windowTitle: "Window",
                    axTreeText: "Second AX tree"
                ))
            ]
        )

        XCTAssertFalse(first.hasSameRenderedContent(as: second))
    }

    func testTranscriptImageAttachmentPreviewRequestIncludesOnlyAppShotAXTreeText() throws {
        let plain = localImageAttachment(label: "plain.png", path: "/tmp/plain.png")
        let appShot = PersistedAppShotAttachment(
            screenshot: localImageAttachment(label: "appshot.png", path: "/tmp/appshot.png"),
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Window title",
            axTreeText: "AX window tree"
        )

        let plainRequest = AppImagePreviewRequest.transcriptImageAttachment(
            TranscriptImageAttachment(localImageAttachment: plain)
        )
        let appShotRequest = AppImagePreviewRequest.transcriptImageAttachment(
            TranscriptImageAttachment(appShot: appShot)
        )

        XCTAssertNil(plainRequest.textPayload)
        XCTAssertEqual(appShotRequest.title, "Window title")
        XCTAssertEqual(try XCTUnwrap(appShotRequest.textPayload).text, "AX window tree")
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
