import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class WorkspaceFolderSelectionTests: XCTestCase {
    func testDefaultFollowsPrimaryFolderInsteadOfMembershipOrder() throws {
        let project = makeProject()
        let selection = WorkspaceFolderSelection()
        let owner = WorkspaceFolderOwner.project(project.id)
        XCTAssertEqual(selection.selected(in: project.workspaceFolderTargets, owner: owner)?.directory, "/tmp/app")

        project.primaryFolderID = try XCTUnwrap(project.orderedFolders.last).id
        XCTAssertEqual(project.workspaceFolderTargets.first?.directory, "/tmp/app")
        XCTAssertEqual(selection.selected(in: project.workspaceFolderTargets, owner: owner)?.directory, "/tmp/library")

        let app = try XCTUnwrap(project.workspaceFolderTargets.first)
        selection.select(app, owner: owner)
        XCTAssertEqual(selection.selected(in: project.workspaceFolderTargets, owner: owner), app)
        XCTAssertNil(selection.selected(in: [], owner: owner))
        XCTAssertEqual(selection.selected(in: Array(project.workspaceFolderTargets.dropFirst()), owner: owner)?.directory, "/tmp/library")
    }

    func testSelectionIsWindowLocalAndFallsBackAfterMembershipRemoval() throws {
        let project = makeProject()
        let firstWindow = WorkspaceFolderSelection()
        let secondWindow = WorkspaceFolderSelection()
        let folders = project.workspaceFolderTargets
        let secondary = try XCTUnwrap(folders.last)
        firstWindow.select(secondary, owner: .project(project.id))
        XCTAssertEqual(firstWindow.selected(in: folders, owner: .project(project.id)), secondary)
        XCTAssertEqual(secondWindow.selected(in: folders, owner: .project(project.id)), folders.first)
        XCTAssertEqual(firstWindow.selected(in: [folders[0]], owner: .project(project.id)), folders[0])
    }

    func testSavedThreadFoldersMapOnlyPrimaryToWorktreeAndKeepRepositoryMetadata() throws {
        let project = makeProject()
        let thread = AgentThread(name: "Work", worktreePath: "/tmp/owned-worktree", project: project)
        let snapshot = try XCTUnwrap(thread.workspaceSnapshot)
        project.primaryFolderID = project.orderedFolders.last?.id
        project.orderedFolders.first?.remoteName = "changed"

        let targets = thread.workspaceFolderTargets
        XCTAssertEqual(targets.map(\.directory), ["/tmp/owned-worktree", "/tmp/library"])
        XCTAssertEqual(targets.map(\.source.path), ["/tmp/app", "/tmp/library"])
        XCTAssertEqual(thread.workspaceSnapshot, snapshot)
        let target = DiffViewerSwitchTarget.forFolder(try XCTUnwrap(targets.last))
        XCTAssertEqual(target.directory, "/tmp/library")
        XCTAssertEqual(target.remoteName, "upstream")
        XCTAssertEqual(target.baseRef, "develop")
        XCTAssertNil(target.worktreePath)
    }

    func testSecondaryFolderUsesOneShotGenerationAndCapturedActionDirectory() throws {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)
        let context = component.modelContainer.mainContext
        let project = makeProject()
        let thread = AgentThread(name: "Work", worktreePath: "/tmp/worktree", project: project)
        let conversation = Conversation(isMain: true, thread: thread)
        thread.conversations = [conversation]
        context.insert(thread)
        try context.save()
        let appState = AppState()
        appState.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
        let selection = WorkspaceFolderSelection()
        let secondary = try XCTUnwrap(thread.workspaceFolderTargets.last)
        selection.select(secondary, owner: .thread(thread.persistentModelID))

        let target = try XCTUnwrap(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .thread(thread), modelContext: context, appState: appState,
            activeDirectory: secondary.directory, folderSelection: selection
        ))
        XCTAssertEqual(target.generationRoute, .project(directory: "/tmp/library"))
        XCTAssertEqual(target.remoteName, "upstream")
        let action = try XCTUnwrap(ToolbarProjectActionsTargetResolver.resolve(
            key: .thread(thread.persistentModelID), modelContext: context, folderSelection: selection
        ))
        selection.select(try XCTUnwrap(thread.workspaceFolderTargets.first), owner: .thread(thread.persistentModelID))
        XCTAssertEqual(action.owner, .folder(.thread(thread.persistentModelID), secondary))
        XCTAssertNil(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .thread(thread), modelContext: context, appState: appState,
            activeDirectory: secondary.directory, folderSelection: selection
        ))
        let primary = try XCTUnwrap(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .thread(thread), modelContext: context, appState: appState,
            activeDirectory: "/tmp/worktree", folderSelection: selection
        ))
        XCTAssertEqual(primary.generationRoute, .thread(
            threadID: thread.persistentModelID, conversationID: conversation.persistentModelID
        ))
    }

    func testWorktreeCanAlsoGrantItsLocalSourceCheckout() throws {
        let project = makeProject()
        let thread = AgentThread(name: "Work", worktreePath: "/tmp/worktree", project: project)
        let source = try XCTUnwrap(thread.sourceFolder)
        try thread.replaceAdditionalFolders([source])
        let targets = thread.workspaceFolderTargets
        XCTAssertEqual(targets.map(\.directory), ["/tmp/worktree", "/tmp/app"])
        XCTAssertEqual(Set(targets.map(\.id)).count, 2)
        XCTAssertEqual(thread.workspaceSnapshot?.sourceFolders, [source])
        XCTAssertEqual(thread.workspaceSnapshot?.additionalWorkspaceRoots(workingDirectory: "/tmp/worktree"), ["/tmp/worktree", "/tmp/app"])
    }

    func testCommitTargetRetainsSourceSelectionWhileOperatingAtRepositoryRoot() throws {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)
        let context = component.modelContainer.mainContext
        let project = Project(name: "Multi", folders: [
            SourceFolderSnapshot(path: "/tmp/repository/first"), SourceFolderSnapshot(path: "/tmp/repository/second")
        ])
        context.insert(project)
        try context.save()
        let selection = WorkspaceFolderSelection()
        let appState = AppState()
        let target = try XCTUnwrap(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .project(project), modelContext: context, appState: appState,
            activeDirectory: "/tmp/repository", activeSourceDirectory: "/tmp/repository/first", folderSelection: selection
        ))
        XCTAssertEqual(target.directory, "/tmp/repository")
        XCTAssertEqual(target.sourceDirectory, "/tmp/repository/first")
        XCTAssertEqual(target.generationRoute, .project(directory: "/tmp/repository"))

        selection.select(try XCTUnwrap(project.workspaceFolderTargets.last), owner: .project(project.id))
        XCTAssertNil(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .project(project), modelContext: context, appState: appState,
            activeDirectory: "/tmp/repository", activeSourceDirectory: target.sourceDirectory, folderSelection: selection
        ))
    }

    func testDiscoveredRepositoryStaysBoundToItsCapturedFolder() async {
        let selection = WorkspaceFolderSelection()
        let first = WorkspaceFolderTarget(directory: "/tmp/first", source: SourceFolderSnapshot(path: "/tmp/first"), isPrimary: true)
        let second = WorkspaceFolderTarget(directory: "/tmp/second", source: SourceFolderSnapshot(path: "/tmp/second"), isPrimary: false)
        await selection.refreshRepository(for: first) { directory in
            XCTAssertEqual(directory, first.directory)
            selection.select(second, owner: .project("project"))
            return "owner/first"
        }
        XCTAssertEqual(selection.repository(for: first), "owner/first")
        XCTAssertNil(selection.repository(for: second))
    }

    func testLinkedPullRequestChangesRefreshPrivateWorkspaceRepositoryDiscovery() async throws {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)
        let context = component.modelContainer.mainContext
        let thread = AgentThread(
            name: "Task", mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/private-task", grantedRoots: [], ownershipStrategy: .privateOwned,
                ownershipMarkerID: "task"
            )
        )
        context.insert(thread)
        try context.save()
        let folder = try XCTUnwrap(thread.workspaceFolderTargets.first)
        let selection = WorkspaceFolderSelection()
        let beforeLink = FolderRepositoryDiscoveryKey.resolve(selection: .thread(thread), folder: folder, modelContext: context)
        await selection.refreshRepository(for: folder) { _ in nil }
        XCTAssertNil(selection.repository(for: folder))

        let link = LinkedPullRequest(summary: makePullRequestSummary(number: 1), linkedAt: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(context.setLinkedPullRequests([link], for: .thread(thread.persistentModelID)))
        try context.save()
        let afterLink = FolderRepositoryDiscoveryKey.resolve(
            selection: .thread(thread), folder: thread.workspaceFolderTargets.first, modelContext: context
        )
        XCTAssertEqual(beforeLink.folder, afterLink.folder)
        XCTAssertNotEqual(beforeLink, afterLink, "Linking must restart discovery without navigating away from the task")
        XCTAssertEqual(afterLink.linkedPullRequestIDs, [link.id])

        await selection.refreshRepository(for: folder) { directory in
            XCTAssertEqual(directory, folder.directory)
            return link.id.nameWithOwner
        }
        XCTAssertEqual(selection.repository(for: folder), link.id.nameWithOwner)
        XCTAssertEqual(ContentView.pullRequestLinks(for: .thread(thread), modelContext: context).map(\.id), [link.id])
    }

    func testOlderRepositoryProbeCannotOverwriteAReplacementResult() async {
        let selection = WorkspaceFolderSelection()
        let folder = WorkspaceFolderTarget(directory: "/tmp/repo", source: SourceFolderSnapshot(path: "/tmp/repo"), isPrimary: true)
        await selection.refreshRepository(for: folder) { _ in
            await selection.refreshRepository(for: folder) { _ in "owner/new" }
            return "owner/old"
        }
        XCTAssertEqual(selection.repository(for: folder), "owner/new")
    }

    func testCompletedGitRefreshRetriesPreviouslyLinkedPrivateWorkspaceRepositoryDiscovery() async throws {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)
        let context = component.modelContainer.mainContext
        let fixture = DiffViewerTestFixture(gitService: DiffViewerMockGitService(
            statusResults: [.failure(GitError.notARepository), .success([])]
        ))
        defer { fixture.viewModel.tearDown() }
        let thread = AgentThread(name: "Task", mode: .task, taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
            primaryRoot: fixture.directory, grantedRoots: [], ownershipStrategy: .privateOwned, ownershipMarkerID: "task"
        ))
        context.insert(thread)
        try context.save()
        let link = LinkedPullRequest(summary: makePullRequestSummary(number: 1), linkedAt: Date())
        XCTAssertTrue(context.setLinkedPullRequests([link], for: .thread(thread.persistentModelID)))
        try context.save()
        let folder = try XCTUnwrap(thread.workspaceFolderTargets.first)
        let selection = WorkspaceFolderSelection()
        await fixture.viewModel.switchToTarget(.forFolder(folder))
        XCTAssertFalse(fixture.viewModel.isGitRepository)
        let beforeClone = FolderRepositoryDiscoveryKey.resolve(
            selection: .thread(thread), folder: folder, modelContext: context, diffViewModel: fixture.viewModel
        )
        await selection.refreshRepository(for: folder) { _ in nil }
        XCTAssertNil(selection.repository(for: folder))

        await fixture.viewModel.refresh(in: fixture.directory, reason: .agentTurnCompleted)
        XCTAssertTrue(fixture.viewModel.isGitRepository)
        XCTAssertEqual(fixture.viewModel.workingState.currentBranch, "feature")
        let afterClone = FolderRepositoryDiscoveryKey.resolve(
            selection: .thread(thread), folder: folder, modelContext: context, diffViewModel: fixture.viewModel
        )
        XCTAssertEqual(beforeClone.folder, afterClone.folder)
        XCTAssertEqual(beforeClone.linkedPullRequestIDs, afterClone.linkedPullRequestIDs)
        XCTAssertNotEqual(beforeClone, afterClone, "Completing the clone must retry discovery without navigation or another PR link")
        if beforeClone != afterClone {
            await selection.refreshRepository(for: folder) { directory in
                XCTAssertEqual(directory, fixture.directory)
                return link.id.nameWithOwner
            }
        }
        XCTAssertEqual(selection.repository(for: folder), link.id.nameWithOwner)
    }

    func testGitRefreshDiscoveryKeyIgnoresOtherFoldersAndKnownRepositories() async throws {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)
        let context = component.modelContainer.mainContext
        let fixture = DiffViewerTestFixture(gitService: DiffViewerMockGitService(statusResults: [.success([]), .success([])]))
        defer { fixture.viewModel.tearDown() }
        let project = Project(name: "Folders", folders: [
            SourceFolderSnapshot(path: "/tmp/other-folder"),
            SourceFolderSnapshot(path: fixture.directory, gitRemote: "https://github.com/owner/repo.git")
        ])
        context.insert(project)
        try context.save()
        let link = LinkedPullRequest(summary: makePullRequestSummary(number: 1), linkedAt: Date())
        XCTAssertTrue(context.setLinkedPullRequests([link], for: .project(project.persistentModelID)))
        try context.save()
        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        XCTAssertEqual(fixture.viewModel.activeSourceDirectory, fixture.directory)
        let targets = project.workspaceFolderTargets
        XCTAssertEqual(targets.map(\.directory), ["/tmp/other-folder", fixture.directory])
        XCTAssertEqual(targets.map(\.repository), [nil, "owner/repo"])
        let keys = project.workspaceFolderTargets.map {
            FolderRepositoryDiscoveryKey.resolve(
                selection: .project(project), folder: $0, modelContext: context, diffViewModel: fixture.viewModel
            )
        }
        XCTAssertEqual(keys.map(\.linkedPullRequestIDs), [Set([link.id]), Set([link.id])])
        XCTAssertTrue(keys.allSatisfy { $0.workspaceRefreshRevision == nil })
        let revisionBeforeRefresh = fixture.viewModel.workspaceRefreshRevision
        await fixture.viewModel.refresh(in: fixture.directory, reason: .agentTurnCompleted)
        XCTAssertGreaterThan(fixture.viewModel.workspaceRefreshRevision, revisionBeforeRefresh)
        let refreshedKeys = project.workspaceFolderTargets.map {
            FolderRepositoryDiscoveryKey.resolve(
                selection: .project(project), folder: $0, modelContext: context, diffViewModel: fixture.viewModel
            )
        }
        XCTAssertEqual(refreshedKeys.compactMap { $0.folder?.directory }, ["/tmp/other-folder", fixture.directory])
        XCTAssertEqual(keys, refreshedKeys)
    }

    private func makeProject() -> Project {
        Project(name: "Multi", folders: [
            SourceFolderSnapshot(path: "/tmp/app", gitRemote: "git@github.com:owner/app.git", remoteName: "origin", baseRef: "main"),
            SourceFolderSnapshot(path: "/tmp/library", gitRemote: "git@github.com:owner/lib.git", remoteName: "upstream", baseRef: "develop")
        ])
    }
}
