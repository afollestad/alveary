import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testStageLocalImageAttachmentsCopiesImagesIntoConversationStore() async throws {
        let root = temporaryDirectory()
        let sourceDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let imageURL = sourceDirectory.appendingPathComponent("screen shot.png")
        let textURL = sourceDirectory.appendingPathComponent("notes.txt")
        try Self.pngHeaderData.write(to: imageURL)
        try "not an image".write(to: textURL, atomically: true, encoding: .utf8)

        let store = DefaultConversationAttachmentStore(rootDirectory: root)
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)

        try await fixture.viewModel.stageLocalImageAttachments(from: [imageURL, textURL])

        let attachment = try XCTUnwrap(fixture.viewModel.stagedImageAttachments.first)
        XCTAssertEqual(fixture.viewModel.stagedImageAttachments.count, 1)
        XCTAssertEqual(attachment.label, "screen shot.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.fileURL.path))
        XCTAssertTrue(attachment.fileURL.path.hasPrefix(root.path))
        XCTAssertTrue(attachment.fileURL.path.contains(fixture.conversation.id))
    }

    func testSupportedProviderSendUsesImageAttachmentsWithoutMarkdownFallback() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let attachment = localImageAttachment(label: "diagram.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]

        try await fixture.viewModel.send("Describe this", supportsLocalImageInput: true)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        XCTAssertEqual(sentMessages, ["Describe this"])
        XCTAssertEqual(sentAttachments, [[attachment]])
        XCTAssertTrue(fixture.viewModel.state.stagedImageAttachments.isEmpty)
        let userMessages = try fixture.userMessages()
        XCTAssertEqual(userMessages.map(\.content), ["Describe this"])
        XCTAssertEqual(
            fixture.viewModel.state.transcriptImageAttachments[try XCTUnwrap(userMessages.first?.id)],
            [attachment]
        )
    }

    func testUnsupportedProviderSendConvertsStagedImagesToMarkdownText() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let attachment = localImageAttachment(label: "diagram.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]

        try await fixture.viewModel.send("Describe this", supportsLocalImageInput: false)

        let fallbackText = "Describe this\n\n\(attachment.markdownImageLink)"
        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        XCTAssertEqual(sentMessages, [fallbackText])
        XCTAssertEqual(sentAttachments, [[]])
        XCTAssertTrue(fixture.viewModel.state.stagedImageAttachments.isEmpty)
        XCTAssertEqual(try fixture.userMessages().map(\.content), [fallbackText])
    }

    func testImageOnlySendCanRetryWithAttachments() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let attachment = localImageAttachment(label: "screen.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))

        do {
            try await fixture.viewModel.send("", supportsLocalImageInput: true)
            XCTFail("Expected image-only send to fail")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .sendFailed)
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(failedMessage.content, "")
        XCTAssertEqual(fixture.viewModel.state.retryableFailedMessageAttachments[failedMessage.id], [attachment])

        await fixture.agentsManager.enqueueSendResult(.success(()))
        try await fixture.viewModel.retryFailedUserMessage(id: failedMessage.id)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        XCTAssertEqual(sentMessages, [""])
        XCTAssertEqual(sentAttachments, [[attachment]])
        XCTAssertFalse(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertEqual(fixture.viewModel.state.transcriptImageAttachments[failedMessage.id], [attachment])
    }

    func testQueuedMessagePreservesImageAttachmentsUntilDrained() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.turnState.beginTurn()
        let attachment = localImageAttachment(label: "queued.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]

        try await fixture.viewModel.queueOrSend("Follow-up", supportsLocalImageInput: true)

        let queued = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext())
        XCTAssertEqual(queued.text, "Follow-up")
        XCTAssertEqual(queued.attachments, [attachment])
        XCTAssertTrue(fixture.viewModel.state.stagedImageAttachments.isEmpty)

        fixture.viewModel.turnState.endTurn()
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("queued image attachment sent") {
            await fixture.agentsManager.sentAttachments() == [[attachment]]
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Follow-up"])
        let userMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(fixture.viewModel.state.transcriptImageAttachments[userMessage.id], [attachment])
    }

    func testSteeringSendsImageAttachments() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.turnState.beginTurn()
        let attachment = localImageAttachment(label: "steer.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]

        try await fixture.viewModel.steer("Use this", supportsLocalImageInput: true)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        let userMessages = try fixture.userMessages()
        XCTAssertEqual(sentMessages, ["Use this"])
        XCTAssertEqual(sentAttachments, [[attachment]])
        XCTAssertEqual(try XCTUnwrap(userMessages.first?.content), "Use this")
        XCTAssertEqual(
            fixture.viewModel.state.transcriptImageAttachments[try XCTUnwrap(userMessages.first?.id)],
            [attachment]
        )
        let steeringCalls = await fixture.agentsManager.steeringCalls()
        XCTAssertEqual(steeringCalls, [
            .init(
                message: "Use this",
                conversationId: fixture.conversation.id,
                steeringInputID: try XCTUnwrap(userMessages.first?.id),
                attachments: [attachment]
            )
        ])
    }

    func testTypedMarkdownImageRemainsTextOnly() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let markdown = "Inspect ![Existing](existing.png)"

        try await fixture.viewModel.send(markdown, supportsLocalImageInput: true)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        XCTAssertEqual(sentMessages, [markdown])
        XCTAssertEqual(sentAttachments, [[]])
        XCTAssertEqual(try fixture.userMessages().map(\.content), [markdown])
    }

    func testCleanupRetainsTranscriptImageAttachments() async throws {
        let root = temporaryDirectory()
        let sourceDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let sentImageURL = sourceDirectory.appendingPathComponent("sent.png")
        let removedImageURL = sourceDirectory.appendingPathComponent("removed.png")
        try Self.pngHeaderData.write(to: sentImageURL)
        try Self.pngHeaderData.write(to: removedImageURL)

        let store = DefaultConversationAttachmentStore(rootDirectory: root)
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)

        try await fixture.viewModel.stageLocalImageAttachments(from: [sentImageURL])
        let sentAttachment = try XCTUnwrap(fixture.viewModel.stagedImageAttachments.first)
        try await fixture.viewModel.send("Describe this", supportsLocalImageInput: true)

        try await fixture.viewModel.stageLocalImageAttachments(from: [removedImageURL])
        let removedAttachment = try XCTUnwrap(fixture.viewModel.stagedImageAttachments.first)
        fixture.viewModel.removeStagedImageAttachment(id: removedAttachment.id)

        try await waitUntil("removed image attachment cleaned up") {
            !FileManager.default.fileExists(atPath: removedAttachment.fileURL.path)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentAttachment.fileURL.path))
    }
}

private func localImageAttachment(label: String) -> LocalImageAttachment {
    LocalImageAttachment(
        id: UUID().uuidString,
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(label),
        label: label,
        createdAt: Date()
    )
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private extension ConversationViewModelTests {
    static let pngHeaderData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}
