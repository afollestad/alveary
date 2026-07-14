import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTasksViewModelTests: XCTestCase {
    func testFiltersKeepCompletedOneShotInAllAndBlockedDefinitionInPaused() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertDefinition(id: "active", state: .active)
        try fixture.insertDefinition(
            id: "blocked",
            state: .paused,
            pauseReason: "Provider is unavailable."
        )
        try fixture.insertDefinition(
            id: "completed",
            state: .completed,
            recurrence: .once(fixture.now.addingTimeInterval(-60))
        )

        fixture.viewModel.reload()

        XCTAssertEqual(Set(fixture.viewModel.tasks(for: .all).map(\.id)), ["active", "blocked", "completed"])
        XCTAssertEqual(fixture.viewModel.tasks(for: .active).map(\.id), ["active"])
        XCTAssertEqual(fixture.viewModel.tasks(for: .paused).map(\.id), ["blocked"])
        XCTAssertEqual(fixture.viewModel.tasks(for: .paused).first?.blockedReason, "Provider is unavailable.")
    }

    func testSaveCreatesStructuredProjectScheduleAndNormalizesGrants() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let project = Project(path: "/tmp/scheduled-project", name: "Scheduled Project")
        fixture.context.insert(project)
        try fixture.context.save()
        fixture.viewModel.reload()

        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "  Weekly audit  "
        draft.prompt = "  Review the repository.  "
        draft.recurrenceKind = .weekly
        draft.weeklyWeekday = 2
        draft.wallClockHour = 9
        draft.wallClockMinute = 30
        draft.timeZoneIdentifier = "America/Chicago"
        draft.workspaceKind = .project
        draft.workspaceStrategy = .localCheckout
        draft.projectPath = project.path
        draft.grantedRoots = ["/tmp/grant", "/tmp/grant"]

        XCTAssertTrue(fixture.viewModel.save(draft))

        let definition = try XCTUnwrap(fixture.fetchDefinitions().first)
        XCTAssertEqual(definition.title, "Weekly audit")
        XCTAssertEqual(definition.prompt, "Review the repository.")
        XCTAssertEqual(definition.recurrence, .weekly(weekday: 2, hour: 9, minute: 30))
        XCTAssertEqual(definition.timeZoneIdentifier, "America/Chicago")
        XCTAssertEqual(definition.workspaceKind, .project)
        XCTAssertEqual(definition.workspaceStrategy, .localCheckout)
        XCTAssertEqual(definition.project?.path, project.path)
        XCTAssertEqual(definition.grantedRoots, ["/tmp/grant"])
        XCTAssertEqual(definition.state, .active)
        XCTAssertNotNil(definition.nextOccurrenceAt)
    }

    func testSaveRejectsMissingTitleWithoutCreatingDefinition() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.requestCreate()
        var draft = fixture.viewModel.makeNewDraft()
        draft.prompt = "Do useful work."

        XCTAssertFalse(fixture.viewModel.save(draft))
        XCTAssertEqual(fixture.viewModel.editorErrorMessage, ScheduledTasksViewModelError.titleRequired.localizedDescription)
        XCTAssertNil(fixture.viewModel.errorMessage)
        XCTAssertTrue(try fixture.fetchDefinitions().isEmpty)

        fixture.viewModel.dismissEditor()

        XCTAssertNil(fixture.viewModel.editorErrorMessage)
    }

    func testWeekdayDraftDefaultsToWorkweekAndSavesExactSelection() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        var draft = fixture.viewModel.makeNewDraft()

        XCTAssertEqual(draft.selectedWeekdays, Set(ScheduledTaskRecurrence.standardWeekdays))

        draft.title = "Selected days"
        draft.prompt = "Run on selected days."
        draft.recurrenceKind = .weekdays
        draft.selectedWeekdays = [3, 5, 7]
        draft.wallClockHour = 11
        draft.wallClockMinute = 45
        draft.timeZoneIdentifier = "UTC"

        XCTAssertTrue(fixture.viewModel.save(draft))
        XCTAssertEqual(
            try XCTUnwrap(fixture.fetchDefinitions().first).recurrence,
            .weekdays(days: [3, 5, 7], hour: 11, minute: 45)
        )
    }

    func testSaveRejectsWeekdayDraftWithoutSelectedDays() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "Missing days"
        draft.prompt = "Run when selected."
        draft.recurrenceKind = .weekdays
        draft.selectedWeekdays = []

        XCTAssertFalse(fixture.viewModel.save(draft))
        XCTAssertEqual(
            fixture.viewModel.editorErrorMessage,
            ScheduledTaskRecurrenceError.emptyWeekdaySelection.localizedDescription
        )
        XCTAssertTrue(try fixture.fetchDefinitions().isEmpty)
    }

    func testRequestEditPublishesEditorDraftForExactDefinition() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertDefinition(id: "requested", title: "Requested task", revision: 4)

        fixture.viewModel.requestEdit(definitionID: "requested")

        XCTAssertEqual(fixture.viewModel.pendingEditorDraft?.definitionID, "requested")
        XCTAssertEqual(fixture.viewModel.pendingEditorDraft?.expectedRevision, 4)
        XCTAssertEqual(fixture.viewModel.pendingEditorDraft?.title, "Requested task")
        fixture.viewModel.dismissEditor()
        XCTAssertNil(fixture.viewModel.pendingEditorDraft)
    }

    func testProviderSwitchNormalizesIncompatiblePermissionMode() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        var draft = fixture.viewModel.makeNewDraft()
        draft.permissionMode = "acceptEdits"

        XCTAssertTrue(
            fixture.viewModel.permissionModeOptions(
                for: draft.providerID,
                including: draft.permissionMode
            ).contains(where: { $0.value == "acceptEdits" })
        )

        draft.providerID = "codex"
        fixture.viewModel.normalizeProviderDependentFields(&draft)

        XCTAssertEqual(draft.permissionMode, "on-request")
        XCTAssertTrue(
            fixture.viewModel.permissionModeOptions(for: "codex")
                .contains(where: { $0.value == draft.permissionMode })
        )
    }

    func testRunNowUsesRevisionCheckedRequestWithoutChangingDefinitionCadence() throws {
        var capturedRequest: ScheduledTaskRunNowRequest?
        let fixture = try ScheduledTasksViewModelFixture(runNow: { request in
            capturedRequest = request
            return true
        })
        try fixture.insertDefinition(
            id: "paused",
            state: .paused,
            recurrence: .daily(hour: 8, minute: 0),
            nextOccurrenceAt: fixture.now.addingTimeInterval(60 * 60)
        )
        fixture.viewModel.reload()
        let row = try XCTUnwrap(fixture.viewModel.tasks.first)

        fixture.viewModel.runNow(row)

        XCTAssertEqual(capturedRequest?.definitionID, "paused")
        XCTAssertEqual(capturedRequest?.definitionRevision, row.revision)
        XCTAssertEqual(capturedRequest?.occurrenceSource, .manual)
        XCTAssertTrue(fixture.viewModel.pendingRunNowDefinitionIDs.contains("paused"))
        let definition = try XCTUnwrap(fixture.context.resolveScheduledTask(id: "paused"))
        XCTAssertEqual(definition.state, .paused)
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.now.addingTimeInterval(60 * 60))
    }

    func testRunNowStaysPendingUntilSchedulerClaimResolutionNotification() async throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertDefinition(id: "slow-preflight", state: .active)
        fixture.viewModel.reload()
        let row = try XCTUnwrap(fixture.viewModel.tasks.first)

        fixture.viewModel.runNow(row)
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertTrue(fixture.viewModel.pendingRunNowDefinitionIDs.contains(row.id))
        fixture.notificationCenter.postScheduledTasksChanged(
            definitionID: row.id,
            schedulerClaimResolved: true
        )
        for _ in 0 ..< 20 where fixture.viewModel.pendingRunNowDefinitionIDs.contains(row.id) {
            await Task.yield()
        }
        XCTAssertFalse(fixture.viewModel.pendingRunNowDefinitionIDs.contains(row.id))
    }

    func testSchedulerStateNotificationReloadsAutomaticRunState() async throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertDefinition(id: "automatic", state: .active)
        fixture.viewModel.reload()
        let definition = try XCTUnwrap(fixture.context.resolveScheduledTask(id: "automatic"))
        definition.state = .paused
        definition.pauseReason = "Provider unavailable."
        try fixture.context.save()

        fixture.notificationCenter.postScheduledTasksChanged(
            object: self,
            definitionID: definition.id,
            schedulerClaimResolved: true
        )
        for _ in 0 ..< 20 where fixture.viewModel.tasks.first?.state != .paused {
            await Task.yield()
        }

        XCTAssertEqual(fixture.viewModel.tasks.first?.state, .paused)
        XCTAssertEqual(fixture.viewModel.tasks.first?.blockedReason, "Provider unavailable.")
    }

    func testExternalMutationNotificationReloadsRows() async throws {
        let fixture = try ScheduledTasksViewModelFixture()
        XCTAssertTrue(fixture.viewModel.tasks.isEmpty)

        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "External task"
        draft.prompt = "Run outside the view model."
        _ = try fixture.mutationService.create(edit: try fixture.definitionEdit(from: draft), at: fixture.now)
        for _ in 0 ..< 10 where fixture.viewModel.tasks.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(fixture.viewModel.tasks.map(\.title), ["External task"])
    }

    func testRecurrenceSummaryUsesPinnedTimeZoneAndFrozenLocale() {
        let locale = Locale(identifier: "en_US_POSIX")
        let date = Date(timeIntervalSince1970: 1_752_408_840)

        XCTAssertEqual(
            ScheduledTaskPresentationFormatting.recurrenceSummary(
                .once(date),
                timeZoneIdentifier: "UTC",
                locale: locale
            ),
            "Once on Jul 13, 2025 at 12:14 PM"
        )
        XCTAssertEqual(
            ScheduledTaskPresentationFormatting.recurrenceSummary(
                .weekly(weekday: 2, hour: 9, minute: 5),
                timeZoneIdentifier: "America/Chicago",
                locale: locale
            ),
            "Weekly on Monday at 9:05 AM"
        )
        XCTAssertEqual(
            ScheduledTaskPresentationFormatting.recurrenceSummary(
                .weekdays(days: [2, 4, 6], hour: 9, minute: 5),
                timeZoneIdentifier: "America/Chicago",
                locale: locale
            ),
            "Every Monday, Wednesday, and Friday at 9:05 AM"
        )
    }
}

