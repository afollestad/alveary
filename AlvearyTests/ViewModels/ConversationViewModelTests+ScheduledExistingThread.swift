import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testClaimedExistingTargetRunFencesOrdinaryOutboundBeforeExecutorStarts() async throws {
        let fixture = try ConversationViewModelTestFixture(hasCompletedInitialSetup: true)
        let run = ScheduledTaskRun(
            occurrenceID: "claimed-target-occurrence",
            definitionID: "claimed-target-definition",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
            triggerKind: .scheduled,
            status: .claimed,
            titleSnapshot: "Attached schedule",
            promptSnapshot: "Continue existing work.",
            destinationSnapshot: .existingThread,
            targetConversationIDSnapshot: fixture.conversation.id,
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: fixture.conversation.provider ?? "claude",
            effortSnapshot: fixture.thread.effort,
            permissionModeSnapshot: fixture.thread.permissionMode,
            workspaceKindSnapshot: .project,
            workspaceStrategySnapshot: .localCheckout,
            projectPathSnapshot: fixture.project.path,
            targetThread: fixture.thread
        )
        fixture.context.insert(run)
        try fixture.context.save()

        XCTAssertTrue(fixture.viewModel.defersOrdinaryScheduledOutbound)
        XCTAssertFalse(fixture.viewModel.canApplySettingsChange)
        await XCTAssertThrowsErrorAsync {
            try await fixture.viewModel.send("Manual message")
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testAutomatedScheduledTurnContinuesAttachedExistingConversationInPlace() async throws {
        let ownershipService = RecoveryWorkspaceOwnershipService()
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            taskWorkspaceOwnershipService: ownershipService
        )
        fixture.thread.isPinned = true
        let workspaceIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 10, fileNumber: 20)
        ownershipService.setIdentity(workspaceIdentity, at: fixture.project.path)
        let run = makeExistingTargetRun(fixture: fixture, workspaceIdentity: workspaceIdentity)
        fixture.context.insert(run)
        try fixture.context.save()
        fixture.viewModel.beginAutomatedScheduledRunExecution(runID: run.id)
        defer { fixture.viewModel.finishAutomatedScheduledRunExecution() }
        XCTAssertEqual(fixture.runtimeStore.automatedScheduledRunID(threadKey: fixture.conversation.id), run.id)

        try await fixture.viewModel.startAutomatedScheduledTurn("Continue existing work.")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Continue existing work."])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Continue existing work."])
        XCTAssertTrue(fixture.thread.hasCompletedInitialSetup)
        XCTAssertNil(run.thread)
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let suspendCalls = await fixture.agentsManager.suspendCalls()
        let spawnConfig = try XCTUnwrap(spawnCalls.first?.config)
        XCTAssertEqual(suspendCalls, [fixture.conversation.id])
        XCTAssertEqual(spawnConfig.providerId, run.providerIDSnapshot)
        XCTAssertEqual(spawnConfig.model, run.modelSnapshot)
        XCTAssertEqual(spawnConfig.effort, run.effortSnapshot)
        XCTAssertEqual(spawnConfig.permissionMode, run.permissionModeSnapshot)
        XCTAssertEqual(spawnConfig.planModeEnabled, run.planModeEnabledSnapshot)
        XCTAssertEqual(spawnConfig.speedMode?.rawValue, run.speedModeSnapshot)
        XCTAssertTrue(spawnConfig.isAutomatedScheduledTurn)
        XCTAssertTrue(spawnConfig.hostTools.isEmpty)
        fixture.viewModel.finishAutomatedScheduledRunExecution()
        XCTAssertNil(fixture.runtimeStore.automatedScheduledRunID(threadKey: fixture.conversation.id))
    }

    func testExistingScheduledTurnRevalidatesTargetAfterRuntimeSpawn() async throws {
        let ownershipService = RecoveryWorkspaceOwnershipService()
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            taskWorkspaceOwnershipService: ownershipService
        )
        fixture.thread.isPinned = true
        let workspaceIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 30, fileNumber: 40)
        ownershipService.setIdentity(workspaceIdentity, at: fixture.project.path)
        let run = makeExistingTargetRun(fixture: fixture, workspaceIdentity: workspaceIdentity)
        fixture.context.insert(run)
        try fixture.context.save()
        fixture.viewModel.beginAutomatedScheduledRunExecution(runID: run.id)
        defer { fixture.viewModel.finishAutomatedScheduledRunExecution() }
        await fixture.agentsManager.pauseNextSpawn()
        var crossedScheduledStartBoundary = false

        let turn = Task {
            try await fixture.viewModel.startAutomatedScheduledTurn(
                "Continue existing work.",
                onRuntimePrepared: { crossedScheduledStartBoundary = true }
            )
        }
        await fixture.agentsManager.waitUntilSpawnEntered()
        fixture.thread.effort = run.effortSnapshot == "high" ? "low" : "high"
        await fixture.agentsManager.resumePausedSpawn()

        do {
            try await turn.value
            XCTFail("Expected changed target settings to stop scheduled delivery")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("target changed"))
        }
        XCTAssertFalse(crossedScheduledStartBoundary)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testUnstartedExistingTargetUsesOneAutomatedInitialSpawn() async throws {
        let ownershipService = RecoveryWorkspaceOwnershipService()
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            taskWorkspaceOwnershipService: ownershipService
        )
        fixture.thread.isPinned = true
        let workspaceIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 50, fileNumber: 60)
        ownershipService.setIdentity(workspaceIdentity, at: fixture.project.path)
        let run = makeExistingTargetRun(fixture: fixture, workspaceIdentity: workspaceIdentity)
        fixture.context.insert(run)
        try fixture.context.save()
        fixture.viewModel.beginAutomatedScheduledRunExecution(runID: run.id)
        defer { fixture.viewModel.finishAutomatedScheduledRunExecution() }

        try await fixture.viewModel.startAutomatedScheduledTurn("Start pinned work.")

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let suspendCalls = await fixture.agentsManager.suspendCalls()
        let config = try XCTUnwrap(spawnCalls.first?.config)
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertTrue(suspendCalls.isEmpty)
        XCTAssertEqual(config.initialPrompt, "Start pinned work.")
        XCTAssertEqual(config.providerId, run.providerIDSnapshot)
        XCTAssertEqual(config.model, run.modelSnapshot)
        XCTAssertEqual(config.effort, run.effortSnapshot)
        XCTAssertEqual(config.permissionMode, run.permissionModeSnapshot)
        XCTAssertEqual(config.planModeEnabled, run.planModeEnabledSnapshot)
        XCTAssertEqual(config.speedMode?.rawValue, run.speedModeSnapshot)
        XCTAssertTrue(config.isAutomatedScheduledTurn)
        XCTAssertTrue(config.hostTools.isEmpty)
        XCTAssertTrue(fixture.thread.hasCompletedInitialSetup)
    }

    func testExistingScheduledTurnRecoversMissingProviderSessionWithLocalHistory() async throws {
        let ownershipService = RecoveryWorkspaceOwnershipService()
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            providerId: "codex",
            taskWorkspaceOwnershipService: ownershipService
        )
        fixture.thread.isPinned = true
        let workspaceIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 70, fileNumber: 80)
        ownershipService.setIdentity(workspaceIdentity, at: fixture.project.path)
        let run = makeExistingTargetRun(fixture: fixture, workspaceIdentity: workspaceIdentity)
        fixture.context.insert(run)
        try seedLocalRestoreHistory(
            fixture,
            userMessage: "Inspect the current implementation.",
            assistantMessage: "The implementation needs a follow-up."
        )
        await fixture.agentsManager.enqueueSpawnError(
            CodexAppServerError.jsonRPCError(
                method: "thread/resume",
                code: -32600,
                message: "no rollout found for scheduled target"
            )
        )
        fixture.viewModel.beginAutomatedScheduledRunExecution(runID: run.id)
        defer { fixture.viewModel.finishAutomatedScheduledRunExecution() }

        try await fixture.viewModel.startAutomatedScheduledTurn("Continue existing work.")

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let freshSessionCalls = await fixture.agentsManager.freshSessionCalls()
        let sentMessages = await fixture.agentsManager.sentMessages()
        let spawnConfig = try XCTUnwrap(spawnCalls.first?.config)
        let freshConfig = try XCTUnwrap(freshSessionCalls.first?.config)
        let sentMessage = try XCTUnwrap(sentMessages.first)
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertEqual(freshSessionCalls.count, 1)
        XCTAssertEqual(sentMessages.count, 1)
        XCTAssertTrue(spawnConfig.isAutomatedScheduledTurn)
        XCTAssertTrue(spawnConfig.hostTools.isEmpty)
        XCTAssertEqual(freshConfig, spawnConfig)
        XCTAssertTrue(freshConfig.hostTools.isEmpty)
        XCTAssertTrue(sentMessage.contains("Restoring context from local history."))
        XCTAssertTrue(sentMessage.contains("User: Inspect the current implementation."))
        XCTAssertTrue(sentMessage.contains("Assistant: The implementation needs a follow-up."))
        XCTAssertTrue(sentMessage.hasSuffix("\n\nContinue existing work."), sentMessage)
        XCTAssertNotNil(
            try fixture.userMessages().first { $0.content == "Continue existing work." }
        )
    }

    func testInterruptedRecoveryClearsLoadedScheduledInteractionState() throws {
        let fixture = try LoadedScheduledRecoveryFixture(
            status: .running,
            requiresFinalizationRecovery: false
        )
        defer { fixture.lease.release() }
        XCTAssertNotNil(fixture.fixture.viewModel.state.pendingToolApproval)
        XCTAssertTrue(fixture.fixture.viewModel.hasUnansweredPrompt)

        let result = try fixture.recover()

        XCTAssertEqual(result.interruptedRunIDs, [fixture.run.persistentModelID])
        XCTAssertEqual(fixture.run.status, .interrupted)
        fixture.assertLoadedInteractionIsSuperseded()
    }

    func testTerminalFinalizationRecoveryClearsLoadedScheduledInteractionState() throws {
        let fixture = try LoadedScheduledRecoveryFixture(
            status: .success,
            requiresFinalizationRecovery: true
        )
        defer { fixture.lease.release() }
        XCTAssertNotNil(fixture.fixture.viewModel.state.pendingToolApproval)
        XCTAssertTrue(fixture.fixture.viewModel.hasUnansweredPrompt)

        let result = try fixture.recover()

        XCTAssertTrue(result.interruptedRunIDs.isEmpty)
        XCTAssertEqual(fixture.run.status, .success)
        XCTAssertFalse(fixture.run.requiresFinalizationRecovery)
        fixture.assertLoadedInteractionIsSuperseded()
    }

}

