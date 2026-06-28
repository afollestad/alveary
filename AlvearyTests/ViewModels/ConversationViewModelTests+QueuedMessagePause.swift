import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testQueuedMessagePauseBlocksDrainUntilResume() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.state.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .interrupted))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(fixture.viewModel.state.queuedMessagesPauseReason, .interrupted)
        XCTAssertEqual(fixture.viewModel.messageQueue.peekNext()?.text, "Follow-up")
        let sentMessagesBeforeResume = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessagesBeforeResume.isEmpty)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)

        fixture.viewModel.resumeQueuedMessages()

        try await waitUntil("queued message sent after resume") {
            await fixture.agentsManager.sentMessages() == ["Follow-up"] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }
        XCTAssertNil(fixture.viewModel.state.queuedMessagesPauseReason)
        XCTAssertFalse(fixture.viewModel.state.lastTurnInterrupted)
    }

    func testResumeQueuedMessagesStillHonorsLifecycleAndReadinessGates() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        await fixture.agentsManager.enqueueRefreshStatus(.idle)
        await fixture.agentsManager.pauseNextRefreshStatus()
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.state.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .interrupted))
        XCTAssertEqual(fixture.viewModel.state.queuedMessagesPauseReason, .interrupted)

        fixture.viewModel.resumeQueuedMessages()
        try await waitUntil("resume starts status refresh") {
            await fixture.agentsManager.refreshStatusCalls() == [fixture.conversation.id]
        }
        XCTAssertNil(fixture.viewModel.state.queuedMessagesPauseReason)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)

        fixture.viewModel.deactivateViewLifecycle()
        await fixture.agentsManager.resumePausedRefreshStatus()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(fixture.viewModel.messageQueue.peekNext()?.text, "Follow-up")
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testQueueOrSendWhilePausedAppendsAndStaysPaused() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.state.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("First")
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .interrupted))
        try await fixture.viewModel.queueOrSend("Second")

        XCTAssertEqual(fixture.viewModel.state.queuedMessagesPauseReason, .interrupted)
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["First", "Second"])
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testQueuedPauseClearsOnlyWhenQueueEmpties() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.messageQueue.enqueue("First", stagedContext: nil)
        fixture.viewModel.state.messageQueue.enqueue("Second", stagedContext: nil)
        fixture.viewModel.state.queuedMessagesPauseReason = .interrupted

        let firstID = try XCTUnwrap(fixture.viewModel.messageQueue.pending.first?.id)
        fixture.viewModel.removeQueuedMessage(id: firstID)
        XCTAssertEqual(fixture.viewModel.state.queuedMessagesPauseReason, .interrupted)

        let secondID = try XCTUnwrap(fixture.viewModel.messageQueue.pending.first?.id)
        fixture.viewModel.editQueuedMessage(id: secondID)
        XCTAssertNil(fixture.viewModel.state.queuedMessagesPauseReason)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Second")
    }

    func testQueuedPauseClearsOnlyWhenSteeredQueueEmpties() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.turnState.beginTurn()
        fixture.viewModel.state.messageQueue.enqueue("First", stagedContext: nil)
        fixture.viewModel.state.messageQueue.enqueue("Second", stagedContext: nil)
        fixture.viewModel.state.queuedMessagesPauseReason = .interrupted

        let firstID = try XCTUnwrap(fixture.viewModel.messageQueue.pending.first?.id)
        try await fixture.viewModel.steerQueuedMessage(id: firstID)
        XCTAssertEqual(fixture.viewModel.state.queuedMessagesPauseReason, .interrupted)

        let secondID = try XCTUnwrap(fixture.viewModel.messageQueue.pending.first?.id)
        try await fixture.viewModel.steerQueuedMessage(id: secondID)

        XCTAssertNil(fixture.viewModel.state.queuedMessagesPauseReason)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["First", "Second"])
    }

    func testPausedQueuePreservesQueuedMessagePayloadOnResume() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.state.runtimePlanModeEnabled = true
        fixture.viewModel.state.turnState.beginTurn()

        let payload = makePausedQueuePayload()
        fixture.viewModel.state.messageQueue.enqueue(
            "Visible [file](file:///tmp/report.txt)",
            stagedContext: "Context",
            requiredPlanModeEnabled: true,
            requiredSpeedMode: .fast,
            transportText: "Transport [file](file:///tmp/report.txt)",
            attachments: [payload.image],
            appShots: [payload.appShot],
            providerMetadata: ["codex-test": .string("metadata")],
            consumedExitPlanModeRevisionGuidance: payload.revisionGuidance
        )

        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .interrupted))
        let queued = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext())

        XCTAssertEqual(fixture.viewModel.state.queuedMessagesPauseReason, .interrupted)
        XCTAssertEqual(queued.text, "Visible [file](file:///tmp/report.txt)")
        XCTAssertEqual(queued.transportText, "Transport [file](file:///tmp/report.txt)")
        XCTAssertEqual(queued.stagedContext, "Context")
        XCTAssertEqual(queued.requiredPlanModeEnabled, true)
        XCTAssertEqual(queued.requiredSpeedMode, .fast)
        XCTAssertEqual(queued.attachments, [payload.image])
        XCTAssertEqual(queued.appShots, [payload.appShot])
        XCTAssertEqual(queued.providerMetadata["codex-test"], .string("metadata"))
        XCTAssertEqual(queued.consumedExitPlanModeRevisionGuidance, payload.revisionGuidance)

        fixture.viewModel.resumeQueuedMessages()

        try await waitUntil("paused queued payload sent after resume") {
            await fixture.agentsManager.sentMessages() == ["Context\n\nTransport [file](file:///tmp/report.txt)"] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }

        let sentAttachments = await fixture.agentsManager.sentAttachments()
        let sentMetadata = await fixture.agentsManager.sentMetadata()
        let userMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(sentAttachments, [[payload.image]])
        XCTAssertEqual(sentMetadata, [["codex-test": .string("metadata")]])
        XCTAssertEqual(userMessage.content, "Visible [file](file:///tmp/report.txt)")
        XCTAssertEqual(userMessage.persistedImageAttachments, [payload.image])
        XCTAssertEqual(userMessage.persistedAppShotAttachments, [PersistedAppShotAttachment(appShot: payload.appShot)])
        XCTAssertEqual(fixture.viewModel.state.transcriptAppShots[userMessage.id], [payload.appShot])
    }
}

private struct PausedQueuePayload {
    let image: LocalImageAttachment
    let appShot: AppShotAttachment
    let revisionGuidance: PendingExitPlanModeRevisionGuidance
}

private func makePausedQueuePayload() -> PausedQueuePayload {
    let image = LocalImageAttachment(
        id: "image-1",
        fileURL: URL(fileURLWithPath: "/tmp/screen.png"),
        label: "screen.png",
        createdAt: Date()
    )
    return PausedQueuePayload(
        image: image,
        appShot: AppShotAttachment(
            id: "app-shot-1",
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Window",
            screenshot: image,
            axTreeText: "AX",
            focusedElementSummary: "Focused",
            attachmentStoreRoot: URL(fileURLWithPath: "/tmp", isDirectory: true)
        ),
        revisionGuidance: PendingExitPlanModeRevisionGuidance(
            toolUseId: "exit-plan-1",
            sessionId: "session-1",
            providerId: "claude",
            providerSessionId: nil
        )
    )
}
