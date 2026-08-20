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
        XCTAssertEqual(fixture.viewModel.existingThreadTargets.map(\.conversationID), [conversation.id])

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
        newThreadDraft.destination = .newThreadPerRun
        XCTAssertTrue(fixture.viewModel.save(newThreadDraft))
        XCTAssertEqual(definition.destination, .newThreadPerRun)
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

        XCTAssertEqual(fixture.viewModel.existingThreadTargets.map(\.conversationID), [newerMain.id, olderMain.id])
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

        let labels = Dictionary(uniqueKeysWithValues: fixture.viewModel.existingThreadTargets.map {
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
            destinationSnapshot: .newThreadPerRun,
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

        XCTAssertFalse(fixture.viewModel.existingThreadTargets.contains { $0.conversationID == conversation.id })
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
        XCTAssertFalse(fixture.viewModel.existingThreadTargets.contains { $0.conversationID == conversation.id })

        target.isForkBootstrapPending = false
        target.hasCompletedInitialSetup = true
        try fixture.context.save()
        fixture.viewModel.reload()

        XCTAssertTrue(fixture.viewModel.existingThreadTargets.contains { $0.conversationID == conversation.id })
    }

    func testThreadPresentationChangeRefreshesPinnedThreadLabel() async throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let target = AgentThread(name: "Before rename", isPinned: true, mode: .task)
        let conversation = Conversation(id: "rename-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        fixture.context.insert(target)
        try fixture.context.save()
        fixture.viewModel.reload()
        XCTAssertEqual(fixture.viewModel.existingThreadTargets.first?.label, "Before rename")

        target.name = "After rename"
        try fixture.context.save()
        fixture.notificationCenter.post(name: .threadPresentationChanged, object: target)
        for _ in 0 ..< 20 where fixture.viewModel.existingThreadTargets.first?.label != "After rename" {
            await Task.yield()
        }

        XCTAssertEqual(fixture.viewModel.existingThreadTargets.first?.label, "After rename")
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

    func testExistingThreadOptionsOfferUnpinnedThreadsWithNoPinNote() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let target = AgentThread(name: "Release chat", mode: .task)
        let conversation = Conversation(id: "unpinned-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        fixture.context.insert(target)
        try fixture.context.save()

        fixture.viewModel.reload()

        let option = try XCTUnwrap(
            fixture.viewModel.existingThreadTargets.first { $0.conversationID == conversation.id }
        )
        XCTAssertEqual(option.label, "Release chat")
    }

    /// A pinned project absorbs its children, but the child still renders inside it, so nothing
    /// about the pin makes it unreachable as a target.
    func testExistingThreadOptionsOfferAnUnpinnedThreadInsideAPinnedProject() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let project = Project(path: "/tmp/absorbing-project", name: "Absorbing Project")
        project.isPinned = true
        let target = AgentThread(name: "Absorbed child", mode: .task, project: project)
        let conversation = Conversation(id: "absorbed-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        project.threads = [target]
        fixture.context.insert(project)
        try fixture.context.save()

        fixture.viewModel.reload()

        XCTAssertTrue(fixture.viewModel.existingThreadTargets.contains { $0.conversationID == conversation.id })
    }

    func testSavingAnExistingThreadScheduleLeavesAnUnpinnedTargetUnpinned() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let pinnedNeighbor = AgentThread(name: "Already pinned", isPinned: true, mode: .task)
        pinnedNeighbor.pinnedSortOrder = 0
        let target = AgentThread(name: "Release chat", mode: .task)
        let conversation = Conversation(id: "unpinned-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        fixture.context.insert(pinnedNeighbor)
        fixture.context.insert(target)
        try fixture.context.save()
        fixture.viewModel.reload()

        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "Continue existing work"
        draft.prompt = "Review the latest state."
        draft.destination = .existingThread
        draft.targetConversationID = conversation.id

        XCTAssertTrue(fixture.viewModel.save(draft))

        let definition = try XCTUnwrap(fixture.fetchDefinitions().first)
        XCTAssertEqual(definition.targetThread?.persistentModelID, target.persistentModelID)
        XCTAssertFalse(target.isPinned)
        XCTAssertNil(target.pinnedSortOrder)
        XCTAssertEqual(pinnedNeighbor.pinnedSortOrder, 0)
    }

    /// The seam between the host tool and the confirmation pane: a proposal that names an
    /// unpinned thread has to survive `makeProposalDraft`, whose picker options would otherwise
    /// drop an unlisted target.
    func testConfirmingAnExistingThreadProposalTargetsTheThreadWithoutPinningIt() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let target = AgentThread(name: "Release chat", mode: .task)
        let conversation = Conversation(id: "unpinned-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        fixture.context.insert(target)
        try fixture.context.save()
        fixture.viewModel.reload()

        let definitionDraft = ScheduledTaskProposalDefinitionDraft(
            title: "Continue existing work",
            prompt: "Review the latest state.",
            destination: .existingThread,
            targetConversationID: conversation.id,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            model: nil,
            effort: "medium",
            permissionMode: "default",
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            grantedRoots: [],
            projectPath: nil
        )
        let draft = fixture.viewModel.makeProposalDraft(
            definitionDraft,
            definitionID: nil,
            expectedRevision: nil
        )
        XCTAssertEqual(draft.targetConversationID, conversation.id)

        XCTAssertTrue(fixture.viewModel.save(draft))

        let definition = try XCTUnwrap(fixture.fetchDefinitions().first)
        XCTAssertEqual(definition.destination, .existingThread)
        XCTAssertEqual(definition.targetThread?.persistentModelID, target.persistentModelID)
        XCTAssertFalse(target.isPinned)
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

    func testUnrecognizedDestinationOpensTheEditorWithNoDestinationSelected() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let definition = try fixture.insertUnrecognizedDestinationDefinition()

        let row = try XCTUnwrap(fixture.viewModel.tasks.first)
        XCTAssertNil(row.destination)
        XCTAssertEqual(row.workspaceSummary, "Unrecognized destination")

        XCTAssertTrue(fixture.viewModel.requestEdit(definitionID: definition.id))
        XCTAssertEqual(fixture.viewModel.activePaneTarget, .edit(definition.id))

        let draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        XCTAssertEqual(draft.unresolvedDestinationRawValue, "future-destination")
        XCTAssertTrue(draft.hasUnresolvedDestination)
        XCTAssertNil(draft.destinationSelection)
        // The screen banner belonged to the refusal this replaced; the pane carries the notice now.
        XCTAssertNil(fixture.viewModel.errorMessage)
    }

    func testUnrecognizedDestinationRefusesTheSaveAndLeavesTheStoredRawValueAlone() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let definition = try fixture.insertUnrecognizedDestinationDefinition()
        XCTAssertTrue(fixture.viewModel.requestEdit(definitionID: definition.id))
        var draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        draft.title = "Renamed while unresolved"

        fixture.viewModel.updateActiveDraft(draft)
        fixture.viewModel.submitActivePane()

        XCTAssertEqual(
            fixture.viewModel.editorErrorMessage,
            ScheduledTasksViewModelError.destinationNotRecognized.localizedDescription
        )
        XCTAssertEqual(fixture.viewModel.activePaneTarget, .edit(definition.id))
        XCTAssertEqual(definition.destinationRawValue, "future-destination")
        XCTAssertEqual(definition.title, "Scheduled task")
        XCTAssertEqual(definition.revision, 1)
    }

    func testPickingADestinationRepairsTheRowAndAllowsTheSave() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let definition = try fixture.insertUnrecognizedDestinationDefinition()
        XCTAssertTrue(fixture.viewModel.requestEdit(definitionID: definition.id))
        var draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)

        // The seeded fallback is `.reusedThread`, so picking it must still count as a choice.
        draft.destinationSelection = .reusedThread
        XCTAssertFalse(draft.hasUnresolvedDestination)
        XCTAssertEqual(draft.destinationSelection, .reusedThread)

        fixture.viewModel.updateActiveDraft(draft)
        fixture.viewModel.submitActivePane()

        XCTAssertNil(fixture.viewModel.editorErrorMessage)
        XCTAssertEqual(definition.destinationRawValue, ScheduledTaskDestination.reusedThread.rawValue)
        XCTAssertEqual(definition.decodedDestination, .reusedThread)
        XCTAssertEqual(definition.revision, 2)
        XCTAssertEqual(fixture.viewModel.tasks.first?.workspaceSummary.hasPrefix("Same thread each time"), true)
    }
}

@MainActor
private extension ScheduledTasksViewModelFixture {
    /// A stored definition whose destination this build cannot decode — the shape a schedule
    /// written by a newer Alveary takes when an older one reads it.
    @discardableResult
    func insertUnrecognizedDestinationDefinition() throws -> ScheduledTask {
        try insertDefinition(id: "unknown-destination", state: .active)
        let definition = try XCTUnwrap(context.resolveScheduledTask(id: "unknown-destination"))
        definition.destinationRawValue = "future-destination"
        try context.save()
        viewModel.reload()
        return definition
    }
}
