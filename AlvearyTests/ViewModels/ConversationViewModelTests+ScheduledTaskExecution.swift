import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testScheduledTaskNoteStaysAtChronologicalBoundaryBeforeScheduledPrompt() throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let earlierDate = Date(timeIntervalSince1970: 100)
        let noteDate = Date(timeIntervalSince1970: 200)
        let promptDate = Date(timeIntervalSince1970: 300)
        let assistant = ConversationEventRecord(
            id: "assistant-before-note",
            type: "message",
            role: "assistant",
            content: "Provider output",
            timestamp: earlierDate,
            conversation: fixture.conversation
        )
        let user = ConversationEventRecord(
            id: "aaa-user-at-note-time",
            type: "message",
            role: "user",
            content: "Scheduled prompt",
            timestamp: promptDate,
            conversation: fixture.conversation
        )
        let note = ConversationEventRecord(
            id: "zzz-scheduled-note",
            type: ConversationEventRecord.scheduledTaskNoteType,
            content: "Scheduled task \"Scheduled audit\" for Jan 15, 2027 at 9:30 AM",
            timestamp: noteDate,
            conversation: fixture.conversation
        )
        fixture.context.insert(assistant)
        fixture.context.insert(user)
        fixture.context.insert(note)
        try fixture.context.save()

        let records = fixture.viewModel.conversationEventRecords()
        XCTAssertEqual(records.map(\.id), [assistant.id, note.id, user.id])

        fixture.viewModel.rebuildChatItemsIfNeeded(from: records, forceFullRebuild: true)
        XCTAssertEqual(
            fixture.viewModel.state.grouper.items,
            [
                .assistantMessage(id: assistant.id, text: "Provider output"),
                .transcriptNote(id: note.id, kind: .scheduledTask(try XCTUnwrap(note.content))),
                .userMessage(id: user.id, text: "Scheduled prompt")
            ]
        )
    }

    func testAutomatedScheduledTurnUsesRestrictedLaunchAndPreservesPrompt() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture

        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let spawn = try XCTUnwrap(spawnCalls.first)
        XCTAssertTrue(spawn.config.isAutomatedScheduledTurn)
        XCTAssertTrue(spawn.config.hostTools.isEmpty)
        XCTAssertEqual(spawn.config.initialPrompt, "Run the scheduled audit.")
        XCTAssertTrue(try fixture.dbThread().hasCompletedInitialSetup)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Run the scheduled audit."])
    }

    func testAutomatedScheduledLaunchFailureKeepsPromptForInspection() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        await fixture.agentsManager.enqueueSpawnError(MockAgentsManager.MockError.sendFailed)

        do {
            try await fixture.viewModel.startAutomatedScheduledTurn("Preserve this failed scheduled prompt.")
            XCTFail("Expected scheduled launch to fail")
        } catch {
            XCTAssertEqual(error as? MockAgentsManager.MockError, .sendFailed)
        }

        let userMessage = try XCTUnwrap(fixture.userMessages().first)
        XCTAssertEqual(userMessage.content, "Preserve this failed scheduled prompt.")
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.contains(userMessage.id))
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
    }

    func testDeferredApprovalContinuationPreservesAutomatedRestrictions() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")
        await fixture.agentsManager.kill(conversationId: fixture.conversation.id)
        let approval = ToolApprovalRequest(
            sessionId: "scheduled-session",
            toolUseId: "scheduled-tool",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: approval.toolUseId)

        let approvalCalls = await fixture.agentsManager.approvalCalls()
        let approvalCall = try XCTUnwrap(approvalCalls.first)
        XCTAssertTrue(approvalCall.config.isAutomatedScheduledTurn)
        XCTAssertTrue(approvalCall.config.hostTools.isEmpty)
        XCTAssertFalse(try fixture.viewModel.makeSpawnConfig(settingsSource: .nextTurn).isAutomatedScheduledTurn)
    }

    func testManualOutboundCannotPreemptScheduledInitialTurn() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        fixture.viewModel.activateViewLifecycle()

        do {
            try await fixture.viewModel.send("Start manually first.")
            XCTFail("Expected direct manual outbound to wait for the scheduled turn")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }

        try await fixture.viewModel.queueOrSend("Continue after the scheduled turn.")
        try await Task.sleep(nanoseconds: 50_000_000)
        let preScheduledSpawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertTrue(preScheduledSpawnCalls.isEmpty)
        XCTAssertEqual(
            fixture.viewModel.state.messageQueue.peekNext()?.text,
            "Continue after the scheduled turn."
        )

        fixture.viewModel.beginAutomatedScheduledRunExecution()
        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")
        let automatedSpawnCalls = await fixture.agentsManager.spawnCalls()
        let spawn = try XCTUnwrap(automatedSpawnCalls.first)
        XCTAssertTrue(spawn.config.isAutomatedScheduledTurn)
        XCTAssertEqual(spawn.config.initialPrompt, "Run the scheduled audit.")
        try scheduledFixture.markRunTerminal()
        fixture.viewModel.finishAutomatedScheduledRunExecution()
    }

    func testDirectSteeringCannotEnterAutomatedScheduledTurn() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        fixture.viewModel.beginAutomatedScheduledRunExecution()
        defer { fixture.viewModel.finishAutomatedScheduledRunExecution() }
        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")

        XCTAssertFalse(fixture.viewModel.canSteerCurrentTurn)
        do {
            try await fixture.viewModel.steer("Change the active scheduled turn.")
            XCTFail("Expected direct steering to wait for scheduled finalization")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }

        let steeringCalls = await fixture.agentsManager.steeringCalls()
        XCTAssertTrue(steeringCalls.isEmpty)
    }

    func testQueuedSteeringCannotEnterAutomatedScheduledTurn() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.beginAutomatedScheduledRunExecution()
        defer { fixture.viewModel.finishAutomatedScheduledRunExecution() }
        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")
        try await fixture.viewModel.queueOrSend("Continue after the scheduled turn.")
        let queuedMessage = try XCTUnwrap(fixture.viewModel.state.messageQueue.peekNext())

        do {
            try await fixture.viewModel.steerQueuedMessage(id: queuedMessage.id)
            XCTFail("Expected queued steering to wait for scheduled finalization")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }

        XCTAssertEqual(fixture.viewModel.state.messageQueue.peekNext()?.id, queuedMessage.id)
        let steeringCalls = await fixture.agentsManager.steeringCalls()
        XCTAssertTrue(steeringCalls.isEmpty)
    }

    func testDirectAgentStartCannotPreemptScheduledInitialTurn() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let config = try fixture.viewModel.makeSpawnConfig()

        do {
            try await fixture.viewModel.startAgent(config: config)
            XCTFail("Expected direct agent start to wait for the scheduled turn")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertTrue(spawnCalls.isEmpty)
    }

    func testGoalStartCannotPreemptScheduledInitialTurn() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture

        do {
            try await fixture.viewModel.startGoal("Run a manual goal first.")
            XCTFail("Expected Goal mode to wait for the scheduled turn")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertTrue(spawnCalls.isEmpty)
    }

    func testQueuedManualFollowUpWaitsForFinalizationAndRelaunchesWithoutRestrictions() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.beginAutomatedScheduledRunExecution()
        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")

        try await fixture.viewModel.queueOrSend("Continue manually.")
        fixture.viewModel.handleTurnCompleted()
        try await Task.sleep(nanoseconds: 50_000_000)
        let preFinalizationSpawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(preFinalizationSpawnCalls.count, 1)
        XCTAssertEqual(fixture.viewModel.state.messageQueue.peekNext()?.text, "Continue manually.")

        try scheduledFixture.markRunTerminal()
        fixture.viewModel.finishAutomatedScheduledRunExecution()
        try await waitUntil("expected queued manual follow-up to use an ordinary runtime") {
            let spawnCalls = await fixture.agentsManager.spawnCalls()
            let sentMessages = await fixture.agentsManager.sentMessages()
            return spawnCalls.count == 2 && sentMessages == ["Continue manually."]
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let suspendCalls = await fixture.agentsManager.suspendCalls()
        let destroyCalls = await fixture.agentsManager.destroyCalls()
        XCTAssertTrue(spawnCalls[0].config.isAutomatedScheduledTurn)
        XCTAssertFalse(spawnCalls[1].config.isAutomatedScheduledTurn)
        XCTAssertTrue(spawnCalls[0].config.hostTools.isEmpty)
        XCTAssertEqual(
            spawnCalls[1].config.hostTools.map(\.name),
            [ScheduledTaskHostToolCatalog.listToolName, ScheduledTaskHostToolCatalog.proposeToolName]
        )
        XCTAssertFalse(spawnCalls[1].forkSession)
        XCTAssertEqual(suspendCalls, [fixture.conversation.id])
        XCTAssertTrue(destroyCalls.isEmpty)
        XCTAssertNil(fixture.viewModel.state.messageQueue.peekNext())
    }

    func testAutomatedScheduledTurnRejectsGrantSymlinkSwapBeforeSpawn() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        try scheduledFixture.swapGrantToReplacement()

        do {
            try await fixture.viewModel.startAutomatedScheduledTurn("Do not run with swapped access.")
            XCTFail("Expected scheduled workspace validation to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                ScheduledTurnWorkspaceValidationError.workspaceRootsChanged.localizedDescription
            )
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
    }

    func testAutomatedScheduledTurnRejectsProjectSamePathReplacementBeforeSpawn() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        try scheduledFixture.replaceWorkspaceAtSamePath()

        do {
            try await fixture.viewModel.startAutomatedScheduledTurn("Do not run in a replacement Project.")
            XCTFail("Expected scheduled workspace validation to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                ScheduledTurnWorkspaceValidationError.workspaceRootsChanged.localizedDescription
            )
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
    }

    func testAutomatedScheduledTurnRevalidatesAfterProviderSetupBeforeSpawn() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let grantPath = scheduledFixture.grant.path
        await fixture.providerSetup.setPrepareForSpawnHook {
            try? FileManager.default.removeItem(atPath: grantPath)
            try? FileManager.default.createDirectory(
                atPath: grantPath,
                withIntermediateDirectories: true
            )
        }

        do {
            try await fixture.viewModel.startAutomatedScheduledTurn("Catch the post-setup swap.")
            XCTFail("Expected scheduled workspace validation to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                ScheduledTurnWorkspaceValidationError.workspaceRootsChanged.localizedDescription
            )
        }

        let setupCalls = await fixture.providerSetup.calls()
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(setupCalls.count, 1)
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
    }

    func testTerminalReconciliationDrainsQueuedMessageForUnstartedScheduledTask() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let lease = registry.makeViewLease(for: fixture.conversation)
        lease.activate()
        defer { lease.release() }

        try await fixture.viewModel.queueOrSend("Continue after materialization failed.")
        XCTAssertEqual(
            fixture.viewModel.state.messageQueue.peekNext()?.text,
            "Continue after materialization failed."
        )
        XCTAssertNil(fixture.viewModel.queueDrainTask)
        let run = try XCTUnwrap(fixture.dbThread().scheduledTaskRun)
        run.status = .failure
        run.finishedAt = .now
        try fixture.context.save()

        registry.reconcileScheduledTaskTerminalState(conversationID: fixture.conversation.id)

        try await waitUntil("expected terminal scheduled shell to drain its queued message") {
            await fixture.agentsManager.spawnCalls().count == 1
        }
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let spawn = try XCTUnwrap(spawnCalls.first)
        XCTAssertFalse(spawn.config.isAutomatedScheduledTurn)
        XCTAssertEqual(
            spawn.config.hostTools.map(\.name),
            [ScheduledTaskHostToolCatalog.listToolName, ScheduledTaskHostToolCatalog.proposeToolName]
        )
        XCTAssertNil(fixture.viewModel.state.messageQueue.peekNext())
    }

}

