import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class SidebarViewModelTests: XCTestCase {
    func testCreateProjectPersistsResolvedRemoteAndGitHubMetadata() async throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.0.0", gitHubAuthenticated: true)
        let projectURL = try makeProjectDirectory(named: "remote-project")

        await fixture.shell.enqueue(.success(shellResult(stdout: "\(projectURL.path)\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "feature/auth\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "upstream\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "git@github.com:acme/rocket.git\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "refs/remotes/upstream/main\n")))

        let project = try await fixture.viewModel.createProject(path: projectURL.path)

        XCTAssertEqual(project.path, projectURL.path)
        XCTAssertEqual(project.name, "remote-project")
        XCTAssertEqual(project.remoteName, "upstream")
        XCTAssertEqual(project.gitRemote, "git@github.com:acme/rocket.git")
        XCTAssertEqual(project.gitBranch, "feature/auth")
        XCTAssertEqual(project.baseRef, "main")
        XCTAssertEqual(project.githubRepository, "acme/rocket")
        XCTAssertTrue(project.githubConnected)

        let invocations = await fixture.shell.invocations
        XCTAssertEqual(invocations.map(\.args), [
            ["rev-parse", "--show-toplevel"],
            ["rev-parse", "--abbrev-ref", "HEAD"],
            ["for-each-ref", "--format=%(upstream:remotename)", "refs/heads/feature/auth"],
            ["remote", "get-url", "upstream"],
            ["symbolic-ref", "refs/remotes/upstream/HEAD"]
        ])
        XCTAssertEqual(fixture.gitHubCLI.checkInstalledCallCount, 1)
        XCTAssertEqual(fixture.gitHubCLI.isAuthenticatedCallCount, 1)
    }

    func testCreateProjectAllowsLocalOnlyRepositories() async throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.0.0", gitHubAuthenticated: true)
        let projectURL = try makeProjectDirectory(named: "local-project")

        await fixture.shell.enqueue(.success(shellResult(stdout: "\(projectURL.path)\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "dev\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "\n")))

        let project = try await fixture.viewModel.createProject(path: projectURL.path)

        XCTAssertNil(project.remoteName)
        XCTAssertNil(project.gitRemote)
        XCTAssertEqual(project.gitBranch, "dev")
        XCTAssertEqual(project.baseRef, "dev")
        XCTAssertNil(project.githubRepository)
        XCTAssertFalse(project.githubConnected)
        XCTAssertEqual(fixture.gitHubCLI.checkInstalledCallCount, 0)
        XCTAssertEqual(fixture.gitHubCLI.isAuthenticatedCallCount, 0)
    }

    func testCreateProjectTreatsMissingGitHubCLIAsDisconnected() async throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: nil, gitHubAuthenticated: true)
        let projectURL = try makeProjectDirectory(named: "github-project")

        await fixture.shell.enqueue(.success(shellResult(stdout: "\(projectURL.path)\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "main\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "origin\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "https://github.com/acme/alveary.git\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "refs/remotes/origin/main\n")))

        let project = try await fixture.viewModel.createProject(path: projectURL.path)

        XCTAssertEqual(project.githubRepository, "acme/alveary")
        XCTAssertFalse(project.githubConnected)
        XCTAssertEqual(fixture.gitHubCLI.checkInstalledCallCount, 1)
        XCTAssertEqual(fixture.gitHubCLI.isAuthenticatedCallCount, 0)
    }

    func testCreateThreadSeedsDefaultsAndInitialConversation() async throws {
        let fixture = try SidebarTestFixture(defaultEffort: "max", createWorktreeByDefault: true)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")

        let readContext = ModelContext(fixture.container)
        let externalProject = try XCTUnwrap(
            try readContext.fetch(FetchDescriptor<Project>()).first
        )

        let thread = try await fixture.viewModel.createThread(
            project: externalProject,
            provider: "claude",
            permissionMode: "plan"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.name, "New thread")
        XCTAssertEqual(savedThread.permissionMode, "plan")
        XCTAssertEqual(savedThread.effort, "max")
        XCTAssertTrue(savedThread.useWorktree)
        XCTAssertEqual(savedThread.project?.path, project.path)
        XCTAssertEqual(savedThread.conversations.count, 1)
        XCTAssertEqual(savedThread.conversations.first?.provider, "claude")
        XCTAssertTrue(savedThread.conversations.first?.isMain ?? false)
        XCTAssertEqual(savedThread.conversations.first?.displayOrder, 0)
    }

    func testArchiveThreadAttemptsAllConversationTeardownsBeforeFailing() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main", "side"]
        )

        await fixture.agentsManager.setDestroyError(.destroyFailed("main"), for: "main")

        do {
            try await fixture.viewModel.archiveThread(thread)
            XCTFail("Expected archive to throw")
        } catch let error as SidebarMockAgentsManager.MockError {
            XCTAssertEqual(error, .destroyFailed("main"))
        }

        let destroyCalls = await fixture.agentsManager.destroyCalls()
        XCTAssertEqual(destroyCalls.sorted(), ["main", "side"])
        XCTAssertNil(try fixture.requireThread(thread).archivedAt)
    }

    func testRestoreThreadClearsArchiveFlag() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            archivedAt: Date()
        )

        try fixture.viewModel.restoreThread(thread)

        XCTAssertNil(try fixture.requireThread(thread).archivedAt)
    }

    func testDeleteThreadRemovesPendingBranchesAndWorktreeBeforeDeletingModel() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            branch: "alveary/live",
            pendingCleanupBranches: ["alveary/stale", "alveary/live"],
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            useWorktree: true
        )

        try await fixture.viewModel.deleteThread(thread)

        let destroyCalls = await fixture.agentsManager.destroyCalls()
        let deleteBranchCalls = await fixture.worktreeManager.deleteBranchCalls()
        let removeCalls = await fixture.worktreeManager.removeCalls()

        XCTAssertEqual(destroyCalls, ["main"])
        XCTAssertEqual(deleteBranchCalls, [
            .init(projectPath: "/tmp/alveary-project", branch: "alveary/stale")
        ])
        XCTAssertEqual(removeCalls, [
            .init(projectPath: "/tmp/alveary-project", worktreePath: "/tmp/alveary-worktree", branch: "alveary/live")
        ])
        XCTAssertFalse(try fixture.threadExists(thread))
    }

    func testDeleteThreadPreservesRecordWhenWorktreeCleanupFails() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            branch: "alveary/live",
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            useWorktree: true
        )
        await fixture.worktreeManager.setRemoveError(.removeFailed)

        do {
            try await fixture.viewModel.deleteThread(thread)
            XCTFail("Expected delete to throw")
        } catch let error as SidebarMockWorktreeManager.MockError {
            XCTAssertEqual(error, .removeFailed)
        }

        XCTAssertTrue(try fixture.threadExists(thread))
    }

    func testThreadStatusUsesDocumentedPriorityAndArchivedOverride() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["busy", "error", "idle", "neutral"]
        )

        await fixture.agentsManager.setStatus(.busy, for: "busy")
        await fixture.agentsManager.setStatus(.error, for: "error")
        await fixture.agentsManager.setStatus(.idle, for: "idle")
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .busy)

        await fixture.agentsManager.setStatus(.neutral, for: "busy")
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .error)

        await fixture.agentsManager.setStatus(.neutral, for: "error")
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .idle)

        await fixture.agentsManager.setStatus(.neutral, for: "idle")
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .stopped)

        try fixture.markThreadArchived(thread)
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .archived)
    }

    func testStatusVersionIncrementsForAgentStatusNotifications() async throws {
        let fixture = try SidebarTestFixture()

        XCTAssertEqual(fixture.viewModel.statusVersion, 0)
        NotificationCenter.default.post(name: .agentStatusChanged, object: nil)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(fixture.viewModel.statusVersion, 1)
    }

    private func makeProjectDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let configURL = url.appendingPathComponent(".alveary.json")
        try Data("{}".utf8).write(to: configURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func shellResult(
        stdout: String,
        stderr: String = "",
        exitCode: Int32 = 0
    ) -> ShellResult {
        ShellResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
    }
}
