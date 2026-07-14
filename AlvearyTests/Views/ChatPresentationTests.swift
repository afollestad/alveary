import XCTest

@testable import Alveary

@MainActor
final class ChatPresentationTests: XCTestCase {
    func testContentModeResolvesTrustPlaceholderBeforeEmptyThread() {
        XCTAssertEqual(
            ChatContentMode.resolve(
                projectTrustPrompt: nil,
                isProjectTrustBlocked: true,
                hasVisibleChatContent: false
            ),
            .projectTrustPlaceholder
        )
    }

    func testContentModeResolvesTranscriptWhenContentExists() {
        XCTAssertEqual(
            ChatContentMode.resolve(
                projectTrustPrompt: nil,
                isProjectTrustBlocked: false,
                hasVisibleChatContent: true
            ),
            .transcript
        )
        XCTAssertEqual(
            ChatContentMode.resolve(
                projectTrustPrompt: nil,
                isProjectTrustBlocked: false,
                hasVisibleChatContent: false
            ),
            .emptyThread
        )
    }

    func testComposerModePriority() {
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: true,
                hasSetupPhase: true,
                isReconfiguringSession: true,
                isAwaitingHandoffSteering: true,
                isHandingOffSession: true,
                isAwaitingExitPlanModeFollowUp: false,
                pendingToolApprovalStatusText: .genericApproval,
                isTurnActive: true,
                runtimeStatus: .busy,
                isSendingMessage: true
            )),
            .progressOnly(.cancellingInitialSetup)
        )
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: false,
                hasSetupPhase: false,
                isReconfiguringSession: false,
                isAwaitingHandoffSteering: true,
                isHandingOffSession: true,
                isAwaitingExitPlanModeFollowUp: false,
                pendingToolApprovalStatusText: .genericApproval,
                isTurnActive: true,
                runtimeStatus: .busy,
                isSendingMessage: true
            )),
            .idle
        )
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: false,
                hasSetupPhase: false,
                isReconfiguringSession: false,
                isAwaitingHandoffSteering: false,
                isHandingOffSession: false,
                isAwaitingExitPlanModeFollowUp: false,
                pendingToolApprovalStatusText: nil,
                isTurnActive: false,
                runtimeStatus: .neutral,
                isSendingMessage: true
            )),
            .busy(canStop: false)
        )
    }

    func testComposerModeTreatsAwaitingExitPlanModeFollowUpAsNonStoppableBusy() {
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: false,
                hasSetupPhase: false,
                isReconfiguringSession: false,
                isAwaitingHandoffSteering: false,
                isHandingOffSession: false,
                isAwaitingExitPlanModeFollowUp: true,
                pendingToolApprovalStatusText: nil,
                isTurnActive: false,
                runtimeStatus: .neutral,
                isSendingMessage: false
            )),
            .busy(canStop: false)
        )
    }

    func testComposerModeTreatsRuntimeBusyAsBusy() {
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: false,
                hasSetupPhase: false,
                isReconfiguringSession: false,
                isAwaitingHandoffSteering: false,
                isHandingOffSession: false,
                isAwaitingExitPlanModeFollowUp: false,
                pendingToolApprovalStatusText: nil,
                isTurnActive: false,
                runtimeStatus: .busy,
                isSendingMessage: false
            )),
            .busy(canStop: true)
        )
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: false,
                hasSetupPhase: false,
                isReconfiguringSession: false,
                isAwaitingHandoffSteering: false,
                isHandingOffSession: false,
                isAwaitingExitPlanModeFollowUp: false,
                pendingToolApprovalStatusText: nil,
                isTurnActive: false,
                runtimeStatus: .idle,
                isSendingMessage: false
            )),
            .idle
        )
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: false,
                hasSetupPhase: false,
                isReconfiguringSession: false,
                isAwaitingHandoffSteering: false,
                isHandingOffSession: false,
                isAwaitingExitPlanModeFollowUp: false,
                pendingToolApprovalStatusText: nil,
                isTurnActive: false,
                runtimeStatus: .neutral,
                isSendingMessage: false
            )),
            .idle
        )
    }

    func testThreadPresentationShowsWorktreePickerBeforeSetup() {
        let project = Project(path: "/tmp/alveary", name: "Alveary", gitRemote: "git@github.com:test/alveary.git")
        let thread = AgentThread(
            name: "Native composer",
            hasCompletedInitialSetup: false,
            permissionMode: "acceptEdits",
            effort: "high",
            model: "opus",
            useWorktree: true,
            project: project
        )

        let presentation = ChatThreadPresentation(thread: thread, providerID: "claude")

        XCTAssertEqual(presentation.selectedModel, "opus")
        XCTAssertEqual(presentation.selectedEffort, "high")
        XCTAssertEqual(presentation.selectedPermissionMode, "acceptEdits")
        XCTAssertFalse(presentation.selectedPlanModeEnabled)
        XCTAssertTrue(presentation.selectedUseWorktree)
        XCTAssertTrue(presentation.showWorktreePicker)
        XCTAssertEqual(presentation.contextWindowCacheLookupID, "claude:opus")
    }

    func testThreadPresentationKeepsPlanOutOfPickerDisplay() {
        let thread = AgentThread(
            name: "Plan mode",
            permissionMode: "default"
        )

        let presentation = ChatThreadPresentation(
            thread: thread,
            providerID: "claude",
            runtimePermissionMode: "plan"
        )

        XCTAssertEqual(presentation.selectedPermissionMode, "default")
        XCTAssertFalse(presentation.selectedPlanModeEnabled)
    }

    func testThreadPresentationUsesRuntimePlanModeForPlusMenuToggle() {
        let thread = AgentThread(
            name: "Plan mode",
            permissionMode: "acceptEdits",
            planModeEnabled: true
        )

        let presentation = ChatThreadPresentation(
            thread: thread,
            providerID: "claude",
            runtimePermissionMode: "acceptEdits",
            runtimePlanModeEnabled: false
        )

        XCTAssertEqual(presentation.selectedPermissionMode, "acceptEdits")
        XCTAssertFalse(presentation.selectedPlanModeEnabled)
    }

    func testThreadPresentationUsesPendingPermissionModeBeforeRuntimeModeForPickerDisplay() {
        let thread = AgentThread(
            name: "Pending permission",
            permissionMode: "default"
        )

        let presentation = ChatThreadPresentation(
            thread: thread,
            providerID: "claude",
            runtimePermissionMode: "plan",
            pendingPermissionMode: "acceptEdits"
        )

        XCTAssertEqual(presentation.selectedPermissionMode, "acceptEdits")
    }

    func testThreadPresentationUsesPendingPlanModeBeforeRuntimeModeForDisplay() {
        let thread = AgentThread(
            name: "Pending plan mode",
            permissionMode: "acceptEdits",
            planModeEnabled: false
        )

        let presentation = ChatThreadPresentation(
            thread: thread,
            providerID: "claude",
            runtimePlanModeEnabled: true,
            pendingPlanModeEnabled: false
        )

        XCTAssertFalse(presentation.selectedPlanModeEnabled)
    }

    func testThreadPresentationHidesWorktreePickerAfterSetup() {
        let project = Project(path: "/tmp/alveary", name: "Alveary", gitRemote: "git@github.com:test/alveary.git")
        let thread = AgentThread(
            name: "Native composer",
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            model: nil,
            useWorktree: true,
            project: project
        )

        let presentation = ChatThreadPresentation(thread: thread, providerID: "claude")

        XCTAssertEqual(presentation.selectedModel, AppSettings.defaultModelValue)
        XCTAssertTrue(presentation.selectedUseWorktree)
        XCTAssertFalse(presentation.showWorktreePicker)
        XCTAssertEqual(presentation.contextWindowCacheLookupID, "claude:\(AppSettings.defaultModelValue)")
    }

    func testTaskThreadPresentationNeverShowsProjectWorktreePicker() {
        let sourceProject = Project(path: "/tmp/alveary", name: "Alveary", gitRemote: "git@github.com:test/alveary.git")
        let thread = AgentThread(
            name: "Scheduled task",
            hasCompletedInitialSetup: false,
            useWorktree: true,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/alveary-task-worktree",
                ownershipStrategy: .projectWorktreeOwned,
                ownershipMarkerID: UUID().uuidString.lowercased(),
                sourceProjectPath: sourceProject.path
            )
        )

        let presentation = ChatThreadPresentation(thread: thread, providerID: "claude")

        XCTAssertFalse(presentation.showWorktreePicker)
    }

    func testLinkedScheduledRunUsesTaskPresentationWhenPersistedModeFallsBackToProject() {
        let sourceProject = Project(path: "/tmp/alveary", name: "Alveary", gitRemote: "git@github.com:test/alveary.git")
        let run = makeChatPresentationScheduledRun()
        let thread = AgentThread(
            name: "Fallback scheduled task",
            hasCompletedInitialSetup: false,
            useWorktree: true,
            project: sourceProject,
            scheduledTaskRun: run
        )
        thread.modeRawValue = "future-mode"
        run.thread = thread

        let presentation = ChatThreadPresentation(thread: thread, providerID: "claude")

        XCTAssertEqual(presentation.mode, .task)
        XCTAssertFalse(presentation.showWorktreePicker)
    }
}

private func makeChatPresentationScheduledRun() -> ScheduledTaskRun {
    ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "chat-presentation-definition",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
        triggerKind: .scheduled,
        status: .success,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "UTC",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .project,
        workspaceStrategySnapshot: .worktree
    )
}
