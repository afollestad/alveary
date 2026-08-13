import XCTest

@testable import Alveary

@MainActor
extension ScheduledTasksViewModelTests {
    func testSuggestionRosterSwapsThePullRequestSlotWhenTheIntegrationIsDisabled() throws {
        let enabled = try ScheduledTasksViewModelFixture()
        XCTAssertEqual(
            enabled.viewModel.firstTaskSuggestions.map(\.id),
            ["pull-request-review", "project-digest", "agents-refresh"]
        )

        let disabled = try ScheduledTasksViewModelFixture(
            configureSettings: { $0.pullRequestsEnabled = false }
        )
        XCTAssertEqual(
            disabled.viewModel.firstTaskSuggestions.map(\.id),
            ["dependency-check", "project-digest", "agents-refresh"]
        )
    }

    func testSuggestionsSeedTheCreateDraftWithTheirPromptAndSchedule() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let suggestions = fixture.viewModel.firstTaskSuggestions
        let pullRequestReview = try XCTUnwrap(suggestions.first { $0.id == "pull-request-review" })

        fixture.viewModel.requestCreate(from: pullRequestReview)

        XCTAssertEqual(fixture.viewModel.activePaneTarget, .create)
        let draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        XCTAssertEqual(draft.title, "Review pull requests")
        XCTAssertEqual(draft.prompt, pullRequestReview.prompt)
        XCTAssertNil(draft.definitionID)
        // Six hours, since the editor and the model both speak minutes.
        XCTAssertEqual(draft.recurrence, .interval(minutes: 360, anchor: fixture.now))
    }

    func testWallClockSuggestionsBuildTheirWeekdayAndWeeklyRecurrences() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let suggestions = fixture.viewModel.firstTaskSuggestions
        let digest = try XCTUnwrap(suggestions.first { $0.id == "project-digest" })
        let agentsRefresh = try XCTUnwrap(suggestions.first { $0.id == "agents-refresh" })

        fixture.viewModel.requestCreate(from: digest)
        XCTAssertEqual(
            fixture.viewModel.pendingEditorDraft?.recurrence,
            .weekdays(hour: 9, minute: 0)
        )

        fixture.viewModel.requestCreate(from: agentsRefresh)
        // Calendar weekdays run 1 = Sunday, so Monday is 2.
        XCTAssertEqual(
            fixture.viewModel.pendingEditorDraft?.recurrence,
            .weekly(weekday: 2, hour: 9, minute: 0)
        )
    }

    /// Picking a suggestion is an explicit choice of starting point, so it has to beat the
    /// cached session the plain create action deliberately reuses.
    func testPickingASecondSuggestionReplacesTheFirstOnesCachedDraft() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let suggestions = fixture.viewModel.firstTaskSuggestions
        let first = try XCTUnwrap(suggestions.first)
        let second = try XCTUnwrap(suggestions.dropFirst().first)

        fixture.viewModel.requestCreate(from: first)
        let firstGeneration = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)
        fixture.viewModel.deactivatePane()

        fixture.viewModel.requestCreate(from: second)

        let draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        XCTAssertEqual(draft.title, second.title)
        XCTAssertEqual(draft.prompt, second.prompt)
        XCTAssertNotEqual(fixture.viewModel.paneSessions[.create]?.generation, firstGeneration)
        XCTAssertEqual(fixture.viewModel.activePaneTarget, .create)
    }

    /// The header's blank create action keeps preserving whatever is in flight, including a
    /// suggestion draft the user has since edited.
    func testPlainCreateStillReopensAnEditedSuggestionDraft() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let suggestion = try XCTUnwrap(fixture.viewModel.firstTaskSuggestions.first)
        fixture.viewModel.requestCreate(from: suggestion)
        var draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        draft.prompt = "Edited after picking the suggestion."
        fixture.viewModel.updateActiveDraft(draft)
        let generation = try XCTUnwrap(fixture.viewModel.paneSessions[.create]?.generation)
        fixture.viewModel.deactivatePane()

        fixture.viewModel.requestCreate()

        XCTAssertEqual(fixture.viewModel.paneSessions[.create]?.generation, generation)
        XCTAssertEqual(fixture.viewModel.pendingEditorDraft?.prompt, "Edited after picking the suggestion.")
        XCTAssertEqual(fixture.viewModel.pendingEditorDraft?.title, suggestion.title)
    }

    /// Workspace and agent are left for the user to settle in the pane, so a suggestion must
    /// not smuggle a Project choice past that review.
    func testSuggestionsLeaveWorkspaceOnTheBlankDraftDefaults() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let project = Project(path: "/tmp/suggestion-project", name: "Suggestion Project")
        fixture.context.insert(project)
        try fixture.context.save()
        fixture.viewModel.reload()
        let suggestion = try XCTUnwrap(fixture.viewModel.firstTaskSuggestions.last)

        fixture.viewModel.requestCreate(from: suggestion)

        let draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        XCTAssertEqual(draft.destination, .newThread)
        XCTAssertEqual(draft.workspaceKind, .privateWorkspace)
        XCTAssertNil(draft.projectPath)
        XCTAssertTrue(draft.grantedRoots.isEmpty)
    }
}
