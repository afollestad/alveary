import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class SidebarViewTests: XCTestCase {
    func testCreateThreadDoesNotNavigateUnderVoiceModelPreparationModal() async throws {
        let fixture = try SidebarTestFixture()
        let selectedThread = try fixture.insertThread(
            projectName: "Selected",
            projectPath: "/tmp/alveary-selected"
        )
        let destinationProject = try fixture.insertProject(
            name: "Destination",
            path: "/tmp/alveary-destination"
        )
        let appState = AppState()
        appState.selectedSidebarItem = .thread(selectedThread)
        let voiceInputService = DisabledVoiceInputService()
        let lifecycleController = VoiceInputLifecycleController(service: voiceInputService)
        let modalSink = SidebarVoiceModelModalSink()
        lifecycleController.setActiveComposerSink(modalSink)
        let view = SidebarView(
            viewModel: fixture.viewModel,
            appState: appState,
            voiceInputLifecycleController: lifecycleController
        )

        await view.createThread(in: destinationProject)

        XCTAssertEqual(appState.selectedSidebarItem, .thread(selectedThread))
        XCTAssertNil(fixture.viewModel.sidebarError)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<AgentThread>()).contains { $0.isDraft })
    }

    func testDeleteFailureDoesNotRestoreSelectionUnderVoiceModelPreparationModal() async throws {
        let fixture = try SidebarTestFixture(saveDeletionCommit: { _ in
            throw SidebarVoiceModelNavigationTestError.persistenceFailed
        })
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let alpha = makeThread(name: "Alpha", project: project)
        let beta = makeThread(name: "Beta", project: project)
        fixture.context.insert(project)
        try fixture.context.save()
        let appState = AppState()
        appState.selectedSidebarItem = .thread(beta)
        appState.previousSelection = .threadId(beta.persistentModelID)
        let voiceInputService = DisabledVoiceInputService()
        let lifecycleController = VoiceInputLifecycleController(service: voiceInputService)
        let modalSink = SidebarVoiceModelModalSink()
        lifecycleController.setActiveComposerSink(modalSink)
        let view = SidebarView(
            viewModel: fixture.viewModel,
            appState: appState,
            voiceInputLifecycleController: lifecycleController
        )

        await view.confirmDeleteThread(beta)

        XCTAssertEqual(appState.selectedSidebarItem, .thread(alpha))
        XCTAssertEqual(appState.previousSelection, .threadId(alpha.persistentModelID))
        XCTAssertTrue(try fixture.threadExists(beta))
        XCTAssertNotNil(fixture.viewModel.sidebarError)
    }

    func testConfirmDeleteThreadSelectsPreviousThreadInSameProject() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let alpha = makeThread(name: "Alpha", project: project)
        let beta = makeThread(name: "Beta", project: project)
        _ = makeThread(name: "Gamma", project: project)
        fixture.context.insert(project)
        try fixture.context.save()

        let appState = AppState()
        appState.selectedSidebarItem = .thread(beta)
        appState.previousSelection = .threadId(beta.persistentModelID)

        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        await view.confirmDeleteThread(beta)

        XCTAssertEqual(appState.selectedSidebarItem, .thread(alpha))
        XCTAssertEqual(appState.previousSelection, .threadId(alpha.persistentModelID))
        XCTAssertFalse(try fixture.threadExists(beta))
    }

    func testConfirmDeleteThreadSelectsNextThreadWhenNoEarlierThreadExists() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let alpha = makeThread(name: "Alpha", project: project)
        let beta = makeThread(name: "Beta", project: project)
        fixture.context.insert(project)
        try fixture.context.save()

        let appState = AppState()
        appState.selectedSidebarItem = .thread(alpha)
        appState.previousSelection = .threadId(alpha.persistentModelID)

        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        await view.confirmDeleteThread(alpha)

        XCTAssertEqual(appState.selectedSidebarItem, .thread(beta))
        XCTAssertEqual(appState.previousSelection, .threadId(beta.persistentModelID))
        XCTAssertFalse(try fixture.threadExists(alpha))
    }

    func testConfirmDeleteThreadFallsBackToProjectWhenItWasLastThread() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = makeThread(name: "Alpha", project: project)
        fixture.context.insert(project)
        try fixture.context.save()

        let appState = AppState()
        appState.selectedSidebarItem = .thread(thread)
        appState.previousSelection = .threadId(thread.persistentModelID)

        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        await view.confirmDeleteThread(thread)

        XCTAssertEqual(appState.selectedSidebarItem, .project(project))
        XCTAssertEqual(appState.previousSelection, .projectPath(project.path))
        XCTAssertFalse(try fixture.threadExists(thread))
    }

    func testArchiveConfirmationMessagePointsToProjectSettingsArchivedThreads() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )
        let appState = AppState()
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        let message = view.archiveConfirmationMessage(for: thread)

        XCTAssertEqual(
            message,
            "This archives \"Thread\". You can find archived threads in the selected project's settings, at the bottom under Archived Threads."
        )
    }

    func testDeleteConfirmationMessageQuotesThreadName() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )
        let appState = AppState()
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        let message = view.deleteConfirmationMessage(for: thread)

        XCTAssertEqual(
            message,
            "This permanently deletes \"Thread\" from Alveary and removes its worktree and branch if present."
        )
    }

    func testDeleteKeyDecisionUsesArchiveConfirmationByDefault() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )

        switch threadCleanupConfirmation(for: .thread(thread), action: .archive) {
        case .archive(let confirmedThread):
            XCTAssertEqual(confirmedThread.persistentModelID, thread.persistentModelID)
        default:
            XCTFail("Expected archive confirmation")
        }
    }

    func testDeleteKeyDecisionUsesDeleteConfirmationWhenConfigured() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )

        switch threadCleanupConfirmation(for: .thread(thread), action: .delete) {
        case .delete(let confirmedThread):
            XCTAssertEqual(confirmedThread.persistentModelID, thread.persistentModelID)
        default:
            XCTFail("Expected delete confirmation")
        }
    }

    func testDeleteKeyDecisionIgnoresNonThreadSelection() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")

        XCTAssertNil(threadCleanupConfirmation(for: .project(project), action: .archive))
        XCTAssertNil(threadCleanupConfirmation(for: .skills, action: .delete))
        XCTAssertNil(threadCleanupConfirmation(for: nil, action: .archive))
    }

    func testDeleteKeyDecisionIgnoresDraftThread() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-draft",
            isDraft: true
        )

        XCTAssertNil(threadCleanupConfirmation(for: .thread(thread), action: .archive))
        XCTAssertNil(threadCleanupConfirmation(for: .thread(thread), action: .delete))
    }

    func testThreadContextMenuItemsUseForkDividerPinRenameArchiveDeleteOrder() {
        XCTAssertEqual(sidebarThreadContextMenuItems(isPinned: false, canRename: true), [
            .forkLocal,
            .forkWorktree,
            .divider,
            .pin,
            .rename,
            .archive,
            .delete
        ])
        XCTAssertEqual(sidebarThreadContextMenuItems(isPinned: false, canRename: true).map(\.title), [
            "Fork into local",
            "Fork into worktree",
            nil,
            "Pin",
            "Rename...",
            "Archive...",
            "Delete..."
        ])
    }

    func testThreadContextMenuItemsUseUnpinForPinnedThreads() {
        XCTAssertEqual(sidebarThreadContextMenuItems(isPinned: true, canRename: true), [
            .forkLocal,
            .forkWorktree,
            .divider,
            .unpin,
            .rename,
            .archive,
            .delete
        ])
        XCTAssertEqual(sidebarThreadContextMenuItems(isPinned: true, canRename: true).map(\.title), [
            "Fork into local",
            "Fork into worktree",
            nil,
            "Unpin",
            "Rename...",
            "Archive...",
            "Delete..."
        ])
    }

    func testThreadContextMenuHidesRenameWhileAnotherRowIsEditing() {
        XCTAssertEqual(sidebarThreadContextMenuItems(isPinned: false, canRename: false), [
            .forkLocal,
            .forkWorktree,
            .divider,
            .pin,
            .archive,
            .delete
        ])
    }

    func testThreadContextMenuKeepsUnpinWhileAnotherRowIsEditing() {
        XCTAssertEqual(sidebarThreadContextMenuItems(isPinned: true, canRename: false), [
            .forkLocal,
            .forkWorktree,
            .divider,
            .unpin,
            .archive,
            .delete
        ])
    }

    func testScheduledTaskAttachmentDisablesUnpinArchiveAndDeleteWithoutRemovingThem() {
        let reason = "This task is attached to a scheduled task."
        let items = sidebarThreadContextMenuItems(isPinned: true, canRename: true)

        XCTAssertEqual(items, [
            .forkLocal,
            .forkWorktree,
            .divider,
            .unpin,
            .rename,
            .archive,
            .delete
        ])
        XCTAssertNil(
            sidebarThreadContextMenuDisabledReason(
                for: .forkLocal,
                scheduledTaskAttachmentReason: reason
            )
        )
        XCTAssertNil(
            sidebarThreadContextMenuDisabledReason(
                for: .rename,
                scheduledTaskAttachmentReason: reason
            )
        )
        for item in [SidebarThreadContextMenuItem.unpin, .archive, .delete] {
            XCTAssertEqual(
                sidebarThreadContextMenuDisabledReason(
                    for: item,
                    scheduledTaskAttachmentReason: reason
                ),
                reason
            )
        }
    }

    func testThreadContextMenuSuppressesPinActionsWhenPinningUnavailable() {
        XCTAssertEqual(sidebarThreadContextMenuItems(isPinned: false, canRename: true, allowsPinning: false), [
            .forkLocal,
            .forkWorktree,
            .divider,
            .rename,
            .archive,
            .delete
        ])
        XCTAssertEqual(sidebarThreadContextMenuItems(isPinned: true, canRename: false, allowsPinning: false), [
            .forkLocal,
            .forkWorktree,
            .divider,
            .archive,
            .delete
        ])
    }

    func testProjectPinContextMenuTitleReflectsProjectPinState() {
        XCTAssertEqual(sidebarProjectPinContextMenuTitle(isPinned: false), "Pin Project")
        XCTAssertEqual(sidebarProjectPinContextMenuTitle(isPinned: true), "Unpin Project")
    }

    func testSectionHeaderActionCenterAlignsWithProjectRowActionCenter() {
        XCTAssertEqual(
            SidebarSectionHeaderRow.actionButtonCenterTrailingInset,
            SidebarProjectRow.trailingActionCenterTrailingInset
        )
    }

    func testSelectionAfterDeletingPinnedThreadPrefersPreviousPinnedThread() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let alpha = makeThread(name: "Alpha", project: project, isPinned: true)
        let beta = makeThread(name: "Beta", project: project, isPinned: true)
        _ = makeThread(name: "Gamma", project: project, isPinned: true)
        fixture.context.insert(project)
        try fixture.context.save()

        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertEqual(view.selectionAfterDeletingThread(beta), .thread(alpha))
    }

    func testSelectionAfterDeletingPinnedThreadPrefersNextPinnedThreadWhenNoPreviousThreadExists() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let alpha = makeThread(name: "Alpha", project: project, isPinned: true)
        let beta = makeThread(name: "Beta", project: project, isPinned: true)
        fixture.context.insert(project)
        try fixture.context.save()

        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertEqual(view.selectionAfterDeletingThread(alpha), .thread(beta))
    }

    func testSelectionAfterDeletingLastPinnedThreadFallsBackToProject() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = makeThread(name: "Alpha", project: project, isPinned: true)
        fixture.context.insert(project)
        try fixture.context.save()

        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertEqual(view.selectionAfterDeletingThread(thread), .project(project))
    }

    func testSelectionAfterDeletingPinnedProjectChildPrefersVisibleSibling() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary", isPinned: true)
        let alpha = makeThread(name: "Alpha", project: project)
        let beta = makeThread(name: "Beta", project: project)
        fixture.context.insert(project)
        try fixture.context.save()

        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertEqual(view.selectionAfterDeletingThread(beta), .thread(alpha))
    }

    func testProjectMoveExpansionPreservesSelectedChildVisibility() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = makeThread(name: "Pinned Child", project: project, isPinned: true)
        fixture.context.insert(project)
        try fixture.context.save()
        let appState = AppState()
        appState.selectedSidebarItem = .thread(thread)
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        XCTAssertTrue(
            sidebarItem(
                appState.selectedSidebarItem,
                belongsToProjectPath: project.path,
                resolvedThreadProjectPath: { _ in nil }
            )
        )
        XCTAssertEqual(
            view.expandedProjectsPreservingVisibleSelection(afterMovingProject: project.path),
            [project.path]
        )
    }

    func testNoThreadsPlaceholderHiddenWhenAllActiveThreadsArePinned() throws {
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let pinnedThread = makeThread(name: "Pinned", project: project, isPinned: true)

        XCTAssertFalse(shouldShowNoThreadsPlaceholder(activeProjectThreads: [], hasAnyActiveThreads: true))
        XCTAssertTrue(shouldShowNoThreadsPlaceholder(activeProjectThreads: [], hasAnyActiveThreads: false))
        XCTAssertFalse(shouldShowNoThreadsPlaceholder(activeProjectThreads: [pinnedThread], hasAnyActiveThreads: true))
    }

    func testWorktreeTooltipTextUsesCanonicalWorktreePath() {
        let path = " \(NSHomeDirectory())/Documents/../Documents/worktrees/refactor-chat-input/ "
        let thread = AgentThread(name: "Thread", useWorktree: true)
        thread.worktreePath = path

        XCTAssertEqual(
            sidebarThreadWorktreeTooltipText(for: thread),
            "~/Documents/worktrees/refactor-chat-input"
        )
    }

    func testWorktreeTooltipTextDoesNotDecodeLiteralPercentEncoding() {
        let path = "\(NSHomeDirectory())/Documents/worktrees/refactor%20chat-input"
        let thread = AgentThread(name: "Thread", useWorktree: true)
        thread.worktreePath = path

        XCTAssertEqual(
            sidebarThreadWorktreeTooltipText(for: thread),
            "~/Documents/worktrees/refactor%20chat-input"
        )
    }

    func testWorktreeTooltipTextUsesPendingFallbackBeforePathExists() {
        let thread = AgentThread(name: "Thread", useWorktree: true)

        XCTAssertEqual(sidebarThreadWorktreeTooltipText(for: thread), "Worktree path not created yet")
    }

    private func makeThread(name: String, project: Project, isPinned: Bool = false) -> AgentThread {
        let thread = AgentThread(name: name, isPinned: isPinned, project: project)
        let conversation = Conversation(
            id: UUID().uuidString,
            title: "Main",
            provider: "claude",
            thread: thread
        )
        thread.conversations = [conversation]
        project.threads.append(thread)
        return thread
    }
}

private final class SidebarVoiceModelModalSink: VoiceInputComposerSink {
    var isModelPreparationModalPresented: Bool { true }

    func forceVoiceInputCommitSynchronously() {}
}

private enum SidebarVoiceModelNavigationTestError: Error {
    case persistenceFailed
}
