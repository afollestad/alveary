import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTasksViewModelTests {
    func testStoredSchedulePresentationAndEditDraftUseCurrentMacTimeZone() throws {
        let fixture = try ScheduledTasksViewModelFixture(
            currentTimeZone: TimeZone(identifier: "Pacific/Auckland") ?? .current
        )
        try fixture.insertDefinition(id: "local-zone", state: .active)
        fixture.viewModel.reload()

        XCTAssertEqual(fixture.viewModel.tasks.first?.timeZoneIdentifier, "Pacific/Auckland")
        XCTAssertEqual(
            fixture.viewModel.makeEditDraft(definitionID: "local-zone")?.timeZoneIdentifier,
            "Pacific/Auckland"
        )
    }

    func testExistingThreadSaveUsesPinnedMainConversationAndCurrentMacTimeZone() throws {
        let fixture = try ScheduledTasksViewModelFixture(
            currentTimeZone: TimeZone(identifier: "Pacific/Auckland") ?? .current
        )
        let project = Project(path: "/tmp/pinned-target", name: "Pinned Project")
        let target = AgentThread(name: "Pinned target", isPinned: true, project: project)
        let conversation = Conversation(id: "pinned-target-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        project.threads = [target]
        fixture.context.insert(project)
        try fixture.context.save()
        fixture.viewModel.reload()
        XCTAssertEqual(fixture.viewModel.pinnedThreads.map(\.conversationID), [conversation.id])

        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "Continue existing work"
        draft.prompt = "Review the latest state."
        draft.destination = .existingThread
        draft.targetConversationID = conversation.id
        draft.timeZoneIdentifier = "UTC"

        XCTAssertTrue(fixture.viewModel.save(draft))

        let definition = try XCTUnwrap(fixture.fetchDefinitions().first)
        XCTAssertEqual(definition.destination, .existingThread)
        XCTAssertEqual(definition.targetThread?.persistentModelID, target.persistentModelID)
        XCTAssertEqual(definition.timeZoneIdentifier, "Pacific/Auckland")
        XCTAssertNil(definition.project)
    }

    func testExistingThreadEditClearsProjectWorkspaceKindForNewThreadRoundTrip() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let project = Project(path: "/tmp/scheduled-project", name: "Scheduled Project")
        let target = AgentThread(name: "Pinned target", isPinned: true, mode: .task)
        let conversation = Conversation(id: "pinned-target-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        fixture.context.insert(project)
        fixture.context.insert(target)
        try fixture.context.save()
        fixture.viewModel.reload()

        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "Round-trip destination"
        draft.prompt = "Review the latest state."
        draft.workspaceKind = .project
        draft.projectPath = project.path
        XCTAssertTrue(fixture.viewModel.save(draft))

        let definition = try XCTUnwrap(fixture.fetchDefinitions().first)
        var existingThreadDraft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        existingThreadDraft.destination = .existingThread
        existingThreadDraft.targetConversationID = conversation.id
        XCTAssertTrue(fixture.viewModel.save(existingThreadDraft))
        XCTAssertEqual(definition.destination, .existingThread)
        XCTAssertEqual(definition.workspaceKind, .privateWorkspace)
        XCTAssertNil(definition.project)

        var newThreadDraft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        XCTAssertEqual(newThreadDraft.workspaceKind, .privateWorkspace)
        XCTAssertNil(newThreadDraft.projectPath)
        newThreadDraft.destination = .newThread
        XCTAssertTrue(fixture.viewModel.save(newThreadDraft))
        XCTAssertEqual(definition.destination, .newThread)
        XCTAssertEqual(definition.workspaceKind, .privateWorkspace)
        XCTAssertNil(definition.project)
    }

    func testPinnedThreadOptionsUseSharedSidebarLegacyOrder() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let older = AgentThread(
            name: "Alpha",
            isPinned: true,
            modifiedAt: Date(timeIntervalSince1970: 100),
            mode: .task
        )
        let olderMain = Conversation(id: "older-main", provider: "claude", thread: older)
        older.conversations = [olderMain]
        let newer = AgentThread(
            name: "Zulu",
            isPinned: true,
            modifiedAt: Date(timeIntervalSince1970: 200),
            mode: .task
        )
        let newerMain = Conversation(id: "newer-main", provider: "codex", thread: newer)
        newer.conversations = [newerMain]
        fixture.context.insert(older)
        fixture.context.insert(newer)
        try fixture.context.save()

        fixture.viewModel.reload()

        XCTAssertEqual(fixture.viewModel.pinnedThreads.map(\.conversationID), [newerMain.id, olderMain.id])
    }

    func testPinnedThreadOptionsStablyDisambiguateMatchingContextLabels() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let first = AgentThread(name: "Duplicate", isPinned: true, mode: .task)
        let firstMain = Conversation(id: "task-one-main", provider: "codex", thread: first)
        first.conversations = [firstMain]
        let second = AgentThread(name: "Duplicate", isPinned: true, mode: .task)
        let secondMain = Conversation(id: "task-two-main", provider: "codex", thread: second)
        second.conversations = [secondMain]
        fixture.context.insert(first)
        fixture.context.insert(second)
        try fixture.context.save()

        fixture.viewModel.reload()

        let labels = Dictionary(uniqueKeysWithValues: fixture.viewModel.pinnedThreads.map {
            ($0.conversationID, $0.label)
        })
        XCTAssertEqual(labels[firstMain.id], "Duplicate — Tasks · task-one")
        XCTAssertEqual(labels[secondMain.id], "Duplicate — Tasks · task-two")
    }

    func testPinnedThreadOptionsExcludeTargetWithPendingScheduledWorktreeCleanup() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let run = ScheduledTaskRun(
            occurrenceID: "pending-cleanup-target-run",
            definitionID: "pending-cleanup-target-definition",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
            triggerKind: .scheduled,
            status: .failure,
            titleSnapshot: "Pending cleanup target",
            promptSnapshot: "Run scheduled work.",
            timeZoneIdentifierSnapshot: "America/Chicago",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree
        )
        run.setPendingWorktreeCleanup(try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: "/tmp/source",
            worktreePath: "/tmp/worktree",
            branch: "alveary/pending-cleanup",
            sourceProjectIdentity: TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 2),
            worktreeIdentity: TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 3),
            ownershipMarkerID: nil,
            ownershipSourceProjectPath: nil
        )))
        let target = AgentThread(
            name: "Pending cleanup target",
            isPinned: true,
            mode: .task,
            scheduledTaskRun: run
        )
        let conversation = Conversation(id: "pending-cleanup-target-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        run.thread = target
        fixture.context.insert(run)
        fixture.context.insert(target)
        try fixture.context.save()

        fixture.viewModel.reload()

        XCTAssertFalse(fixture.viewModel.pinnedThreads.contains { $0.conversationID == conversation.id })
    }

    func testPinnedThreadOptionsExcludeForkTargetUntilBootstrapCompletes() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let target = AgentThread(
            name: "Pending fork",
            hasCompletedInitialSetup: false,
            isPinned: true,
            isForkBootstrapPending: true,
            mode: .task
        )
        let conversation = Conversation(id: "pending-fork-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        fixture.context.insert(target)
        try fixture.context.save()

        fixture.viewModel.reload()
        XCTAssertFalse(fixture.viewModel.pinnedThreads.contains { $0.conversationID == conversation.id })

        target.isForkBootstrapPending = false
        target.hasCompletedInitialSetup = true
        try fixture.context.save()
        fixture.viewModel.reload()

        XCTAssertTrue(fixture.viewModel.pinnedThreads.contains { $0.conversationID == conversation.id })
    }

    func testThreadPresentationChangeRefreshesPinnedThreadLabel() async throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let target = AgentThread(name: "Before rename", isPinned: true, mode: .task)
        let conversation = Conversation(id: "rename-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        fixture.context.insert(target)
        try fixture.context.save()
        fixture.viewModel.reload()
        XCTAssertEqual(fixture.viewModel.pinnedThreads.first?.label, "Before rename")

        target.name = "After rename"
        try fixture.context.save()
        fixture.notificationCenter.post(name: .threadPresentationChanged, object: target)
        for _ in 0 ..< 20 where fixture.viewModel.pinnedThreads.first?.label != "After rename" {
            await Task.yield()
        }

        XCTAssertEqual(fixture.viewModel.pinnedThreads.first?.label, "After rename")
    }

    func testExistingThreadRowUsesTargetMainConversationProvider() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let project = Project(path: "/tmp/provider-target", name: "Provider target")
        let target = AgentThread(name: "Target", isPinned: true, project: project)
        let conversation = Conversation(id: "provider-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        project.threads = [target]
        let definition = ScheduledTask(
            id: "provider-definition",
            title: "Continue target",
            prompt: "Continue the work.",
            destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "UTC",
            providerID: "claude",
            targetThread: target
        )
        fixture.context.insert(project)
        fixture.context.insert(definition)
        try fixture.context.save()

        fixture.viewModel.reload()

        XCTAssertEqual(fixture.viewModel.tasks.first?.providerID, "codex")
    }

    func testRunNowClaimResolutionSurfacesSchedulerRejection() async throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertDefinition(id: "busy-target", state: .active)
        fixture.viewModel.reload()
        let row = try XCTUnwrap(fixture.viewModel.tasks.first)

        fixture.viewModel.runNow(row)
        fixture.notificationCenter.postScheduledTasksChanged(
            definitionID: row.id,
            schedulerClaimResolved: true,
            schedulerClaimErrorMessage: "The attached task is busy. Try again when it is idle."
        )
        for _ in 0 ..< 20 where fixture.viewModel.pendingRunNowDefinitionIDs.contains(row.id) {
            await Task.yield()
        }

        XCTAssertFalse(fixture.viewModel.pendingRunNowDefinitionIDs.contains(row.id))
        XCTAssertEqual(
            fixture.viewModel.errorMessage,
            "The attached task is busy. Try again when it is idle."
        )
    }

    func testUnknownDestinationPresentsInvalidRowAndRefusesEditDraft() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertDefinition(id: "unknown-destination", state: .active)
        let definition = try XCTUnwrap(fixture.context.resolveScheduledTask(id: "unknown-destination"))
        definition.destinationRawValue = "future-destination"
        try fixture.context.save()

        fixture.viewModel.reload()

        let row = try XCTUnwrap(fixture.viewModel.tasks.first)
        XCTAssertNil(row.destination)
        XCTAssertEqual(row.workspaceSummary, "Invalid destination")
        XCTAssertNil(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        XCTAssertEqual(
            fixture.viewModel.errorMessage,
            ScheduledTasksViewModelError.invalidPersistedDestination.localizedDescription
        )
    }
}
