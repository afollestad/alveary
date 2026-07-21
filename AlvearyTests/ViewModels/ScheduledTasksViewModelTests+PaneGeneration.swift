import XCTest

@testable import Alveary

@MainActor
extension ScheduledTasksViewModelTests {
    func testPaneFocusRestorationIDUsesInvokingControlAndSurvivesDismissal() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertDefinition(id: "focus-edit")

        fixture.viewModel.requestCreate(focusRestorationID: "scheduled-new-empty")
        XCTAssertEqual(fixture.viewModel.paneFocusRestorationID, "scheduled-new-empty")
        fixture.viewModel.dismissActivePane()
        XCTAssertEqual(fixture.viewModel.paneFocusRestorationID, "scheduled-new-empty")

        fixture.viewModel.requestEdit(definitionID: "focus-edit")
        XCTAssertEqual(fixture.viewModel.paneFocusRestorationID, "scheduled-edit-focus-edit")
        fixture.viewModel.dismissActivePane()
        XCTAssertEqual(fixture.viewModel.paneFocusRestorationID, "scheduled-edit-focus-edit")

        fixture.viewModel.requestCreate()
        XCTAssertEqual(fixture.viewModel.paneFocusRestorationID, "scheduled-new")
        fixture.viewModel.dismissActivePane()
        XCTAssertEqual(fixture.viewModel.paneFocusRestorationID, "scheduled-new")
    }

    func testMissingEditRequestPreservesActiveTargetAndFocusRestorationID() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.requestCreate(focusRestorationID: "scheduled-new-empty")

        fixture.viewModel.requestEdit(definitionID: "missing")

        XCTAssertEqual(fixture.viewModel.activePaneTarget, .create)
        XCTAssertNotNil(fixture.viewModel.paneSessions[.create])
        XCTAssertNil(fixture.viewModel.paneSessions[.edit("missing")])
        XCTAssertEqual(fixture.viewModel.paneFocusRestorationID, "scheduled-new-empty")
    }

    func testProposalLoadPreservesManualSessionWhileScreenLoadNormalizesWithoutClearingError() async throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.requestCreate()
        var draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        draft.prompt = "Keep this manual draft and its validation error."
        draft.providerID = "codex"
        draft.permissionMode = "acceptEdits"
        fixture.viewModel.updateActiveDraft(draft)
        fixture.viewModel.submitActivePane()

        let sessionBeforeLoad = try XCTUnwrap(fixture.viewModel.paneSessions[.create])
        XCTAssertEqual(
            sessionBeforeLoad.errorMessage,
            ScheduledTasksViewModelError.titleRequired.localizedDescription
        )

        await fixture.viewModel.load()

        XCTAssertEqual(fixture.viewModel.paneSessions[.create], sessionBeforeLoad)

        var normalizedDraft = sessionBeforeLoad.draft
        fixture.viewModel.normalizeProviderDependentFields(&normalizedDraft)
        XCTAssertNotEqual(normalizedDraft, sessionBeforeLoad.draft)

        await fixture.viewModel.loadForScreen()

        let sessionAfterScreenLoad = try XCTUnwrap(fixture.viewModel.paneSessions[.create])
        XCTAssertEqual(sessionAfterScreenLoad.generation, sessionBeforeLoad.generation)
        XCTAssertEqual(sessionAfterScreenLoad.draft, normalizedDraft)
        XCTAssertEqual(sessionAfterScreenLoad.errorMessage, sessionBeforeLoad.errorMessage)
        XCTAssertEqual(sessionAfterScreenLoad.isSubmitting, sessionBeforeLoad.isSubmitting)
    }

    func testDismissingCapturedTargetDoesNotCloseNewActiveTarget() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertDefinition(id: "active-edit")
        fixture.viewModel.requestCreate()
        let capturedGeneration = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)
        fixture.viewModel.requestEdit(definitionID: "active-edit")

        fixture.viewModel.dismissPane(.create, generation: capturedGeneration)

        XCTAssertNil(fixture.viewModel.paneSessions[.create])
        XCTAssertEqual(fixture.viewModel.activePaneTarget, .edit("active-edit"))
        XCTAssertNotNil(fixture.viewModel.paneSessions[.edit("active-edit")])
        XCTAssertEqual(fixture.viewModel.paneDismissalGeneration, 0)
    }

    func testCompletingDeactivatedDismissalDoesNotRestoreFocusOverNewActiveTarget() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertDefinition(id: "new-active-edit")
        fixture.viewModel.requestCreate()
        let generation = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)
        fixture.viewModel.deactivatePane(.create, generation: generation)
        fixture.viewModel.requestEdit(definitionID: "new-active-edit")

        fixture.viewModel.dismissPane(.create, generation: generation)

        XCTAssertEqual(fixture.viewModel.activePaneTarget, .edit("new-active-edit"))
        XCTAssertNotNil(fixture.viewModel.paneSessions[.edit("new-active-edit")])
        XCTAssertEqual(fixture.viewModel.paneDismissalGeneration, 0)
    }

    func testStaleDismissalCannotCloseReopenedSameTarget() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.requestCreate()
        let staleGeneration = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)
        fixture.viewModel.dismissActivePane()
        fixture.viewModel.requestCreate()
        let reopenedGeneration = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)

        fixture.viewModel.dismissPane(.create, generation: staleGeneration)

        XCTAssertNotEqual(reopenedGeneration, staleGeneration)
        XCTAssertEqual(fixture.viewModel.paneSessions[.create]?.generation, reopenedGeneration)
        XCTAssertEqual(fixture.viewModel.activePaneTarget, .create)
        XCTAssertEqual(fixture.viewModel.paneDismissalGeneration, 1)
    }

    func testRequestingDeactivatedSameTargetCreatesFreshDefaultGenerationBeforeCompletion() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.requestCreate()
        var staleDraft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        staleDraft.title = "Stale draft"
        staleDraft.prompt = "Stale instructions"
        fixture.viewModel.updateActiveDraft(staleDraft)
        let staleGeneration = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)

        fixture.viewModel.deactivatePane(.create, generation: staleGeneration)
        fixture.viewModel.requestCreate()
        let reopenedGeneration = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)

        XCTAssertNotEqual(reopenedGeneration, staleGeneration)
        XCTAssertEqual(fixture.viewModel.pendingEditorDraft?.title, "")
        XCTAssertEqual(fixture.viewModel.pendingEditorDraft?.prompt, "")
        XCTAssertNil(fixture.viewModel.pendingEditorDraft?.definitionID)
        XCTAssertEqual(fixture.viewModel.activePaneTarget, .create)
        XCTAssertEqual(fixture.viewModel.paneDismissalGeneration, 0)

        fixture.viewModel.dismissPane(.create, generation: staleGeneration)

        XCTAssertEqual(fixture.viewModel.paneSessions[.create]?.generation, reopenedGeneration)
        XCTAssertEqual(fixture.viewModel.activePaneTarget, .create)
        XCTAssertEqual(fixture.viewModel.paneDismissalGeneration, 0)
    }

    func testDismissalWithoutFocusRestorationDoesNotBumpGenerationWhenNoTargetIsActive() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.requestCreate()
        let generation = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)

        fixture.viewModel.deactivatePane(.create, generation: generation)
        fixture.viewModel.dismissPane(.create, generation: generation, restoreFocus: false)

        XCTAssertNil(fixture.viewModel.activePaneTarget)
        XCTAssertNil(fixture.viewModel.paneSessions[.create])
        XCTAssertEqual(fixture.viewModel.paneDismissalGeneration, 0)
    }

    func testDismissalWithoutFocusRestorationClearsMatchingActiveTarget() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.requestCreate()
        let generation = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)

        fixture.viewModel.dismissPane(.create, generation: generation, restoreFocus: false)

        XCTAssertNil(fixture.viewModel.activePaneTarget)
        XCTAssertNil(fixture.viewModel.paneSessions[.create])
        XCTAssertEqual(fixture.viewModel.paneDismissalGeneration, 0)
    }

    func testRequestingPendingSuccessfulSubmitStartsFreshDraftWithoutFocusBump() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.requestCreate(focusRestorationID: "scheduled-new-empty")
        var draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        draft.title = "Created task"
        draft.prompt = "Do useful work."
        fixture.viewModel.updateActiveDraft(draft)
        let completedGeneration = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)

        fixture.viewModel.submitActivePane()
        let request = PaneSessionDismissalRequest(target: ScheduledTaskPaneTarget.create, generation: completedGeneration)
        XCTAssertTrue(fixture.viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(fixture.viewModel.paneFocusRestorationID, "scheduled-new")

        fixture.viewModel.requestCreate()

        XCTAssertNotEqual(fixture.viewModel.paneSessions[.create]?.generation, completedGeneration)
        XCTAssertEqual(fixture.viewModel.pendingEditorDraft?.title, "")
        XCTAssertEqual(fixture.viewModel.pendingEditorDraft?.prompt, "")
        XCTAssertEqual(fixture.viewModel.activePaneTarget, .create)
        XCTAssertFalse(fixture.viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(fixture.viewModel.paneDismissalGeneration, 0)
    }

    func testSuccessfulSubmitRetainsSessionUntilAnimatedDismissalCompletes() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.requestCreate()
        var draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        draft.title = "New task"
        draft.prompt = "Do useful work."
        fixture.viewModel.updateActiveDraft(draft)
        let generation = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)

        fixture.viewModel.submitActivePane()

        let request = PaneSessionDismissalRequest(target: ScheduledTaskPaneTarget.create, generation: generation)
        XCTAssertTrue(fixture.viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(fixture.viewModel.activePaneTarget, .create)
        XCTAssertEqual(fixture.viewModel.paneSessions[.create]?.generation, generation)
        XCTAssertEqual(fixture.viewModel.paneSessions[.create]?.isSubmitting, true)

        fixture.viewModel.deactivatePane(.create, generation: generation)
        fixture.viewModel.dismissPane(.create, generation: generation)
        XCTAssertNil(fixture.viewModel.paneSessions[.create])
        XCTAssertFalse(fixture.viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(fixture.viewModel.paneDismissalGeneration, 1)
    }
}
