import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// Covers the app-scoped half of thread creation. `SidebarViewModel` routes its own creation
/// through this same instance, so the sidebar creation suites cover the view-side wiring.
@MainActor
final class ThreadLifecycleServiceTests: XCTestCase {
    func testInsertProjectThreadCreatesActiveProjectThreadFromSeed() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")

        let thread = try fixture.viewModel.threadLifecycle.insertProjectThread(
            project: project,
            seed: ProjectThreadSeed(
                provider: "codex",
                permissionMode: "on-request",
                model: "gpt-5",
                effort: "high",
                isDraft: false
            )
        )

        XCTAssertEqual(thread.name, "New thread")
        XCTAssertFalse(thread.hasCustomName)
        XCTAssertEqual(thread.permissionMode, "on-request")
        XCTAssertEqual(thread.model, "gpt-5")
        XCTAssertEqual(thread.effort, "high")
        XCTAssertEqual(thread.effectiveMode, .project)
        XCTAssertFalse(thread.isDraft)
        XCTAssertFalse(thread.isPinned)
        XCTAssertEqual(thread.project?.path, project.path)
        XCTAssertEqual(thread.conversations.map(\.provider), ["codex"])
        XCTAssertEqual(thread.conversations.map(\.isMain), [true])
    }

    func testInsertProjectThreadNamesTheThreadAndMarksItManuallyNamed() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")

        let thread = try fixture.viewModel.threadLifecycle.insertProjectThread(
            project: project,
            seed: makeSeed(name: "Release checklist")
        )

        XCTAssertEqual(thread.name, "Release checklist")
        XCTAssertTrue(thread.hasCustomName)
    }

    func testInsertProjectThreadPinsWhenRequested() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")

        let thread = try fixture.viewModel.threadLifecycle.insertProjectThread(
            project: project,
            seed: makeSeed(pinned: true)
        )

        XCTAssertTrue(thread.isPinned)
        XCTAssertEqual(thread.pinnedSortOrder, 0)
    }

    func testInsertProjectThreadSkipsThePinInsideAPinnedProject() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")
        project.isPinned = true
        try fixture.context.save()

        let thread = try fixture.viewModel.threadLifecycle.insertProjectThread(
            project: project,
            seed: makeSeed(pinned: true)
        )

        // A pinned project absorbs its children, so the pin would be invisible and normalization
        // would clear it in the same commit.
        XCTAssertFalse(thread.isPinned)
        XCTAssertNil(thread.pinnedSortOrder)
    }

    func testInsertProjectThreadEnablesWorktreesOnlyForGitProjects() throws {
        let fixture = try SidebarTestFixture(createWorktreeByDefault: true)
        let gitProject = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")
        gitProject.gitBranch = "main"
        let plainProject = try fixture.insertProject(name: "Notes", path: "/tmp/notes")
        try fixture.context.save()

        let gitThread = try fixture.viewModel.threadLifecycle.insertProjectThread(
            project: gitProject,
            seed: makeSeed()
        )
        let plainThread = try fixture.viewModel.threadLifecycle.insertProjectThread(
            project: plainProject,
            seed: makeSeed()
        )

        XCTAssertTrue(gitThread.useWorktree)
        XCTAssertFalse(plainThread.useWorktree)
    }

    func testInsertProjectThreadByPathResolvesTheProject() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")

        let thread = try fixture.viewModel.threadLifecycle.insertProjectThread(
            projectPath: project.path,
            seed: makeSeed()
        )

        XCTAssertEqual(thread.project?.path, project.path)
    }

    func testInsertProjectThreadByPathRejectsAnUnknownProject() throws {
        let fixture = try SidebarTestFixture()

        XCTAssertThrowsError(
            try fixture.viewModel.threadLifecycle.insertProjectThread(
                projectPath: "/tmp/missing",
                seed: makeSeed()
            )
        ) { error in
            guard case .projectMissing = error as? SidebarViewModelError else {
                return XCTFail("Expected projectMissing, got \(error)")
            }
        }
    }

    func testInsertProjectThreadRollsBackAFailedSave() throws {
        let fixture = try SidebarTestFixture(saveThreadCreation: { _ in throw ThreadLifecycleTestError.saveFailed })
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")

        XCTAssertThrowsError(
            try fixture.viewModel.threadLifecycle.insertProjectThread(project: project, seed: makeSeed())
        )

        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<AgentThread>()).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<Conversation>()).isEmpty)
    }

    func testInsertTaskThreadCreatesAPrivateWorkspaceThread() throws {
        let fixture = try SidebarTestFixture()

        let thread = try fixture.viewModel.threadLifecycle.insertTaskThread(
            seed: TaskThreadSeed(
                provider: "codex",
                permissionMode: "on-request",
                model: "gpt-5",
                effort: "high",
                isDraft: false
            )
        )

        XCTAssertEqual(thread.name, "New task")
        XCTAssertFalse(thread.hasCustomName)
        XCTAssertEqual(thread.effectiveMode, .task)
        XCTAssertNil(thread.project)
        XCTAssertFalse(thread.useWorktree)
        XCTAssertFalse(thread.isPinned)
        XCTAssertEqual(thread.conversations.map(\.provider), ["codex"])
        XCTAssertEqual(thread.conversations.map(\.isMain), [true])

        let workspace = try XCTUnwrap(thread.taskWorkspaceDescriptor)
        XCTAssertEqual(workspace.ownershipStrategy, .privateOwned)
        XCTAssertTrue(workspace.grantedRoots.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.primaryRoot))
    }

    func testInsertTaskThreadNamesPinsAndGrantsFromItsSeed() throws {
        let fixture = try SidebarTestFixture()
        let granted = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: granted) }
        let canonical = CanonicalPath.normalize(granted.path)

        let thread = try fixture.viewModel.threadLifecycle.insertTaskThread(
            seed: makeTaskSeed(name: "Scratch", pinned: true, grantedRoots: [canonical])
        )

        XCTAssertEqual(thread.name, "Scratch")
        XCTAssertTrue(thread.hasCustomName)
        XCTAssertTrue(thread.isPinned)
        XCTAssertEqual(thread.pinnedSortOrder, 0)
        XCTAssertEqual(thread.taskWorkspaceDescriptor?.grantedRoots, [canonical])
    }

    /// A `.project` placement is sidebar nesting only: the thread renders under the project while
    /// keeping its own private workspace and `.task` mode.
    func testInsertTaskThreadNestsUnderItsSeedProjectPlacement() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")

        let thread = try fixture.viewModel.threadLifecycle.insertTaskThread(
            seed: makeTaskSeed(placement: .project(path: project.path))
        )

        XCTAssertEqual(thread.project?.path, project.path)
        XCTAssertEqual(thread.effectiveMode, .task)
        XCTAssertNil(thread.customSection)
        XCTAssertEqual(thread.taskWorkspaceDescriptor?.ownershipStrategy, .privateOwned)
    }

    func testInsertTaskThreadSkipsThePinAPinnedNestingProjectWouldAbsorb() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")
        project.isPinned = true
        try fixture.context.save()

        let thread = try fixture.viewModel.threadLifecycle.insertTaskThread(
            seed: makeTaskSeed(pinned: true, placement: .project(path: project.path))
        )

        // A pinned project absorbs its children, so the pin would be invisible and normalization
        // would clear it in the same commit — the same skip `insertProjectThread` makes.
        XCTAssertFalse(thread.isPinned)
        XCTAssertNil(thread.pinnedSortOrder)
        XCTAssertEqual(thread.project?.path, project.path)
    }

    func testInsertTaskThreadRejectsAVanishedPlacementProject() throws {
        let fixture = try SidebarTestFixture()

        XCTAssertThrowsError(
            try fixture.viewModel.threadLifecycle.insertTaskThread(
                seed: makeTaskSeed(placement: .project(path: "/tmp/missing-project"))
            )
        ) { error in
            guard case .projectMissing = error as? SidebarViewModelError else {
                return XCTFail("Expected projectMissing, got \(error)")
            }
        }

        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<AgentThread>()).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<Conversation>()).isEmpty)
    }

    /// The private workspace is a directory on disk, so a failed save has to take it back down.
    func testInsertTaskThreadRemovesItsWorkspaceWhenTheSaveFails() throws {
        let fixture = try SidebarTestFixture(saveThreadCreation: { _ in throw ThreadLifecycleTestError.saveFailed })
        let ownership = try XCTUnwrap(
            fixture.taskWorkspaceOwnershipService as? DefaultTaskWorkspaceOwnershipService
        )

        XCTAssertThrowsError(try fixture.viewModel.threadLifecycle.insertTaskThread(seed: makeTaskSeed()))

        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<AgentThread>()).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<Conversation>()).isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: ownership.privateWorkspacesRoot.path
        )
        XCTAssertEqual(leftovers, [])
    }

    private func makeTaskSeed(
        name: String? = nil,
        pinned: Bool = false,
        grantedRoots: [String] = [],
        placement: TaskThreadSidebarPlacement = .tasks
    ) -> TaskThreadSeed {
        TaskThreadSeed(
            provider: "claude",
            permissionMode: "default",
            model: nil,
            effort: AppSettings.defaultEffortLevel,
            isDraft: false,
            name: name,
            pinned: pinned,
            grantedRoots: grantedRoots,
            placement: placement
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-lifecycle-grants-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSeed(name: String? = nil, pinned: Bool = false) -> ProjectThreadSeed {
        ProjectThreadSeed(
            provider: "claude",
            permissionMode: "default",
            model: nil,
            effort: AppSettings.defaultEffortLevel,
            isDraft: false,
            name: name,
            pinned: pinned
        )
    }
}

enum ThreadLifecycleTestError: Error {
    case saveFailed
}
