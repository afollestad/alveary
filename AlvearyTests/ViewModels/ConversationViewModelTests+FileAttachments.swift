import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testFileOnlyRetryableContentUsesFileAttachments() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let attachment = viewModelFileAttachment(label: "report.pdf")
        let localMessage = fixture.viewModel.insertLocalUserMessage(
            "",
            into: try fixture.dbConversation(),
            fileAttachments: [attachment]
        )
        fixture.viewModel.state.markRetryableFailedMessage(
            id: localMessage.id,
            stagedContext: nil,
            fileAttachments: [attachment]
        )

        try await fixture.viewModel.retryFailedUserMessage(id: localMessage.id)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [""])
        XCTAssertFalse(fixture.viewModel.state.retryableFailedMessageIDs.contains(localMessage.id))
        XCTAssertEqual(fixture.viewModel.state.transcriptFileAttachments[localMessage.id], [attachment])
    }

    func testFileOnlySendCanRetryWithFileAttachmentMetadata() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let attachment = viewModelFileAttachment(label: "report.pdf")
        fixture.viewModel.state.stagedFileAttachments = [attachment]
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))

        do {
            try await fixture.viewModel.send("")
            XCTFail("Expected file-only send to fail")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .sendFailed)
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(failedMessage.content, attachment.markdownLink)
        XCTAssertEqual(failedMessage.persistedFileAttachments, [attachment])
        XCTAssertEqual(fixture.viewModel.state.retryableFailedMessageFileAttachments[failedMessage.id], [attachment])

        await fixture.agentsManager.enqueueSendResult(.success(()))
        try await fixture.viewModel.retryFailedUserMessage(id: failedMessage.id)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [attachment.markdownLink])
        XCTAssertFalse(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertEqual(fixture.viewModel.state.transcriptFileAttachments[failedMessage.id], [attachment])
    }

    func testQueuedMessagePreservesFileAttachmentsUntilDrained() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.turnState.beginTurn()
        let attachment = viewModelFileAttachment(label: "queued.pdf")
        fixture.viewModel.state.stagedFileAttachments = [attachment]

        try await fixture.viewModel.queueOrSend("Follow-up")

        let expectedVisibleText = "Follow-up\n\n\(attachment.markdownLink)"
        let queued = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext())
        XCTAssertEqual(queued.text, expectedVisibleText)
        XCTAssertEqual(queued.fileAttachments, [attachment])
        XCTAssertTrue(fixture.viewModel.state.stagedFileAttachments.isEmpty)

        fixture.viewModel.turnState.endTurn()
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("queued file attachment sent") {
            await fixture.agentsManager.sentMessages() == [expectedVisibleText]
        }
        let userMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(userMessage.content, expectedVisibleText)
        XCTAssertEqual(userMessage.persistedFileAttachments, [attachment])
        XCTAssertEqual(fixture.viewModel.state.transcriptFileAttachments[userMessage.id], [attachment])
    }

    func testQueuedSteerPreservesFileAttachments() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.turnState.beginTurn()
        let attachment = viewModelFileAttachment(label: "steer.pdf")
        fixture.viewModel.state.stagedFileAttachments = [attachment]

        try await fixture.viewModel.queueOrSend("Queued steer")
        let queuedID = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext()?.id)
        try await fixture.viewModel.steerQueuedMessage(id: queuedID)

        let expectedVisibleText = "Queued steer\n\n\(attachment.markdownLink)"
        let sentMessages = await fixture.agentsManager.sentMessages()
        let userMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(sentMessages, [expectedVisibleText])
        XCTAssertEqual(userMessage.content, expectedVisibleText)
        XCTAssertEqual(userMessage.persistedFileAttachments, [attachment])
        XCTAssertEqual(fixture.viewModel.state.transcriptFileAttachments[userMessage.id], [attachment])
        XCTAssertEqual(fixture.viewModel.messageQueue.peekNext(), nil)
    }

    func testFirstSendSetupFailureKeepsRetryableTranscriptAttemptAndRestoresStagedFile() async throws {
        let fixture = try ConversationViewModelTestFixture(
            threadName: "New thread",
            useWorktree: true,
            hasCompletedInitialSetup: false,
            worktreeInfo: WorktreeInfo(path: "/tmp/alveary-worktree", branch: "alveary/fix-auth")
        )
        await fixture.worktreeManager.enqueueCreateResult(.failure(.createFailed))

        let message = "Implement the authentication retry flow"
        let fileAttachment = viewModelFileAttachment(label: "setup-notes.pdf")
        fixture.viewModel.state.stagedContext = "Context block"
        fixture.viewModel.state.stagedFileAttachments = [fileAttachment]
        do {
            try await fixture.viewModel.queueOrSend(message)
            XCTFail("Expected setup to throw")
        } catch let error as MockWorktreeManager.MockError {
            XCTAssertEqual(error, .createFailed)
        }

        let expectedVisibleText = "\(message)\n\n\(fileAttachment.markdownLink)"
        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(failedMessage.content, expectedVisibleText)
        XCTAssertEqual(failedMessage.persistedFileAttachments, [fileAttachment])
        XCTAssertEqual(try fixture.userMessages().count, 1)
        XCTAssertEqual(fixture.viewModel.state.retryableFailedMessageStagedContexts[failedMessage.id], "Context block")
        XCTAssertEqual(fixture.viewModel.state.retryableFailedMessageFileAttachments[failedMessage.id], [fileAttachment])
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(fixture.viewModel.state.stagedContext)
        XCTAssertEqual(fixture.viewModel.state.stagedFileAttachments, [fileAttachment])
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
        XCTAssertNil(fixture.viewModel.setupPhase)

        try await fixture.viewModel.retryFailedUserMessage(id: failedMessage.id)

        let retriedMessages = try fixture.userMessages()
        XCTAssertEqual(retriedMessages.map(\.id), [failedMessage.id])
        XCTAssertEqual(retriedMessages.map(\.content), [expectedVisibleText])
        XCTAssertFalse(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertNil(fixture.viewModel.state.retryableFailedMessageFileAttachments[failedMessage.id])
        XCTAssertTrue(fixture.viewModel.state.stagedFileAttachments.isEmpty)
        XCTAssertTrue(try fixture.dbThread().hasCompletedInitialSetup)
        let createCalls = await fixture.worktreeManager.createCalls()
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(createCalls.count, 2)
        XCTAssertEqual(spawnCalls.first?.config.initialPrompt, "Context block\n\n\(expectedVisibleText)")
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }
}

private func viewModelFileAttachment(label: String) -> LocalFileAttachment {
    LocalFileAttachment(
        id: UUID().uuidString,
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(label),
        label: label,
        createdAt: Date()
    )
}
