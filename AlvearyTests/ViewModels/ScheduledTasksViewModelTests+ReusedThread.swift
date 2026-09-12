import SwiftData
import XCTest

@testable import Alveary

/// Covers what the Scheduled card and editor say about a `.reusedThread` schedule once its first
/// run has minted a thread — and what they fall back to when that thread stops being usable, since
/// the schedule then mints a replacement rather than blocking.
@MainActor
extension ScheduledTasksViewModelTests {
    func testEditingScheduleRejectsRetargetedSavedGrantWithoutChangingItsReuseThread() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let grant = root.appendingPathComponent("Grant", isDirectory: true)
        let replacement = root.appendingPathComponent("Replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: grant, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try ScheduledTasksViewModelFixture()
        let thread = try fixture.insertReusedThreadDefinition(id: "changed-grant")
        let definition = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTask>()).first)
        let workspace = WorkspaceSnapshot(primarySource: nil, grants: [SourceFolderSnapshot(path: CanonicalPath.normalize(grant.path))])
        definition.workspaceSnapshot = workspace
        definition.grantedRoots = workspace.grants.map(\.path)
        try thread.replaceAdditionalFolders(workspace.grants)
        try fixture.context.save()
        let originalTitle = definition.title
        let originalRevision = definition.revision
        var draft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        draft.title = "Renamed schedule"
        try FileManager.default.removeItem(at: grant)
        try FileManager.default.createSymbolicLink(at: grant, withDestinationURL: replacement)

        // Both saving unrelated edits and adding another grant must retain the saved literal.
        for addingFolder in [false, true] {
            if addingFolder { draft.addFolderGrants([replacement.path, replacement.path]) }
            XCTAssertEqual(draft.grantedRoots.first, workspace.grants.first?.path)
            XCTAssertFalse(fixture.viewModel.save(draft))
            XCTAssertEqual(fixture.viewModel.editorErrorMessage, ScheduledTaskMutationError.workspaceRootsChanged.localizedDescription)
            XCTAssertEqual(definition.workspaceSnapshot, workspace)
            XCTAssertEqual(definition.title, originalTitle)
            XCTAssertEqual(definition.revision, originalRevision)
            XCTAssertEqual(definition.reusedThread?.persistentModelID, thread.persistentModelID)
        }
        XCTAssertEqual(draft.grantedRoots.count, 2)
    }

    func testTextOnlyEditPreservesLegacyRootsAndReusedThreadUntilGrantsChange() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let thread = try fixture.insertReusedThreadDefinition(id: "legacy-roots")
        let definition = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTask>()).first)
        let legacy = WorkspaceSnapshot(primarySource: nil, rootsExplicitlyManaged: false)
        definition.workspaceSnapshot = legacy
        thread.workspaceSnapshot = legacy
        try fixture.context.save()
        var draft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        draft.title = "Renamed schedule"

        XCTAssertTrue(fixture.viewModel.save(draft))
        XCTAssertEqual(definition.workspaceSnapshot, legacy)
        XCTAssertEqual(definition.reusedThread?.persistentModelID, thread.persistentModelID)

        draft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        draft.grantedRoots = ["/tmp/new-grant"]
        XCTAssertTrue(fixture.viewModel.save(draft))
        XCTAssertEqual(definition.workspaceSnapshot?.rootsExplicitlyManaged, true)
        XCTAssertNil(definition.reusedThread)
    }

    func testReusedThreadScheduleNamesItsCreatedThreadOnTheCardAndInTheEditor() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let thread = try fixture.insertReusedThreadDefinition(id: "reuse", threadName: "Morning triage")
        fixture.viewModel.reload()

        let presentation = try XCTUnwrap(fixture.viewModel.tasks.first)
        XCTAssertEqual(presentation.workspaceSummary, "Same thread each time · Morning triage")

        let draft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: "reuse"))
        XCTAssertEqual(draft.reusedThread?.name, "Morning triage")
        XCTAssertEqual(draft.reusedThread?.conversationID, thread.soleMainConversation?.id)
    }

    func testReusedThreadScheduleDescribesItsWorkspaceBeforeTheFirstRun() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertReusedThreadDefinition(id: "reuse", linksThread: false)
        fixture.viewModel.reload()

        XCTAssertEqual(fixture.viewModel.tasks.first?.workspaceSummary, "Same thread each time · Private workspace")
        XCTAssertNil(fixture.viewModel.makeEditDraft(definitionID: "reuse")?.reusedThread)
    }

    /// Archiving the thread is the self-heal the reuse relationship exists to allow, so neither
    /// surface may keep naming it once the next claim has decided to replace it.
    func testArchivedReusedThreadFallsBackToTheWorkspaceItWouldRecreate() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let thread = try fixture.insertReusedThreadDefinition(id: "reuse")
        thread.archivedAt = fixture.now
        try fixture.context.save()
        fixture.viewModel.reload()

        XCTAssertEqual(fixture.viewModel.tasks.first?.workspaceSummary, "Same thread each time · Private workspace")
        XCTAssertNil(fixture.viewModel.makeEditDraft(definitionID: "reuse")?.reusedThread)
    }

    func testForkedReusedThreadFallsBackToTheWorkspaceItWouldRecreate() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let thread = try fixture.insertReusedThreadDefinition(id: "reuse")
        thread.conversations.append(Conversation(id: "reuse-second-main", provider: "claude", thread: thread))
        try fixture.context.save()
        fixture.viewModel.reload()

        XCTAssertEqual(fixture.viewModel.tasks.first?.workspaceSummary, "Same thread each time · Private workspace")
        XCTAssertNil(fixture.viewModel.makeEditDraft(definitionID: "reuse")?.reusedThread)
    }

    /// Deleting the thread converts no definition — `ScheduledTaskTargetDetachment` filters to
    /// `.existingThread`, so `.scheduledTasksChanged` never fires — leaving the lifecycle
    /// notification as the only signal that stops an open Scheduled screen from naming a thread
    /// that no longer exists, or offering it in the editor's thread picker.
    func testDeletedReusedThreadRefreshesTheScreenThroughTheLifecycleNotification() async throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let thread = try fixture.insertReusedThreadDefinition(id: "reuse", threadName: "Morning triage")
        fixture.viewModel.reload()
        XCTAssertEqual(fixture.viewModel.tasks.first?.workspaceSummary, "Same thread each time · Morning triage")
        XCTAssertEqual(fixture.viewModel.existingThreadTargets.map(\.conversationID), ["reuse-main"])

        fixture.context.delete(thread)
        try fixture.context.save()
        fixture.notificationCenter.post(name: .threadLifecycleChanged, object: nil)

        let healedSummary = "Same thread each time · Private workspace"
        for _ in 0 ..< 20 where fixture.viewModel.tasks.first?.workspaceSummary != healedSummary {
            await Task.yield()
        }
        XCTAssertEqual(fixture.viewModel.tasks.first?.workspaceSummary, healedSummary)
        XCTAssertTrue(fixture.viewModel.existingThreadTargets.isEmpty)
    }

    /// The proposal payload cannot carry the service-owned reuse link, so an edit-target
    /// proposal's review pane reads it off the live definition instead.
    func testEditProposalDraftSeedsTheReuseLinkFromTheLiveDefinition() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let thread = try fixture.insertReusedThreadDefinition(id: "reuse", threadName: "Morning triage")
        fixture.viewModel.reload()

        let definitionDraft = ScheduledTaskProposalDefinitionDraft(
            title: "Reuse schedule",
            prompt: "Do the work, weekly now.",
            destination: .reusedThread,
            targetConversationID: nil,
            recurrence: .weekly(weekday: 2, hour: 9, minute: 0),
            timeZoneIdentifier: "UTC",
            providerID: "claude",
            model: nil,
            effort: "medium",
            permissionMode: "default",
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            grantedRoots: [],
            projectPath: nil
        )

        let editDraft = fixture.viewModel.makeProposalDraft(
            definitionDraft,
            definitionID: "reuse",
            expectedRevision: 1
        )
        XCTAssertEqual(editDraft.reusedThread?.name, "Morning triage")
        XCTAssertEqual(editDraft.reusedThread?.conversationID, thread.soleMainConversation?.id)

        // A create proposal has no definition yet, so it has no link to show.
        let createDraft = fixture.viewModel.makeProposalDraft(
            definitionDraft,
            definitionID: nil,
            expectedRevision: nil
        )
        XCTAssertNil(createDraft.reusedThread)
    }

    /// The editor's link row cannot select the thread itself — sidebar selection is app-wide, so
    /// the ask travels to the root as a notification.
    func testOpeningTheReusedThreadPostsAThreadOpenRequest() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        // A box, because the observer closure is `@Sendable` and cannot capture a local `var`.
        let requestedConversationID = RequestedConversationIDBox()
        let observer = fixture.notificationCenter.addObserver(
            forName: .threadOpenRequested,
            object: nil,
            queue: nil
        ) { notification in
            let request = notification.userInfo?[ThreadOpenRequestNotificationKey.request] as? ThreadOpenRequest
            requestedConversationID.value = request?.conversationID
        }
        defer { fixture.notificationCenter.removeObserver(observer) }

        fixture.viewModel.requestReusedThreadOpen(conversationID: "reuse-main")

        XCTAssertEqual(requestedConversationID.value, "reuse-main")
    }
}

@MainActor
extension ScheduledTasksViewModelFixture {
    /// A reuse schedule whose linked thread is healthy: a private workspace root and one main
    /// conversation are what `AgentThread.isHealthyReusedScheduledTaskTarget` requires.
    @discardableResult
    func insertReusedThreadDefinition(
        id: String,
        threadName: String = "Reuse thread",
        linksThread: Bool = true
    ) throws -> AgentThread {
        let thread = AgentThread(name: threadName, mode: .task)
        thread.taskWorkspaceDescriptor = TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/\(id)-workspace",
            ownershipStrategy: .projectLocal
        )
        thread.conversations = [Conversation(id: "\(id)-main", provider: "claude", thread: thread)]
        context.insert(thread)

        let definition = ScheduledTask(
            id: id,
            title: "Reuse schedule",
            prompt: "Do the work.",
            destination: .reusedThread,
            state: .active,
            recurrence: .daily(hour: 8, minute: 0),
            timeZoneIdentifier: currentTimeZone.identifier,
            providerID: "claude"
        )
        if linksThread {
            definition.reusedThread = thread
        }
        context.insert(definition)
        try context.save()
        return thread
    }
}