@MainActor
struct ScheduledConversationViewModelFixture {
    let root: URL
    let workspace: URL
    let grant: URL
    let fixture: ConversationViewModelTestFixture

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledConversationViewModelFixture-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("Workspace", isDirectory: true)
        let grant = root.appendingPathComponent("Grant", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: grant, withIntermediateDirectories: true)
        let ownershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("WorktreeRecords", isDirectory: true)
        )
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            providerId: "claude",
            threadMode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: workspace.path,
                grantedRoots: [grant.path],
                ownershipStrategy: .projectLocal,
                sourceProjectPath: workspace.path
            ),
            taskWorkspaceOwnershipService: ownershipService
        )
        let run = try Self.makeRun(
            fixture: fixture,
            workspace: workspace,
            grant: grant,
            ownershipService: ownershipService
        )
        fixture.context.insert(run)
        try fixture.context.save()
        self.root = root
        self.workspace = workspace
        self.grant = grant
        self.fixture = fixture
    }

    private static func makeRun(
        fixture: ConversationViewModelTestFixture,
        workspace: URL,
        grant: URL,
        ownershipService: DefaultTaskWorkspaceOwnershipService
    ) throws -> ScheduledTaskRun {
        let workspaceIdentities = try ScheduledTaskWorkspaceIdentitySnapshot(
            workspaceKind: .project,
            projectPath: workspace.path,
            grantedRootPaths: [grant.path],
            identityAtPath: ownershipService.directoryIdentity(at:)
        )
        let run = ScheduledTaskRun(
            occurrenceID: "scheduled-view-model-occurrence",
            definitionID: "scheduled-view-model-definition",
            definitionRevision: 1,
            occurrenceAt: .now,
            triggerKind: .scheduled,
            status: .preparing,
            titleSnapshot: "Scheduled task",
            promptSnapshot: "Run it.",
            timeZoneIdentifierSnapshot: "America/Chicago",
            providerIDSnapshot: "claude",
            effortSnapshot: "high",
            permissionModeSnapshot: "acceptEdits",
            workspaceKindSnapshot: .project,
            workspaceStrategySnapshot: .localCheckout,
            projectPathSnapshot: workspace.path,
            grantedRootsSnapshot: [grant.path],
            workspaceIdentitySnapshot: workspaceIdentities,
            thread: fixture.thread
        )
        run.preparedWorkspaceRoot = workspace.path
        run.preparedWorkspaceOwnershipStrategy = .projectLocal
        return run
    }

    func swapGrantToReplacement() throws {
        let replacement = root.appendingPathComponent("ReplacementGrant", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: grant)
        try FileManager.default.createSymbolicLink(atPath: grant.path, withDestinationPath: replacement.path)
    }

    func replaceWorkspaceAtSamePath() throws {
        try FileManager.default.removeItem(at: workspace)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    func markRunTerminal(status: ScheduledTaskRunStatus = .success) throws {
        guard let run = fixture.thread.scheduledTaskRun else {
            throw FixtureError.missingThread
        }
        run.status = status
        run.finishedAt = .now
        try fixture.context.save()
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}
