import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testApprovalRestoreReturnsFromMountAndBlocksOutboundUntilReadCompletes() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = try insertAsyncRestoreApproval(in: fixture)
        let reader = SuspendedApprovalTranscriptReader()
        fixture.viewModel.readToolApprovalTranscript = { await reader.read($0) }
        fixture.viewModel.state.messageQueue.enqueue("Wait for approval")

        fixture.viewModel.activateViewLifecycle()
        XCTAssertTrue(fixture.viewModel.state.isRestoringToolApproval)
        fixture.viewModel.hydratePendingToolApprovalIfNeeded()
        try await waitUntil("approval read started without blocking the main actor") { await reader.callCount == 1 }
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertFalse(fixture.viewModel.canSubmitPromptAnswer(promptId: approval.toolUseId))
        XCTAssertFalse(fixture.viewModel.canApplySettingsChange)
        XCTAssertFalse(fixture.viewModel.isReadyForExistingScheduledTask)
        XCTAssertThrowsError(try fixture.viewModel.ensureCanReserveOutbound())
        XCTAssertThrowsError(try fixture.viewModel.validatePromptDismissalAvailable())
        do {
            try await fixture.viewModel.approveToolUse(approval)
            XCTFail("A recovering approval must not reach the provider")
        } catch {}
        do {
            try await fixture.viewModel.startAutomatedScheduledTurn("Wait for recovery")
            XCTFail("Scheduled runtime preparation must wait for approval recovery")
        } catch {}
        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(calls.isEmpty)
        let messages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(messages.isEmpty)

        let task = fixture.viewModel.toolApprovalRestoreTask
        await reader.finishRead(at: 0, with: nil)
        await task?.value
        XCTAssertFalse(fixture.viewModel.state.isRestoringToolApproval)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, approval)
        fixture.viewModel.deactivateViewLifecycle()
    }

    func testApprovalRestoreCancellationDoesNotClearReplacementMountRead() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = try insertAsyncRestoreApproval(in: fixture)
        let reader = SuspendedApprovalTranscriptReader()
        fixture.viewModel.readToolApprovalTranscript = { await reader.read($0) }
        fixture.viewModel.activateViewLifecycle()
        try await waitUntil("first restore read started") { await reader.callCount == 1 }
        let oldTask = fixture.viewModel.toolApprovalRestoreTask

        fixture.viewModel.deactivateViewLifecycle()
        XCTAssertFalse(fixture.viewModel.state.isRestoringToolApproval)
        fixture.viewModel.activateViewLifecycle()
        try await waitUntil("replacement restore read started") { await reader.callCount == 2 }
        let newTask = fixture.viewModel.toolApprovalRestoreTask
        await reader.finishRead(at: 0, with: .approved)
        await oldTask?.value
        XCTAssertTrue(fixture.viewModel.state.isRestoringToolApproval)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertNil(try fixture.records(type: "tool_approval").first?.toolApprovalStatus)

        await reader.finishRead(at: 1, with: nil)
        await newTask?.value
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, approval)
        fixture.viewModel.deactivateViewLifecycle()
    }

    func testApprovalRestoreIgnoresResolvedRecordAndReplacementLiveApproval() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        _ = try insertAsyncRestoreApproval(in: fixture)
        let reader = SuspendedApprovalTranscriptReader()
        fixture.viewModel.readToolApprovalTranscript = { await reader.read($0) }
        fixture.viewModel.hydratePendingToolApprovalIfNeeded()
        try await waitUntil("restore read started") { await reader.callCount == 1 }
        let task = fixture.viewModel.toolApprovalRestoreTask
        let record = try XCTUnwrap(fixture.records(type: "tool_approval").first)
        record.toolApprovalStatus = ToolApprovalStatus.denied.rawValue
        let replacement = ToolApprovalRequest(sessionId: "new-session", toolUseId: "new-tool", toolName: "Read", toolInput: "{}")
        fixture.viewModel.replacePendingToolApproval(with: replacement)
        XCTAssertFalse(fixture.viewModel.state.isRestoringToolApproval)
        try fixture.context.save()

        await reader.finishRead(at: 0, with: .approved)
        await task?.value
        XCTAssertEqual(record.toolApprovalStatus, ToolApprovalStatus.denied.rawValue)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, replacement)
        XCTAssertFalse(fixture.viewModel.state.isRestoringToolApproval)
    }

    func testOldControllerDeinitDoesNotUnblockReplacementControllerRecovery() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = try insertAsyncRestoreApproval(in: fixture)
        let reader = SuspendedApprovalTranscriptReader()
        var original: ConversationViewModel? = makeRecoveryController(fixture: fixture, reader: reader)
        let originalWasReleased = { [weak controller = original] in controller == nil }
        original?.activateViewLifecycle()
        try await waitUntil("first controller read started") { await reader.callCount == 1 }
        let oldTask = original?.toolApprovalRestoreTask
        original?.deactivateViewLifecycle()
        original = nil
        let replacement = makeRecoveryController(fixture: fixture, reader: reader)
        replacement.activateViewLifecycle()
        try await waitUntil("replacement controller read started") { await reader.callCount == 2 }
        let newTask = replacement.toolApprovalRestoreTask
        await reader.finishRead(at: 0, with: .approved)
        await oldTask?.value
        try await waitUntil("old controller released") { originalWasReleased() }
        XCTAssertTrue(replacement.state.isRestoringToolApproval)
        XCTAssertThrowsError(try replacement.ensureCanReserveOutbound())
        await reader.finishRead(at: 1, with: nil)
        await newTask?.value
        XCTAssertEqual(replacement.state.pendingToolApproval?.request, approval)
        replacement.deactivateViewLifecycle()
    }

    func testActionTimeApprovalReadPreservesLiveOnlyRequest() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let approval = ToolApprovalRequest(
            sessionId: "live-session", toolUseId: "live-prompt", toolName: "AskUserQuestion", toolInput: "{}",
            approvalIdentityToolInput: "original input"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        fixture.viewModel.readToolApprovalTranscript = { _ in nil }

        let resolution = try await fixture.viewModel.clearResolvedToolApprovalFromClaudeSessionIfNeeded(approval)

        XCTAssertNil(resolution)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, approval)
    }

    func testApprovalRestoreIgnoresStateReplacementAndDeletedConversation() async throws {
        for deletesConversation in [false, true] {
            let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
            _ = try insertAsyncRestoreApproval(in: fixture)
            let reader = SuspendedApprovalTranscriptReader()
            fixture.viewModel.readToolApprovalTranscript = { await reader.read($0) }
            fixture.viewModel.hydratePendingToolApprovalIfNeeded()
            try await waitUntil("restore read started") { await reader.callCount == 1 }
            let task = fixture.viewModel.toolApprovalRestoreTask
            if deletesConversation {
                fixture.context.delete(fixture.conversation)
                try fixture.context.save()
            } else {
                fixture.viewModel.replaceState(with: ConversationState())
            }
            await reader.finishRead(at: 0, with: .approved)
            await task?.value
            XCTAssertFalse(fixture.viewModel.state.isRestoringToolApproval)
            XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        }
    }

    func testActionTimeApprovalReadRejectsChangedProviderSession() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = try insertAsyncRestoreApproval(in: fixture)
        let reader = SuspendedApprovalTranscriptReader()
        fixture.viewModel.readToolApprovalTranscript = { await reader.read($0) }
        let task = Task { try await fixture.viewModel.clearResolvedToolApprovalFromClaudeSessionIfNeeded(approval) }
        try await waitUntil("action-time read started") { await reader.callCount == 1 }
        let record = try XCTUnwrap(fixture.records(type: "tool_approval").first)
        fixture.conversation.providerSessionId = "replacement-session"
        try fixture.context.save()
        await reader.finishRead(at: 0, with: .approved)
        do {
            _ = try await task.value
            XCTFail("A stale session's decision must not be applied")
        } catch is CancellationError {
            XCTAssertNil(record.toolApprovalStatus)
        }
    }

    func testApprovalRestoreAcceptsInitialBindingForTheSameProviderSession() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = try insertAsyncRestoreApproval(in: fixture)
        let reader = SuspendedApprovalTranscriptReader()
        fixture.viewModel.readToolApprovalTranscript = { await reader.read($0) }
        fixture.viewModel.hydratePendingToolApprovalIfNeeded()
        try await waitUntil("restore read started") { await reader.callCount == 1 }
        let task = fixture.viewModel.toolApprovalRestoreTask
        fixture.conversation.providerSessionId = approval.sessionId
        try fixture.context.save()

        await reader.finishRead(at: 0, with: .approved)
        await task?.value

        XCTAssertFalse(fixture.viewModel.state.isRestoringToolApproval)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(try fixture.records(type: "tool_approval").first?.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
    }

    func testApprovalRestoreRechecksReplacementRecordBeforeUnblockingOutbound() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        _ = try insertAsyncRestoreApproval(in: fixture)
        let reader = SuspendedApprovalTranscriptReader()
        fixture.viewModel.readToolApprovalTranscript = { await reader.read($0) }
        fixture.viewModel.hydratePendingToolApprovalIfNeeded()
        try await waitUntil("first restore read started") { await reader.callCount == 1 }
        let oldTask = fixture.viewModel.toolApprovalRestoreTask
        let record = try XCTUnwrap(fixture.records(type: "tool_approval").first)
        record.toolApprovalStatus = ToolApprovalStatus.approved.rawValue
        fixture.context.insert(ConversationEventRecord(
            conversationId: fixture.conversation.id, type: "tool_approval", content: "restore-session",
            toolId: "replacement-tool", toolName: "Read", toolInput: "{}", conversation: fixture.conversation
        ))
        try fixture.context.save()
        await reader.finishRead(at: 0, with: .approved)
        await oldTask?.value
        try await waitUntil("replacement approval read started") { await reader.callCount == 2 }
        XCTAssertTrue(fixture.viewModel.state.isRestoringToolApproval)
        XCTAssertThrowsError(try fixture.viewModel.ensureCanReserveOutbound())
        let newTask = fixture.viewModel.toolApprovalRestoreTask
        await reader.finishRead(at: 1, with: nil)
        await newTask?.value
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request.toolUseId, "replacement-tool")
    }

    private func insertAsyncRestoreApproval(in fixture: ConversationViewModelTestFixture) throws -> ToolApprovalRequest {
        let approval = ToolApprovalRequest(sessionId: "restore-session", toolUseId: "restore-tool", toolName: "Bash", toolInput: "{}")
        fixture.context.insert(ConversationEventRecord(
            conversationId: fixture.conversation.id,
            type: "tool_approval",
            content: approval.sessionId,
            toolId: approval.toolUseId,
            toolName: approval.toolName,
            toolInput: approval.toolInput,
            conversation: fixture.conversation
        ))
        try fixture.context.save()
        return approval
    }

    private func makeRecoveryController(
        fixture: ConversationViewModelTestFixture,
        reader: SuspendedApprovalTranscriptReader
    ) -> ConversationViewModel {
        let controller = ConversationViewModel(
            conversation: fixture.conversation,
            agentsManager: fixture.agentsManager,
            runtimeStore: fixture.runtimeStore,
            keepAwakeService: fixture.keepAwakeService,
            modelContext: fixture.context,
            settingsService: fixture.settingsService,
            worktreeManager: fixture.worktreeManager,
            providerSetup: fixture.providerSetup,
            contextWindowCache: fixture.contextWindowCache
        )
        controller.readToolApprovalTranscript = { await reader.read($0) }
        return controller
    }
}

private actor SuspendedApprovalTranscriptReader {
    private var continuations: [CheckedContinuation<ToolApprovalStatus?, Never>?] = []
    var callCount: Int { continuations.count }

    func read(_ lookup: ToolApprovalTranscriptLookup) async -> ToolApprovalStatus? {
        await withCheckedContinuation { continuations.append($0) }
    }

    func finishRead(at index: Int, with status: ToolApprovalStatus?) {
        continuations[index]?.resume(returning: status)
        continuations[index] = nil
    }
}
