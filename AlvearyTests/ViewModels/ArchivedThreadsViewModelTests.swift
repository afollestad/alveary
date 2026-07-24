import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ArchivedThreadsViewModelTests: XCTestCase {
    func testPermanentDeleteSanitizesRoutingAtCommitBeforeCleanupFinishes() async throws {
        let fixture = try SidebarTestFixture()
        let cleanupGate = ArchivedThreadCleanupGate()
        await fixture.agentsManager.setDestroyObserver { _ in
            await cleanupGate.waitForRelease()
        }
        let task = try insertTask(
            in: fixture,
            name: "Commit boundary",
            archivedAt: Date()
        )
        let conversationID = try XCTUnwrap(task.conversations.first?.persistentModelID)
        let (viewModel, appState) = makeViewModel(fixture: fixture)
        appState.selectedSidebarItem = .thread(task)
        appState.previousSelection = .threadId(task.persistentModelID)
        appState.selectedConversationIDs[task.persistentModelID] = conversationID
        fixture.settingsService.updateRestoreSelection(
            threadID: task.persistentModelID,
            conversationID: conversationID
        )
        viewModel.refresh()
        let item = try XCTUnwrap(viewModel.items.first)

        let deletion = Task { @MainActor in
            await viewModel.confirmPermanentDeletion(item)
        }
        await cleanupGate.waitUntilEntered()

        XCTAssertNil(fixture.context.resolveThread(id: task.persistentModelID))
        XCTAssertNil(appState.selectedSidebarItem)
        XCTAssertNil(appState.previousSelection)
        XCTAssertNil(appState.selectedConversationIDs[task.persistentModelID])
        XCTAssertNil(fixture.settingsService.current.lastOpenThreadID)
        XCTAssertNil(fixture.settingsService.current.lastOpenConversationID)

        cleanupGate.release()
        await deletion.value
    }

    func testRefreshFetchesArchivedNondraftThreadsOfEveryModeInDeterministicNewestFirstOrder() throws {
        let fixture = try SidebarTestFixture()
        let oldest = try insertTask(
            in: fixture,
            name: "Zulu",
            archivedAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 500)
        )
        let alpha = try insertTask(
            in: fixture,
            name: "Alpha",
            archivedAt: Date(timeIntervalSince1970: 200),
            modifiedAt: Date(timeIntervalSince1970: 300)
        )
        let beta = try insertTask(
            in: fixture,
            name: "Beta",
            archivedAt: Date(timeIntervalSince1970: 200),
            modifiedAt: Date(timeIntervalSince1970: 400)
        )
        _ = try insertTask(in: fixture, name: "Active", archivedAt: nil)
        _ = try insertTask(in: fixture, name: "Draft", archivedAt: Date(), isDraft: true)
        // Project-mode threads used to be filtered out; the combined screen lists them too.
        let archivedProjectThread = AgentThread(
            name: "Project thread",
            archivedAt: Date(timeIntervalSince1970: 300)
        )
        fixture.context.insert(archivedProjectThread)
        try fixture.context.save()
        let viewModel = makeViewModel(fixture: fixture).viewModel

        viewModel.refresh()

        XCTAssertEqual(
            viewModel.items.map(\.id),
            [
                archivedProjectThread.persistentModelID,
                beta.persistentModelID,
                alpha.persistentModelID,
                oldest.persistentModelID
            ]
        )
        XCTAssertEqual(viewModel.items.map(\.title), ["Project thread", "Beta", "Alpha", "Zulu"])
    }

    func testRestoreAlwaysUnpinsThreadAndRemovesItFromArchivedItems() async throws {
        let fixture = try SidebarTestFixture()
        let task = try insertTask(
            in: fixture,
            name: "Restore me",
            archivedAt: Date(),
            isPinned: true,
            pinnedSortOrder: 4
        )
        let viewModel = makeViewModel(fixture: fixture).viewModel
        viewModel.refresh()
        let item = try XCTUnwrap(viewModel.items.first)
        let initialOrderVersion = fixture.viewModel.threadOrderVersion

        await viewModel.restore(item)

        let restoredTask = try XCTUnwrap(fixture.context.resolveThread(id: task.persistentModelID))
        XCTAssertNil(restoredTask.archivedAt)
        XCTAssertFalse(restoredTask.isPinned)
        XCTAssertNil(restoredTask.pinnedSortOrder)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertGreaterThan(fixture.viewModel.threadOrderVersion, initialOrderVersion)
    }

    func testConfirmedRestoreUsesPresentedItemAfterDialogBindingClearsPendingState() async throws {
        let fixture = try SidebarTestFixture()
        let task = try insertTask(in: fixture, name: "Restore race", archivedAt: Date())
        let viewModel = makeViewModel(fixture: fixture).viewModel
        viewModel.refresh()
        let item = try XCTUnwrap(viewModel.items.first)
        viewModel.requestRestore(item)
        XCTAssertEqual(viewModel.pendingRestore, item)

        viewModel.cancelRestore()
        await viewModel.confirmRestore(item)

        XCTAssertNil(viewModel.pendingRestore)
        XCTAssertNil(try XCTUnwrap(fixture.context.resolveThread(id: task.persistentModelID)).archivedAt)
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testPermanentDeleteCleansWorkspaceAndSanitizesStaleAppAndSettingsState() async throws {
        let fixture = try SidebarTestFixture()
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let task = try insertTask(
            in: fixture,
            name: "Delete me",
            archivedAt: Date(),
            workspace: workspace,
            conversationIDs: ["main", "side"]
        )
        let mainConversationID = try XCTUnwrap(task.conversations.first?.persistentModelID)
        let (viewModel, appState) = makeViewModel(fixture: fixture)
        appState.selectedSidebarItem = .thread(task)
        appState.previousSelection = .threadId(task.persistentModelID)
        appState.selectedConversationIDs[task.persistentModelID] = mainConversationID
        fixture.settingsService.updateRestoreSelection(
            threadID: task.persistentModelID,
            conversationID: mainConversationID
        )
        var commitRequestWasCancelled = false
        appState.requestCommitMessageGeneration(
            prompt: "Commit",
            threadID: task.persistentModelID,
            conversationID: mainConversationID,
            completion: { result in
                if case .failure(CommitMessageGenerationError.activeConversationChanged) = result {
                    commitRequestWasCancelled = true
                }
            }
        )
        viewModel.refresh()
        viewModel.requestPermanentDeletion(try XCTUnwrap(viewModel.items.first))

        await viewModel.confirmPermanentDeletion(try XCTUnwrap(viewModel.pendingPermanentDeletion))

        XCTAssertNil(fixture.context.resolveThread(id: task.persistentModelID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.primaryRoot))
        XCTAssertNil(appState.selectedSidebarItem)
        XCTAssertNil(appState.previousSelection)
        XCTAssertNil(appState.selectedConversationIDs[task.persistentModelID])
        XCTAssertNil(appState.pendingCommitMessageGenerationRequest)
        XCTAssertTrue(commitRequestWasCancelled)
        XCTAssertNil(fixture.settingsService.current.lastOpenThreadID)
        XCTAssertNil(fixture.settingsService.current.lastOpenConversationID)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testPrecommitDeleteFailureRollsBackAndPreservesSelectionState() async throws {
        let fixture = try SidebarTestFixture(saveDeletionCommit: { _ in
            throw ArchivedThreadsTestError.saveFailed
        })
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        defer { try? fixture.taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace) }
        let task = try insertTask(
            in: fixture,
            name: "Keep me",
            archivedAt: Date(),
            workspace: workspace
        )
        let conversationID = try XCTUnwrap(task.conversations.first?.persistentModelID)
        let (viewModel, appState) = makeViewModel(fixture: fixture)
        appState.selectedSidebarItem = .thread(task)
        appState.previousSelection = .threadId(task.persistentModelID)
        appState.selectedConversationIDs[task.persistentModelID] = conversationID
        fixture.settingsService.updateRestoreSelection(threadID: task.persistentModelID, conversationID: conversationID)
        viewModel.refresh()
        viewModel.requestPermanentDeletion(try XCTUnwrap(viewModel.items.first))

        await viewModel.confirmPermanentDeletion(try XCTUnwrap(viewModel.pendingPermanentDeletion))

        XCTAssertNotNil(fixture.context.resolveThread(id: task.persistentModelID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.primaryRoot))
        XCTAssertEqual(appState.selectedSidebarItem, .thread(task))
        XCTAssertEqual(appState.previousSelection, .threadId(task.persistentModelID))
        XCTAssertEqual(appState.selectedConversationIDs[task.persistentModelID], conversationID)
        XCTAssertEqual(fixture.settingsService.current.lastOpenThreadID, task.persistentModelID)
        XCTAssertEqual(fixture.settingsService.current.lastOpenConversationID, conversationID)
        XCTAssertEqual(viewModel.items.map(\.id), [task.persistentModelID])
        XCTAssertTrue(viewModel.errorMessage?.contains("could not be deleted") == true)
    }

    func testPostcommitCleanupFailureTreatsThreadAsDeletedAndShowsDiagnostic() async throws {
        let fixture = try SidebarTestFixture()
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        defer { try? fixture.taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace) }
        let task = try insertTask(
            in: fixture,
            name: "Cleanup failure",
            archivedAt: Date(),
            workspace: workspace
        )
        let conversation = try XCTUnwrap(task.conversations.first)
        await fixture.agentsManager.setDestroyError(.destroyFailed(conversation.id), for: conversation.id)
        let (viewModel, appState) = makeViewModel(fixture: fixture)
        appState.previousSelection = .threadId(task.persistentModelID)
        appState.selectedConversationIDs[task.persistentModelID] = conversation.persistentModelID
        fixture.settingsService.updateRestoreSelection(
            threadID: task.persistentModelID,
            conversationID: conversation.persistentModelID
        )
        viewModel.refresh()
        viewModel.requestPermanentDeletion(try XCTUnwrap(viewModel.items.first))

        await viewModel.confirmPermanentDeletion(try XCTUnwrap(viewModel.pendingPermanentDeletion))

        XCTAssertNil(fixture.context.resolveThread(id: task.persistentModelID))
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(appState.previousSelection)
        XCTAssertNil(appState.selectedConversationIDs[task.persistentModelID])
        XCTAssertNil(fixture.settingsService.current.lastOpenThreadID)
        XCTAssertNil(fixture.settingsService.current.lastOpenConversationID)
        XCTAssertTrue(viewModel.errorMessage?.contains("was deleted, but cleanup did not finish") == true)
    }

    func testConfirmedDeleteUsesPresentedItemAfterDialogBindingClearsPendingState() async throws {
        let fixture = try SidebarTestFixture()
        let task = try insertTask(in: fixture, name: "Dialog race", archivedAt: Date())
        let viewModel = makeViewModel(fixture: fixture).viewModel
        viewModel.refresh()
        let item = try XCTUnwrap(viewModel.items.first)
        viewModel.requestPermanentDeletion(item)

        viewModel.cancelPermanentDeletion()
        await viewModel.confirmPermanentDeletion(item)

        XCTAssertNil(fixture.context.resolveThread(id: task.persistentModelID))
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testSuccessfulRefreshClearsTransientLoadError() throws {
        let fixture = try SidebarTestFixture()
        let task = try insertTask(in: fixture, name: "Recovered", archivedAt: Date())
        let fetchState = ArchivedThreadsFetchState()
        let appState = AppState()
        let viewModel = ArchivedThreadsViewModel(
            modelContext: fixture.context,
            sidebarViewModel: fixture.viewModel,
            appState: appState,
            settingsService: fixture.settingsService,
            fetchArchivedThreads: {
                if fetchState.shouldFail {
                    throw ArchivedThreadsTestError.fetchFailed
                }
                return [task]
            }
        )

        viewModel.refresh()
        XCTAssertTrue(viewModel.errorMessage?.contains("could not be loaded") == true)

        fetchState.shouldFail = false
        viewModel.refresh()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.items.map(\.id), [task.persistentModelID])
    }

    func testThreadLifecycleNotificationRefreshesVisibleArchivedItemsForEveryMode() throws {
        let fixture = try SidebarTestFixture()
        let task = try insertTask(in: fixture, name: "Archived elsewhere", archivedAt: Date())
        let viewModel = makeViewModel(fixture: fixture).viewModel

        viewModel.handleThreadLifecycleChanged(Notification(
            name: .threadLifecycleChanged,
            userInfo: [ThreadLifecycleNotificationKey.mode: AgentThreadMode.project.rawValue]
        ))

        XCTAssertEqual(viewModel.items.map(\.id), [task.persistentModelID])
    }

    func testArchivedLinkedScheduledRunsUseWorkspaceSnapshotForFallbackModes() async throws {
        let fixture = try SidebarTestFixture()
        let (unknownProjectModeTask, _) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "archived-unknown-project-mode-task"
        )
        let (unknownPrivateModeTask, unknownPrivateRun) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "archived-unknown-private-mode-task"
        )
        unknownProjectModeTask.modeRawValue = "future-mode"
        unknownProjectModeTask.archivedAt = Date(timeIntervalSinceReferenceDate: 100)
        unknownPrivateModeTask.modeRawValue = "future-mode"
        unknownPrivateModeTask.archivedAt = Date(timeIntervalSinceReferenceDate: 200)
        unknownPrivateRun.workspaceKindRawValueSnapshot = ScheduledTaskWorkspaceKind.privateWorkspace.rawValue
        try fixture.context.save()
        let viewModel = makeViewModel(fixture: fixture).viewModel

        viewModel.refresh()

        XCTAssertEqual(unknownProjectModeTask.effectiveMode, .project)
        XCTAssertEqual(unknownPrivateModeTask.effectiveMode, .task)
        // Both modes are listed now; only the delete-copy flag differs between them.
        XCTAssertEqual(
            viewModel.items.map(\.id),
            [unknownPrivateModeTask.persistentModelID, unknownProjectModeTask.persistentModelID]
        )
        XCTAssertEqual(viewModel.items.map(\.isTask), [true, false])

        await viewModel.restore(try XCTUnwrap(viewModel.items.first))

        XCTAssertNotNil(unknownProjectModeTask.archivedAt)
        XCTAssertNil(unknownPrivateModeTask.archivedAt)
        XCTAssertEqual(viewModel.items.map(\.id), [unknownProjectModeTask.persistentModelID])
    }
}

