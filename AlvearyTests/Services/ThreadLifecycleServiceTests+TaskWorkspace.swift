import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// A Task thread that has to start somewhere specific, and one whose workspace is only resolved
/// after it exists. The pull request pane's address-feedback route needs both.
@MainActor
extension ThreadLifecycleServiceTests {
    private func makeTaskWorkspaceSeed(workspace: TaskWorkspaceDescriptor?) -> TaskThreadSeed {
        TaskThreadSeed(
            provider: "claude",
            permissionMode: "default",
            model: nil,
            effort: AppSettings.defaultEffortLevel,
            isDraft: false,
            workspace: workspace
        )
    }

    private func makeBorrowedDirectory() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-lifecycle-borrowed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return CanonicalPath.normalize(url.path)
    }

    /// The root is created lazily by the first mint, so "missing" and "empty" both mean nothing
    /// was minted.
    private func mintedPrivateWorkspaces(_ fixture: SidebarTestFixture) throws -> [String] {
        let root = try XCTUnwrap(fixture.taskWorkspaceOwnershipService as? DefaultTaskWorkspaceOwnershipService)
            .privateWorkspacesRoot
            .path
        return (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
    }

    func testASeededWorkspaceIsUsedInsteadOfMintingAPrivateOne() throws {
        let fixture = try SidebarTestFixture()
        let borrowed = try makeBorrowedDirectory()

        let thread = try fixture.viewModel.threadLifecycle.insertTaskThread(
            seed: makeTaskWorkspaceSeed(
                workspace: TaskWorkspaceDescriptor(primaryRoot: borrowed, ownershipStrategy: .projectLocal)
            )
        )

        XCTAssertEqual(thread.taskWorkspaceDescriptor?.primaryRoot, borrowed)
        XCTAssertEqual(thread.taskWorkspaceDescriptor?.ownershipStrategy, .projectLocal)
        XCTAssertEqual(try mintedPrivateWorkspaces(fixture), [], "A seeded workspace must not also mint a private one")
    }

    /// The rollback removes only what the insert created. A seeded workspace can be a checkout
    /// another thread is still working in, and deleting it would take that work with it.
    func testAFailedSaveLeavesASeededWorkspaceOnDisk() throws {
        let fixture = try SidebarTestFixture(saveThreadCreation: { _ in throw ThreadLifecycleTestError.saveFailed })
        let borrowed = try makeBorrowedDirectory()

        XCTAssertThrowsError(
            try fixture.viewModel.threadLifecycle.insertTaskThread(
                seed: makeTaskWorkspaceSeed(
                    workspace: TaskWorkspaceDescriptor(primaryRoot: borrowed, ownershipStrategy: .projectLocal)
                )
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: borrowed))
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<AgentThread>()).isEmpty)
    }

    /// The upgrade path: the thread was answered with a private workspace so the caller could
    /// navigate, and the real one lands afterwards.
    func testReplacingTheWorkspaceSwapsTheDescriptorAndReleasesThePrivateOne() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.viewModel.threadLifecycle.insertTaskThread(
            seed: makeTaskWorkspaceSeed(workspace: nil)
        )
        let privateRoot = try XCTUnwrap(thread.taskWorkspaceDescriptor?.primaryRoot)
        let borrowed = try makeBorrowedDirectory()

        try fixture.viewModel.threadLifecycle.replaceTaskWorkspace(
            threadID: thread.persistentModelID,
            with: TaskWorkspaceDescriptor(primaryRoot: borrowed, ownershipStrategy: .projectLocal)
        )

        XCTAssertEqual(thread.taskWorkspaceDescriptor?.primaryRoot, borrowed)
        XCTAssertEqual(thread.taskWorkspaceDescriptor?.ownershipStrategy, .projectLocal)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: privateRoot),
            "The private workspace nothing points at any more must not be left behind"
        )
    }

    /// A Task carries its checkout in the descriptor and nowhere else. A non-nil `branch` here
    /// would offer the pull request's head branch to `branch -D` on permanent deletion.
    func testReplacingTheWorkspaceLeavesTheProjectThreadFieldsAlone() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.viewModel.threadLifecycle.insertTaskThread(
            seed: makeTaskWorkspaceSeed(workspace: nil)
        )
        let borrowed = try makeBorrowedDirectory()

        try fixture.viewModel.threadLifecycle.replaceTaskWorkspace(
            threadID: thread.persistentModelID,
            with: TaskWorkspaceDescriptor(
                primaryRoot: borrowed,
                ownershipStrategy: .projectWorktreeOwned,
                ownershipMarkerID: "marker",
                sourceProjectPath: borrowed
            )
        )

        XCTAssertNil(thread.branch)
        XCTAssertNil(thread.worktreePath)
        XCTAssertFalse(thread.useWorktree)
        XCTAssertTrue(thread.pendingCleanupBranches.isEmpty)
    }

    /// A Project thread's working directory comes from its project and worktree, so a descriptor
    /// on one would be state nothing reads.
    func testReplacingTheWorkspaceRefusesAProjectThread() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")
        let thread = try fixture.viewModel.threadLifecycle.insertProjectThread(
            project: project,
            seed: ProjectThreadSeed(
                provider: "claude",
                permissionMode: "default",
                model: nil,
                effort: AppSettings.defaultEffortLevel,
                isDraft: false
            )
        )
        let borrowed = try makeBorrowedDirectory()

        XCTAssertThrowsError(
            try fixture.viewModel.threadLifecycle.replaceTaskWorkspace(
                threadID: thread.persistentModelID,
                with: TaskWorkspaceDescriptor(primaryRoot: borrowed, ownershipStrategy: .projectLocal)
            )
        )
        XCTAssertNil(thread.taskWorkspaceDescriptor)
    }
}
