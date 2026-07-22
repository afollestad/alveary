import XCTest

@testable import Alveary

@MainActor
extension ConversationControllerRegistryTests {
    func testScheduledReadinessIncludesActiveSiblingConversationInTargetThread() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let secondary = Conversation(
            id: "scheduled-target-sibling",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: fixture.thread
        )
        fixture.thread.conversations.append(secondary)
        fixture.context.insert(secondary)
        try fixture.context.save()
        let secondaryManager = MockAgentsManager(
            isRunning: true,
            sendError: nil,
            reconfigureError: nil,
            approvalError: nil
        )
        let secondaryViewModel = ConversationViewModel(
            conversation: secondary,
            agentsManager: secondaryManager,
            runtimeStore: fixture.runtimeStore,
            keepAwakeService: fixture.keepAwakeService,
            modelContext: fixture.context,
            settingsService: fixture.settingsService,
            worktreeManager: fixture.worktreeManager,
            taskWorkspaceOwnershipService: fixture.taskWorkspaceOwnershipService,
            providerSetup: fixture.providerSetup,
            contextWindowCache: fixture.contextWindowCache,
            attachmentStore: fixture.attachmentStore,
            threadActivityRecorder: NoopThreadActivityRecorder()
        )
        let registry = DefaultConversationControllerRegistry { conversation in
            conversation.id == secondary.id ? secondaryViewModel : fixture.viewModel
        }
        let mainLease = registry.makeViewLease(for: fixture.conversation)
        let siblingLease = registry.makeViewLease(for: secondary)
        mainLease.activate()
        siblingLease.activate()
        secondaryViewModel.markVisibleTurnStarted()
        secondaryViewModel.turnState.beginTurn()
        await Task.yield()

        XCTAssertFalse(registry.isReadyForScheduledTask(conversationID: fixture.conversation.id))

        secondaryViewModel.state.endTurn()
        mainLease.release()
        siblingLease.release()
    }

    func testRecoveryReadinessIgnoresOwnDurableFenceButNotRuntimeActivity() throws {
        let fixture = try ConversationViewModelTestFixture(hasCompletedInitialSetup: true)
        let run = ScheduledTaskRun(
            occurrenceID: "recovery-controller-run",
            definitionID: "recovery-controller-definition",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
            triggerKind: .scheduled,
            status: .claimed,
            titleSnapshot: "Attached schedule",
            promptSnapshot: "Continue",
            destinationSnapshot: .existingThread,
            targetConversationIDSnapshot: fixture.conversation.id,
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "claude",
            effortSnapshot: fixture.thread.effort,
            permissionModeSnapshot: fixture.thread.permissionMode,
            workspaceKindSnapshot: .project,
            workspaceStrategySnapshot: .localCheckout,
            projectPathSnapshot: fixture.project.path,
            targetThread: fixture.thread
        )
        fixture.context.insert(run)
        try fixture.context.save()
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let lease = registry.makeViewLease(for: fixture.conversation)
        lease.activate()

        XCTAssertFalse(registry.isReadyForScheduledTask(conversationID: fixture.conversation.id))
        XCTAssertTrue(registry.isReadyForScheduledTaskRecovery(conversationID: fixture.conversation.id))

        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        XCTAssertFalse(registry.isReadyForScheduledTaskRecovery(conversationID: fixture.conversation.id))
        fixture.viewModel.state.endTurn()
        lease.release()
    }
}
