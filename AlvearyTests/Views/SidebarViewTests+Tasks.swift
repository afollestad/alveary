import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    func testDisabledCleanupUsesNoSignOnlyOnDirectHover() {
        let disabledReason = "Attached to a scheduled task"
        for action in ThreadCleanupAction.allCases {
            XCTAssertEqual(
                sidebarThreadCleanupSystemImage(
                    action: action,
                    disabledReason: disabledReason,
                    isCleanupButtonHovered: false
                ),
                action.systemImage
            )
            XCTAssertEqual(
                sidebarThreadCleanupSystemImage(
                    action: action,
                    disabledReason: disabledReason,
                    isCleanupButtonHovered: true
                ),
                "nosign"
            )
        }
        XCTAssertEqual(
            sidebarThreadCleanupSystemImage(action: .archive, disabledReason: nil, isCleanupButtonHovered: true),
            "archivebox"
        )
        XCTAssertEqual(
            sidebarThreadCleanupSystemImage(action: .delete, disabledReason: nil, isCleanupButtonHovered: true),
            "trash"
        )
    }

    func testTasksHeaderActionRequestsTaskModeComposer() {
        let appState = AppState()

        startNewTaskFlowFromSidebar(appState: appState)

        assertPendingTaskComposerRequest(appState)
    }

    func testTaskArchiveConfirmationMessagePointsToArchivedTasksSettings() throws {
        let fixture = try SidebarTestFixture()
        let task = makeSidebarTask(name: "Nightly audit", modifiedAt: Date())
        fixture.context.insert(task)
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertEqual(
            view.archiveConfirmationMessage(for: task),
            "This archives \"Nightly audit\". You can find archived tasks in Settings > Threads > Archived Tasks."
        )
    }

    func testTaskDeleteConfirmationDistinguishesOwnedAndGrantedFolders() {
        let task = makeSidebarTask(name: "Nightly audit", modifiedAt: Date())

        XCTAssertEqual(
            threadDeleteConfirmationMessage(for: task),
            "This permanently deletes \"Nightly audit\" and removes its Alveary-owned workspace or worktree. "
                + "Granted folders are never deleted."
        )
    }

    func testTaskContextMenuOmitsForkActionsAndDivider() {
        XCTAssertEqual(
            sidebarThreadContextMenuItems(
                isPinned: false,
                canRename: true,
                allowsPinning: true,
                allowsForking: false
            ),
            [.pin, .rename, .archive, .delete]
        )
    }

    func testNoTasksPlaceholderHiddenWhenAllActiveTasksArePinned() {
        let pinnedTask = makeSidebarTask(name: "Pinned", modifiedAt: Date(), isPinned: true)

        XCTAssertFalse(shouldShowNoTasksPlaceholder(activeTaskThreads: [], hasAnyActiveTaskThreads: true))
        XCTAssertTrue(shouldShowNoTasksPlaceholder(activeTaskThreads: [], hasAnyActiveTaskThreads: false))
        XCTAssertFalse(shouldShowNoTasksPlaceholder(activeTaskThreads: [pinnedTask], hasAnyActiveTaskThreads: true))
    }

    func testTaskSelectionAfterDeletionPrefersNextVisibleTaskThenPrevious() throws {
        let fixture = try SidebarTestFixture()
        let newest = makeSidebarTask(name: "Newest", modifiedAt: Date(timeIntervalSince1970: 300))
        let middle = makeSidebarTask(name: "Middle", modifiedAt: Date(timeIntervalSince1970: 200))
        let oldest = makeSidebarTask(name: "Oldest", modifiedAt: Date(timeIntervalSince1970: 100))
        [newest, middle, oldest].forEach(fixture.context.insert)
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertEqual(view.selectionAfterDeletingThread(middle), .thread(oldest))
        XCTAssertEqual(view.selectionAfterDeletingThread(oldest), .thread(middle))
    }

    func testPinnedProjectThreadFallbackDoesNotCrossIntoTaskDomain() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/project-thread-fallback", name: "Project")
        let firstProjectThread = AgentThread(
            name: "First project thread",
            isPinned: true,
            pinnedSortOrder: 0,
            project: project
        )
        let task = makeSidebarTask(name: "Pinned task", modifiedAt: Date(), isPinned: true)
        task.pinnedSortOrder = 1
        let secondProjectThread = AgentThread(
            name: "Second project thread",
            isPinned: true,
            pinnedSortOrder: 2,
            project: project
        )
        project.threads = [firstProjectThread, secondProjectThread]
        fixture.context.insert(project)
        fixture.context.insert(task)
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertEqual(
            view.selectionAfterDeletingThread(secondProjectThread),
            .thread(firstProjectThread)
        )
    }

    func testBlankTaskFallbackSelectsTaskThatAppearedDuringArchive() throws {
        let fixture = try SidebarTestFixture()
        let appState = AppState()
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        let newTask = makeSidebarTask(name: "Appeared during archive", modifiedAt: Date())
        fixture.context.insert(newTask)
        try fixture.context.save()

        view.completeTaskRemovalFallbackIfNeeded(true)

        XCTAssertEqual(appState.selectedSidebarItem, .thread(newTask))
        XCTAssertEqual(appState.previousSelection, .threadId(newTask.persistentModelID))
        XCTAssertNil(appState.pendingCommand)
    }

    func testTaskSelectionFallbackCrossesPinnedAndUnpinnedTaskSections() throws {
        let fixture = try SidebarTestFixture()
        let pinned = makeSidebarTask(name: "Pinned", modifiedAt: Date(timeIntervalSince1970: 300), isPinned: true)
        let newest = makeSidebarTask(name: "Newest", modifiedAt: Date(timeIntervalSince1970: 200))
        let oldest = makeSidebarTask(name: "Oldest", modifiedAt: Date(timeIntervalSince1970: 100))
        [pinned, newest, oldest].forEach(fixture.context.insert)
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertEqual(view.selectionAfterDeletingThread(pinned), .thread(newest))
        XCTAssertEqual(view.selectionAfterDeletingThread(oldest), .thread(newest))
    }

    func testPinnedTaskUsesDistinctDragSourceAndGeometryRole() throws {
        let fixture = try SidebarTestFixture()
        let task = makeSidebarTask(name: "Pinned", modifiedAt: Date(), isPinned: true)
        fixture.context.insert(task)
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertNotNil(view.pinnedItemDragConfiguration(for: task))
        XCTAssertEqual(view.pinnedItemDragGeometryRole(for: task), .pinnedTask(task.persistentModelID))
    }

    func testLinkedScheduledRunWithFallbackProjectModeUsesProjectSidebarBehavior() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/sidebar-fallback-task", name: "Project")
        fixture.context.insert(project)
        let (task, _) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "sidebar-fallback-task"
        )
        task.name = "Fallback scheduled task"
        task.modeRawValue = "future-mode"
        task.project = project
        task.isPinned = true
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertEqual(
            view.archiveConfirmationMessage(for: task),
            "This archives \"Fallback scheduled task\". "
                + "You can find archived threads in the selected project's settings, at the bottom under Archived Threads."
        )
        XCTAssertTrue(threadDeleteConfirmationMessage(for: task).contains("removes its worktree and branch if present"))
        XCTAssertNotNil(view.pinnedItemDragConfiguration(for: task))
        XCTAssertEqual(view.pinnedItemDragGeometryRole(for: task), .pinnedThread(task.persistentModelID))
        XCTAssertTrue(sidebarItem(.thread(task), belongsToProjectPath: project.path) { _ in project.path })
    }

    func testDeletingLastSelectedTaskRequestsBlankTaskComposerAfterSuccess() async throws {
        let fixture = try SidebarTestFixture()
        let task = makeSidebarTask(name: "Only task", modifiedAt: Date())
        fixture.context.insert(task)
        try fixture.context.save()
        let appState = AppState()
        appState.selectedSidebarItem = .thread(task)
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        await view.confirmDeleteThread(task)

        XCTAssertNil(appState.selectedSidebarItem)
        assertPendingTaskComposerRequest(appState)
        XCTAssertFalse(try fixture.threadExists(task))
    }

    func testDeletingSelectedTaskClearsConversationSelectionBeforePersistenceCommit() async throws {
        let appState = AppState()
        var deletingThreadID: PersistentIdentifier?
        var selectedConversationIDAtCommit: PersistentIdentifier?
        let fixture = try SidebarTestFixture(saveDeletionCommit: { context in
            if let deletingThreadID {
                selectedConversationIDAtCommit = appState.selectedConversationIDs[deletingThreadID]
            }
            try context.save()
        })
        let task = makeSidebarTask(name: "Selected task", modifiedAt: Date())
        fixture.context.insert(task)
        try fixture.context.save()
        let conversationID = try XCTUnwrap(task.conversations.first?.persistentModelID)
        deletingThreadID = task.persistentModelID
        appState.selectedSidebarItem = .thread(task)
        appState.selectedConversationIDs[task.persistentModelID] = conversationID
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        await view.confirmDeleteThread(task)

        XCTAssertNil(selectedConversationIDAtCommit)
        XCTAssertNil(appState.selectedConversationIDs[task.persistentModelID])
        XCTAssertFalse(try fixture.threadExists(task))
    }

    func testArchivingLastSelectedTaskRequestsBlankTaskComposerAfterSuccess() async throws {
        let fixture = try SidebarTestFixture()
        let task = makeSidebarTask(name: "Only task", modifiedAt: Date())
        fixture.context.insert(task)
        try fixture.context.save()
        let appState = AppState()
        appState.selectedSidebarItem = .thread(task)
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        await view.archive(task)

        XCTAssertNil(appState.selectedSidebarItem)
        assertPendingTaskComposerRequest(appState)
        XCTAssertNotNil(try fixture.requireThread(task).archivedAt)
    }

    func testDeletingLastSelectedTaskRequestsBlankTaskComposerAfterPostCommitFailure() async throws {
        let fixture = try SidebarTestFixture()
        let task = makeSidebarTask(name: "Only task", modifiedAt: Date())
        fixture.context.insert(task)
        try fixture.context.save()
        let conversationID = try XCTUnwrap(task.conversations.first?.id)
        await fixture.agentsManager.setDestroyError(.destroyFailed(conversationID), for: conversationID)
        let appState = AppState()
        appState.selectedSidebarItem = .thread(task)
        appState.previousSelection = .threadId(task.persistentModelID)
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        await view.confirmDeleteThread(task)

        XCTAssertNil(appState.selectedSidebarItem)
        XCTAssertNil(appState.previousSelection)
        guard case .newThread(_, let mode)? = appState.pendingCommand else {
            return XCTFail("Expected a blank Task composer request")
        }
        XCTAssertEqual(mode, .task)
        XCTAssertFalse(try fixture.threadExists(task))
    }

    func testPendingScheduledCleanupFailureKeepsSelectedTaskAndConversation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-sidebar-pending-delete-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ownershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("Records", isDirectory: true)
        )
        let fixture = try SidebarTestFixture(taskWorkspaceOwnershipService: ownershipService)
        let workspace = try ownershipService.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        let branch = "alveary/sidebar-pending-delete"
        let run = makeSidebarPendingCleanupRun()
        run.setPendingWorktreeCleanup(try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceRoot.path,
            worktreePath: worktreeRoot.path,
            branch: branch,
            sourceProjectIdentity: ownershipService.directoryIdentity(at: sourceRoot.path),
            worktreeIdentity: ownershipService.directoryIdentity(at: worktreeRoot.path),
            ownershipMarkerID: workspace.ownershipMarkerID,
            ownershipSourceProjectPath: workspace.sourceProjectPath
        )))
        let task = AgentThread(name: "Scheduled task", mode: .task, scheduledTaskRun: run)
        let conversation = Conversation(id: "sidebar-pending-delete", provider: "codex", thread: task)
        task.conversations = [conversation]
        run.thread = task
        fixture.context.insert(run)
        fixture.context.insert(task)
        try fixture.context.save()
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: branch, headOID: "owned-head")
        ])
        await fixture.worktreeManager.setDeleteBranchError(.deleteBranchFailed)

        let appState = AppState()
        appState.selectedSidebarItem = .thread(task)
        appState.previousSelection = .threadId(task.persistentModelID)
        appState.selectedConversationIDs[task.persistentModelID] = conversation.persistentModelID
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        await view.confirmDeleteThread(task)

        XCTAssertEqual(appState.selectedSidebarItem, .thread(task))
        XCTAssertEqual(appState.previousSelection, .threadId(task.persistentModelID))
        XCTAssertEqual(appState.selectedConversationIDs[task.persistentModelID], conversation.persistentModelID)
        XCTAssertNil(appState.pendingCommand)
        XCTAssertTrue(try fixture.threadExists(task))
    }

    func testArchivingLastSelectedTaskRequestsBlankTaskComposerAfterPostCommitFailure() async throws {
        let fixture = try SidebarTestFixture()
        let task = makeSidebarTask(name: "Only task", modifiedAt: Date())
        fixture.context.insert(task)
        try fixture.context.save()
        let conversationID = try XCTUnwrap(task.conversations.first?.id)
        await fixture.agentsManager.setDestroyError(.destroyFailed(conversationID), for: conversationID)
        let appState = AppState()
        appState.selectedSidebarItem = .thread(task)
        appState.previousSelection = .threadId(task.persistentModelID)
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        await view.archive(task)

        XCTAssertNil(appState.selectedSidebarItem)
        XCTAssertNil(appState.previousSelection)
        guard case .newThread(_, let mode)? = appState.pendingCommand else {
            return XCTFail("Expected a blank Task composer request")
        }
        XCTAssertEqual(mode, .task)
        XCTAssertNotNil(try fixture.requireThread(task).archivedAt)
    }

    func testProjectDeletionDeletesLinkedRunThreadWithUnknownProjectMode() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/sidebar-fallback-task-project", name: "Project")
        fixture.context.insert(project)
        let (task, _) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "project-delete-fallback-task"
        )
        task.modeRawValue = "future-mode"
        task.project = project
        try fixture.context.save()
        try await fixture.viewModel.deleteProject(project)

        XCTAssertNil(fixture.context.resolveProject(id: project.persistentModelID))
        XCTAssertNil(fixture.context.resolveThread(id: task.persistentModelID))
    }
}

@MainActor
private func assertPendingTaskComposerRequest(
    _ appState: AppState,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .newThread(_, let mode)? = appState.pendingCommand else {
        return XCTFail("Expected a blank Task composer request", file: file, line: line)
    }
    XCTAssertEqual(mode, .task, file: file, line: line)
}

@MainActor
private func makeSidebarTask(
    name: String,
    modifiedAt: Date,
    isPinned: Bool = false
) -> AgentThread {
    let task = AgentThread(
        name: name,
        isPinned: isPinned,
        modifiedAt: modifiedAt,
        mode: .task,
        taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/\(UUID().uuidString)",
            ownershipStrategy: .projectLocal
        )
    )
    task.conversations = [Conversation(
        id: UUID().uuidString,
        title: "Main",
        provider: "claude",
        thread: task
    )]
    return task
}

@MainActor
private func makeSidebarPendingCleanupRun() -> ScheduledTaskRun {
    ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "definition-\(UUID().uuidString)",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
        triggerKind: .scheduled,
        status: .failure,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "America/Chicago",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .project,
        workspaceStrategySnapshot: .worktree
    )
}
