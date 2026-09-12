import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testMaterializationFreezesWorktreePreferenceBeforeSetupCompletes() throws {
        let fixture = try ConversationViewModelTestFixture(isDraft: true, hasCompletedInitialSetup: false)
        fixture.viewModel.applyWorktreePreferenceChange(true)
        XCTAssertTrue(fixture.thread.useWorktree)
        let workspace = fixture.thread.workspaceSnapshot
        try fixture.viewModel.materializeDraftWithoutMessageIfNeeded()
        _ = try draftProjectEditor(fixture).saveProjectConfiguration(
            ProjectConfiguration(name: "Now empty"), projectID: fixture.project.id
        )
        fixture.viewModel.applyWorktreePreferenceChange(false)
        XCTAssertTrue(fixture.thread.useWorktree)
        XCTAssertEqual(fixture.thread.workspaceSnapshot, workspace)
    }

    func testDraftProjectEditPreservesExplicitGrantRemovalAndWorktreeChoice() async throws {
        let fixture = try ConversationViewModelTestFixture(isDraft: true, hasCompletedInitialSetup: false)
        let editor = draftProjectEditor(fixture)
        let source = try XCTUnwrap(fixture.thread.sourceFolder)
        let secondary = SourceFolderSnapshot(path: "/tmp/draft-explicit-secondary", gitBranch: "main")
        _ = try editor.saveProjectConfiguration(
            ProjectConfiguration(name: "Project", folders: [source, secondary]), projectID: fixture.project.id
        )
        fixture.viewModel.applyWorktreePreferenceChange(true)
        fixture.viewModel.removeTaskWorkspaceGrant(secondary.path)
        try await waitUntil("draft grant removal completes") { !fixture.viewModel.isUpdatingTaskWorkspaceConfiguration }
        XCTAssertNil(fixture.viewModel.state.lastTurnError)

        _ = try editor.saveProjectConfiguration(
            ProjectConfiguration(name: "Project", folders: [secondary, source]), projectID: fixture.project.id
        )
        XCTAssertEqual(fixture.thread.sourceFolder, secondary)
        XCTAssertEqual(fixture.thread.workspaceSnapshot?.grants, [])
        XCTAssertTrue(fixture.thread.useWorktree)

        _ = try editor.saveProjectConfiguration(ProjectConfiguration(name: "Empty"), projectID: fixture.project.id)
        XCTAssertEqual(fixture.thread.mode, .task)
        XCTAssertEqual(fixture.thread.resolvedWorkspaceDescriptor?.grantedRoots, [])
        XCTAssertFalse(fixture.thread.useWorktree)
        _ = try editor.saveProjectConfiguration(
            ProjectConfiguration(name: "Project", folders: [source, secondary]), projectID: fixture.project.id
        )
        XCTAssertTrue(fixture.thread.useWorktree)
        XCTAssertEqual(fixture.thread.workspaceSnapshot?.grants, [])
    }

    func testProjectEditsDoNotRetargetInitialWorktreeOrGrants() async throws {
        let fixture = try ConversationViewModelTestFixture(useWorktree: true, hasCompletedInitialSetup: false)
        let original = try XCTUnwrap(fixture.thread.sourceFolder)
        let grant = SourceFolderSnapshot(path: "/tmp/original-grant", gitBranch: "main")
        try fixture.thread.replaceAdditionalFolders([grant])
        fixture.project.primaryFolder?.path = "/tmp/replacement-project-source"
        fixture.project.baseRef = "replacement-base"
        fixture.project.remoteName = "replacement-remote"
        try fixture.context.save()

        try await fixture.viewModel.setupHiddenInitialRuntimeIfNeeded()

        let creates = await fixture.worktreeManager.createCalls()
        XCTAssertEqual(creates.first?.projectPath, original.path)
        XCTAssertEqual(creates.first?.baseRef, original.baseRef)
        XCTAssertEqual(creates.first?.remoteName, original.remoteName)
        let config = try fixture.viewModel.makeSpawnConfig()
        XCTAssertEqual(config.workingDirectory, "/tmp/worktree")
        XCTAssertEqual(config.additionalWorkspaceRoots, ["/tmp/worktree", grant.path])
    }

    func testLegacyNativeRootsRemainOmittedUntilWorkspaceEdit() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.thread.workspaceSnapshot = WorkspaceSnapshot(
            primarySource: fixture.thread.sourceFolder, rootsExplicitlyManaged: false
        )
        let original = try fixture.viewModel.makeSpawnConfig()
        XCTAssertEqual(original.additionalWorkspaceRoots, [])

        try fixture.thread.replaceAdditionalFolders([])
        let edited = try fixture.viewModel.makeSpawnConfig()
        XCTAssertEqual(edited.additionalWorkspaceRoots, [edited.workingDirectory])
    }

    func testCorruptWorkspaceSnapshotFailsInsteadOfDroppingGrants() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.thread.workspaceSnapshotJSON = "not-json"
        XCTAssertThrowsError(try fixture.viewModel.makeSpawnConfig(workingDirectory: "/tmp/existing")) { error in
            XCTAssertEqual(error.localizedDescription, WorkspaceFolderError.invalidSnapshot.localizedDescription)
        }
    }

    func testProjectGrantFinalRemovalUsesWorkingDirectoryOnlyOverride() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        try fixture.thread.replaceAdditionalFolders([SourceFolderSnapshot(path: "/tmp/missing-grant")])
        try fixture.context.save()

        fixture.viewModel.removeTaskWorkspaceGrant("/tmp/missing-grant")
        try await waitUntil("workspace update completes") { !fixture.viewModel.isUpdatingTaskWorkspaceConfiguration }

        XCTAssertEqual(fixture.thread.workspaceSnapshot?.grants, [])
        let calls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(calls.first?.config.additionalWorkspaceRoots, [fixture.project.path])
        XCTAssertNil(fixture.viewModel.state.lastTurnError)
    }

    func testFailedProjectGrantRemovalRestoresLegacyRootPolicy() async throws {
        let fixture = try ConversationViewModelTestFixture(reconfigureResult: .nextTurnRequired, providerId: "codex")
        let original = WorkspaceSnapshot(
            primarySource: fixture.thread.sourceFolder,
            grants: [SourceFolderSnapshot(path: "/tmp/old-grant")], rootsExplicitlyManaged: false
        )
        fixture.thread.workspaceSnapshot = original
        try fixture.context.save()

        fixture.viewModel.removeTaskWorkspaceGrant("/tmp/old-grant")
        try await waitUntil("workspace update completes") { !fixture.viewModel.isUpdatingTaskWorkspaceConfiguration }

        XCTAssertEqual(fixture.thread.workspaceSnapshot, original)
        let calls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(calls.first?.config.additionalWorkspaceRoots, [fixture.project.path])
        XCTAssertEqual(calls.last?.config.additionalWorkspaceRoots, ["/tmp/old-grant"])
    }
}

@MainActor
private func draftProjectEditor(_ fixture: ConversationViewModelTestFixture) -> SidebarViewModel {
    SidebarViewModel(
        agentsManager: fixture.agentsManager, modelContext: fixture.context, shell: MockShellRunner(),
        gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
        worktreeManager: fixture.worktreeManager, settingsService: fixture.settingsService,
        taskWorkspaceOwnershipService: fixture.taskWorkspaceOwnershipService, notificationManager: RecordingNotificationManager()
    )
}