private extension ConversationViewModelTests {
    func makeExistingTargetRun(
        fixture: ConversationViewModelTestFixture,
        workspaceIdentity: TaskWorkspaceFileSystemIdentity
    ) -> ScheduledTaskRun {
        ScheduledTaskRun(
            occurrenceID: "existing-conversation-occurrence",
            definitionID: "existing-conversation-definition",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
            triggerKind: .scheduled,
            status: .preparing,
            titleSnapshot: "Attached schedule",
            promptSnapshot: "Continue existing work.",
            destinationSnapshot: .existingThread,
            targetConversationIDSnapshot: fixture.conversation.id,
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: fixture.conversation.provider ?? "claude",
            modelSnapshot: fixture.thread.model,
            effortSnapshot: fixture.thread.effort,
            permissionModeSnapshot: "default",
            planModeEnabledSnapshot: fixture.thread.planModeEnabled ?? false,
            speedModeSnapshot: fixture.thread.normalizedSpeedMode.rawValue,
            workspaceKindSnapshot: .project,
            workspaceStrategySnapshot: .localCheckout,
            projectPathSnapshot: fixture.project.path,
            workspaceIdentitySnapshot: ScheduledTaskWorkspaceIdentitySnapshot(
                projectRoot: ScheduledTaskRootIdentitySnapshot(
                    path: fixture.project.path,
                    identity: workspaceIdentity
                ),
                grantedRoots: []
            ),
            targetThread: fixture.thread
        )
    }
}

