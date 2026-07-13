import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
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