@MainActor
private final class ScheduledTasksViewModelFixture {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let container: ModelContainer
    let context: ModelContext
    let notificationCenter = NotificationCenter()
    let settingsService = InMemorySettingsService()
    let mutationService: ScheduledTaskMutationService
    let viewModel: ScheduledTasksViewModel

    init(runNow: @escaping @MainActor (ScheduledTaskRunNowRequest) -> Bool = { _ in true }) throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        mutationService = ScheduledTaskMutationService(
            modelContext: context,
            notificationCenter: notificationCenter
        )
        viewModel = ScheduledTasksViewModel(
            modelContext: context,
            mutationService: mutationService,
            settingsService: settingsService,
            notificationCenter: notificationCenter,
            runNow: runNow,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    func insertDefinition(
        id: String,
        title: String = "Scheduled task",
        revision: Int = 1,
        state: ScheduledTaskState,
        recurrence: ScheduledTaskRecurrence = .daily(hour: 8, minute: 0),
        nextOccurrenceAt: Date? = nil,
        pauseReason: String? = nil
    ) throws {
        let definition = ScheduledTask(
            id: id,
            title: title,
            prompt: "Do the work.",
            revision: revision,
            state: state,
            recurrence: recurrence,
            timeZoneIdentifier: "UTC",
            providerID: "claude",
            nextOccurrenceAt: nextOccurrenceAt,
            pauseReason: pauseReason,
            modifiedAt: Date(timeIntervalSince1970: Double(revision))
        )
        context.insert(definition)
        try context.save()
    }

    func insertDefinition(
        id: String,
        title: String = "Scheduled task",
        revision: Int = 1
    ) throws {
        try insertDefinition(id: id, title: title, revision: revision, state: .active)
    }

    func fetchDefinitions() throws -> [ScheduledTask] {
        try context.fetch(FetchDescriptor<ScheduledTask>())
    }

    func definitionEdit(from draft: ScheduledTaskEditorDraft) throws -> ScheduledTaskDefinitionEdit {
        ScheduledTaskDefinitionEdit(
            title: draft.title,
            prompt: draft.prompt,
            recurrence: draft.recurrence,
            timeZoneIdentifier: draft.timeZoneIdentifier,
            providerID: draft.providerID,
            model: nil,
            effort: draft.effort,
            permissionMode: draft.permissionMode,
            workspaceKind: draft.workspaceKind,
            workspaceStrategy: draft.workspaceStrategy,
            grantedRoots: draft.grantedRoots,
            project: nil
        )
    }
}