// Non-private so `ArchivedThreadsViewModelTests+Grouping.swift` shares these fixtures.
extension ArchivedThreadsViewModelTests {
    func makeViewModel(fixture: SidebarTestFixture) -> (viewModel: ArchivedThreadsViewModel, appState: AppState) {
        let appState = AppState()
        let viewModel = ArchivedThreadsViewModel(
            modelContext: fixture.context,
            sidebarViewModel: fixture.viewModel,
            appState: appState,
            settingsService: fixture.settingsService
        )
        return (viewModel, appState)
    }

    @discardableResult
    func insertTask(
        in fixture: SidebarTestFixture,
        name: String,
        archivedAt: Date?,
        modifiedAt: Date? = nil,
        isDraft: Bool = false,
        isPinned: Bool = false,
        pinnedSortOrder: Int? = nil,
        workspace: TaskWorkspaceDescriptor? = nil,
        conversationIDs: [String] = ["main"]
    ) throws -> AgentThread {
        let workspace = workspace ?? TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/archived-threads-\(UUID().uuidString)",
            ownershipStrategy: .projectLocal
        )
        let task = AgentThread(
            name: name,
            hasCustomName: true,
            isPinned: isPinned,
            pinnedSortOrder: pinnedSortOrder,
            isDraft: isDraft,
            modifiedAt: modifiedAt,
            archivedAt: archivedAt,
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        task.conversations = conversationIDs.enumerated().map { index, id in
            Conversation(
                id: "\(name)-\(id)",
                provider: "codex",
                isMain: index == 0,
                displayOrder: index,
                thread: task
            )
        }
        fixture.context.insert(task)
        try fixture.context.save()
        return task
    }

    @discardableResult
    func insertProjectThread(
        in fixture: SidebarTestFixture,
        name: String,
        project: Project,
        archivedAt: Date?
    ) throws -> AgentThread {
        let thread = AgentThread(
            name: name,
            hasCustomName: true,
            archivedAt: archivedAt,
            project: project
        )
        thread.conversations = [
            Conversation(id: "\(name)-main", provider: "codex", isMain: true, displayOrder: 0, thread: thread)
        ]
        fixture.context.insert(thread)
        try fixture.context.save()
        return thread
    }
}

private enum ArchivedThreadsTestError: Error {
    case fetchFailed
    case saveFailed
}

private final class ArchivedThreadsFetchState {
    var shouldFail = true
}

@MainActor
private final class ArchivedThreadCleanupGate {
    private var didEnter = false
    private var entryContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        didEnter = true
        entryContinuation?.resume()
        entryContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !didEnter else {
            return
        }
        await withCheckedContinuation { continuation in
            entryContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