@MainActor
private final class LoadedScheduledRecoveryFixture {
    let fixture: ConversationViewModelTestFixture
    let run: ScheduledTaskRun
    let promptRecord: ConversationEventRecord
    let approvalRecord: ConversationEventRecord
    let lease: ConversationControllerLease
    private let coordinator: ScheduledTaskRunRecoveryCoordinator
    private static let actionDate = Date(timeIntervalSinceReferenceDate: 7_000_000)

    init(
        status: ScheduledTaskRunStatus,
        requiresFinalizationRecovery: Bool
    ) throws {
        let fixture = try ConversationViewModelTestFixture(hasCompletedInitialSetup: true)
        fixture.thread.isPinned = true
        let run = Self.makeRun(
            fixture: fixture,
            status: status,
            requiresFinalizationRecovery: requiresFinalizationRecovery
        )
        let noteTimestamp = Self.actionDate.addingTimeInterval(-20)
        let note = ConversationEventRecord(
            id: "scheduled-task-\(run.id)",
            conversationId: fixture.conversation.id,
            type: ConversationEventRecord.scheduledTaskNoteType,
            content: "Scheduled task note",
            timestamp: noteTimestamp,
            conversation: fixture.conversation
        )
        let interaction = Self.makePendingInteraction(
            conversation: fixture.conversation,
            after: noteTimestamp
        )
        fixture.context.insert(run)
        fixture.context.insert(note)
        fixture.context.insert(interaction.promptRecord)
        fixture.context.insert(interaction.approvalRecord)
        try fixture.context.save()
        fixture.viewModel.rebuildChatItemsIfNeeded(
            from: fixture.viewModel.conversationEventRecords(),
            forceFullRebuild: true
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: interaction.approval,
            status: .pending
        )
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let lease = registry.makeViewLease(for: fixture.conversation)
        let coordinator = ScheduledTaskRunRecoveryCoordinator(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: RecordingNotificationManager(),
            workspaceOwnershipService: fixture.taskWorkspaceOwnershipService
        )
        self.fixture = fixture
        self.run = run
        self.promptRecord = interaction.promptRecord
        self.approvalRecord = interaction.approvalRecord
        self.lease = lease
        self.coordinator = coordinator
    }

    func recover() throws -> ScheduledTaskRunRecoveryResult {
        try coordinator.recoverPersistedRuns(at: Self.actionDate) { _ in false }
    }

    func assertLoadedInteractionIsSuperseded(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval, file: file, line: line)
        XCTAssertFalse(fixture.viewModel.hasUnansweredPrompt, file: file, line: line)
        XCTAssertEqual(
            approvalRecord.toolApprovalStatus,
            ToolApprovalStatus.superseded.rawValue,
            file: file,
            line: line
        )
        XCTAssertEqual(promptRecord.content, ChatItemGrouper.handledPromptSummary, file: file, line: line)
    }

    private static func makeRun(
        fixture: ConversationViewModelTestFixture,
        status: ScheduledTaskRunStatus,
        requiresFinalizationRecovery: Bool
    ) -> ScheduledTaskRun {
        ScheduledTaskRun(
            occurrenceID: "loaded-recovery-\(UUID().uuidString)",
            definitionID: "loaded-recovery-definition",
            definitionRevision: 1,
            occurrenceAt: Self.actionDate.addingTimeInterval(-30),
            triggerKind: .scheduled,
            status: status,
            titleSnapshot: "Loaded recovery",
            promptSnapshot: "Continue existing work.",
            destinationSnapshot: .existingThread,
            targetConversationIDSnapshot: fixture.conversation.id,
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "claude",
            modelSnapshot: fixture.thread.model,
            effortSnapshot: fixture.thread.effort,
            permissionModeSnapshot: fixture.thread.permissionMode,
            planModeEnabledSnapshot: fixture.thread.planModeEnabled,
            speedModeSnapshot: fixture.thread.speedMode,
            workspaceKindSnapshot: .project,
            workspaceStrategySnapshot: .localCheckout,
            projectPathSnapshot: fixture.project.path,
            startedAt: Self.actionDate.addingTimeInterval(-19),
            requiresFinalizationRecovery: requiresFinalizationRecovery,
            targetThread: fixture.thread
        )
    }

    private static func makePendingInteraction(
        conversation: Conversation,
        after noteTimestamp: Date
    ) -> LoadedScheduledPendingInteraction {
        let promptInput = #"{"questions":[{"question":"Continue?","header":"Continue","options":[],"multiSelect":false}]}"#
        let approval = ToolApprovalRequest(
            sessionId: "scheduled-recovery-session",
            toolUseId: "scheduled-recovery-prompt",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        let promptRecord = overlayAskUserQuestionToolCallRecord(
            conversation: conversation,
            promptId: approval.toolUseId,
            promptInput: promptInput,
            timestamp: noteTimestamp.addingTimeInterval(1).timeIntervalSince1970
        )
        let approvalRecord = overlayToolApprovalRecord(
            conversation: conversation,
            approval: approval,
            timestamp: noteTimestamp.addingTimeInterval(2).timeIntervalSince1970
        )
        return LoadedScheduledPendingInteraction(
            promptRecord: promptRecord,
            approvalRecord: approvalRecord,
            approval: approval
        )
    }
}

private struct LoadedScheduledPendingInteraction {
    let promptRecord: ConversationEventRecord
    let approvalRecord: ConversationEventRecord
    let approval: ToolApprovalRequest
}
