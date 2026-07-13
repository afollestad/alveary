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
        await fixture.shell.enqueue(.success(shellResult(stdout: "org-49461806@github.com:acme/rocket.git\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "refs/remotes/upstream/main\n")))

        let project = try await fixture.viewModel.createProject(path: projectURL.path)

        XCTAssertEqual(project.path, projectURL.path)
        XCTAssertEqual(project.name, "remote-project")
        XCTAssertEqual(project.remoteName, "upstream")
        XCTAssertEqual(project.gitRemote, "org-49461806@github.com:acme/rocket.git")
        XCTAssertEqual(project.gitBranch, "feature/auth")
        XCTAssertEqual(project.baseRef, "main")
        XCTAssertEqual(project.githubRepository, "acme/rocket")
        XCTAssertTrue(project.githubConnected)
        XCTAssertEqual(project.sidebarSortOrder, 0)
        XCTAssertNil(project.pinnedSortOrder)

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

    func testCreateProjectAppendsToRegularProjectOrder() async throws {
        let fixture = try SidebarTestFixture()
        let existing = Project(path: "/tmp/existing", name: "Existing", sidebarSortOrder: 0)
        fixture.context.insert(existing)
        try fixture.context.save()
        let projectURL = try makeProjectDirectory(named: "appended-project")

        await fixture.shell.enqueue(
            .success(
                shellResult(
                    stdout: "",
                    stderr: "fatal: not a git repository (or any of the parent directories): .git\n",
                    exitCode: 128
                )
            )
        )

        let project = try await fixture.viewModel.createProject(path: projectURL.path)

        XCTAssertEqual(project.sidebarSortOrder, 1)
        XCTAssertEqual(fixture.viewModel.regularProjects(from: [project, existing]).map(\.path), [
            existing.path,
            project.path
        ])
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

    func testCreateProjectAllowsNonGitDirectories() async throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.0.0", gitHubAuthenticated: true)
        let projectURL = try makeProjectDirectory(named: "plain-project")

        await fixture.shell.enqueue(
            .success(
                shellResult(
                    stdout: "",
                    stderr: "fatal: not a git repository (or any of the parent directories): .git\n",
                    exitCode: 128
                )
            )
        )

        let project = try await fixture.viewModel.createProject(path: projectURL.path)

        XCTAssertEqual(project.path, projectURL.path)
        XCTAssertEqual(project.name, "plain-project")
        XCTAssertNil(project.remoteName)
        XCTAssertNil(project.gitRemote)
        XCTAssertNil(project.gitBranch)
        XCTAssertNil(project.baseRef)
        XCTAssertNil(project.githubRepository)
        XCTAssertFalse(project.githubConnected)

        let invocations = await fixture.shell.invocations
        XCTAssertEqual(invocations.map(\.args), [
            ["rev-parse", "--show-toplevel"]
        ])
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

    func testActiveThreadsFetchesUnarchivedThreadsSortedByNameWhenModifiedDatesAreNil() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let zulu = AgentThread(name: "Zulu", archivedAt: nil, project: project)
        let alpha = AgentThread(name: "alpha", archivedAt: nil, project: project)
        let archived = AgentThread(name: "Archived", archivedAt: Date(), project: project)
        project.threads = [zulu, alpha, archived]
        fixture.context.insert(project)
        try fixture.context.save()

        let activeThreads = fixture.viewModel.activeThreads(for: project)

        XCTAssertEqual(activeThreads.map(\.persistentModelID), [alpha.persistentModelID, zulu.persistentModelID])
    }

    func testArchiveThreadArchivesBeforeReportingRuntimeCleanupFailure() async throws {
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
        } catch let error as SidebarViewModelError {
            guard case .archiveCleanupFailed(let underlying) = error,
                  let mockError = underlying as? SidebarMockAgentsManager.MockError else {
                XCTFail("Expected archive cleanup failure")
                return
            }
            XCTAssertEqual(mockError, .destroyFailed("main"))
        }

        let destroyCalls = await fixture.agentsManager.destroyCalls()
        XCTAssertEqual(destroyCalls.sorted(), ["main", "side"])
        XCTAssertNotNil(try fixture.requireThread(thread).archivedAt)
    }

    func testRestoreThreadClearsArchiveFlag() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            archivedAt: Date()
        )

        let dbThread = try fixture.requireThread(thread)
        guard let conversation = dbThread.conversations.first else {
            XCTFail("Expected a conversation")
            return
        }
        conversation.events = [
            ConversationEventRecord(
                conversationId: conversation.id,
                type: "message",
                role: "user",
                content: "Investigate the flaky sidebar reload",
                conversation: conversation
            ),
            ConversationEventRecord(
                conversationId: conversation.id,
                type: "message",
                role: "assistant",
                content: "I found a stale observer during restore.",
                conversation: conversation
            )
        ]
        try fixture.context.save()

        try await fixture.viewModel.restoreThread(thread)

        let restoredThread = try fixture.requireThread(thread)
        XCTAssertNil(restoredThread.archivedAt)
        let pendingRestoreContext = restoredThread.conversations.first?.pendingRestoreContext
        XCTAssertEqual(pendingRestoreContext?.contains("Restoring context from local history."), true)
        XCTAssertEqual(pendingRestoreContext?.contains("Investigate the flaky sidebar reload"), true)
        XCTAssertEqual(pendingRestoreContext?.contains("I found a stale observer during restore."), true)
    }

    func testDeleteThreadDeletesModelAndCleansPendingBranchesAndWorktree() async throws {
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

    func testDeleteThreadTreatsConcurrentDeletionDuringRuntimeTeardownAsSatisfied() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"]
        )
        let threadID = thread.persistentModelID

        await fixture.agentsManager.setDestroyObserver { conversationId in
            guard conversationId == "main",
                  let dbThread = fixture.context.resolveThread(id: threadID) else {
                return
            }
            fixture.context.delete(dbThread)
            try? fixture.context.save()
        }

        try await fixture.viewModel.deleteThread(thread)

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(fixture.notificationManager.markReadCalls, ["main"])
    }

    func testDeleteProjectDeletesModelsAndCleansChildThreadsAndRemainingWorktrees() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let primaryThread = AgentThread(
            name: "Primary",
            branch: "alveary/live",
            pendingCleanupBranches: ["alveary/stale", "alveary/live"],
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            useWorktree: true,
            project: project
        )
        primaryThread.conversations = [
            Conversation(id: "main", title: "Main", provider: "claude", isMain: true, displayOrder: 0, thread: primaryThread),
            Conversation(id: "side", title: "Side", provider: "claude", isMain: false, displayOrder: 1, thread: primaryThread)
        ]

        let secondaryThread = AgentThread(name: "Secondary", project: project)
        secondaryThread.conversations = [
            Conversation(id: "archived", title: "Archived", provider: "claude", isMain: true, displayOrder: 0, thread: secondaryThread)
        ]

        project.threads = [primaryThread, secondaryThread]
        fixture.context.insert(project)
        try fixture.context.save()

        try await fixture.viewModel.deleteProject(project)

        let destroyCalls = await fixture.agentsManager.destroyCalls().sorted()
        let deleteBranchCalls = await fixture.worktreeManager.deleteBranchCalls()
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let removeAllCalls = await fixture.worktreeManager.removeAllCalls()

        XCTAssertEqual(destroyCalls, ["archived", "main", "side"])
        XCTAssertEqual(deleteBranchCalls, [
            .init(projectPath: "/tmp/alveary-project", branch: "alveary/stale")
        ])
        XCTAssertEqual(removeCalls, [
            .init(projectPath: "/tmp/alveary-project", worktreePath: "/tmp/alveary-worktree", branch: "alveary/live")
        ])
        XCTAssertTrue(removeAllCalls.isEmpty)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Conversation>()), 0)
    }

    func testDeleteProjectTreatsConcurrentDeletionDuringRuntimeTeardownAsSatisfied() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = AgentThread(name: "Primary", project: project)
        thread.conversations = [
            Conversation(id: "main", title: "Main", provider: "claude", isMain: true, displayOrder: 0, thread: thread)
        ]
        project.threads = [thread]
        fixture.context.insert(project)
        try fixture.context.save()
        let projectID = project.persistentModelID

        await fixture.agentsManager.setDestroyObserver { conversationId in
            guard conversationId == "main",
                  let dbProject = fixture.context.resolveProject(id: projectID) else {
                return
            }
            fixture.context.delete(dbProject)
            try? fixture.context.save()
        }

        try await fixture.viewModel.deleteProject(project)

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(fixture.notificationManager.markReadCalls, ["main"])
    }

    func testDeleteProjectSucceedsWhenProjectFolderIsAlreadyMissing() async throws {
        let fixture = try SidebarTestFixture()
        let parentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let missingProjectURL = parentURL.appendingPathComponent("missing-project")
        let project = Project(path: missingProjectURL.path, name: "Missing")
        let thread = AgentThread(
            name: "Primary",
            branch: "alveary/live",
            pendingCleanupBranches: ["alveary/stale"],
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            useWorktree: true,
            project: project
        )
        thread.conversations = [
            Conversation(id: "main", title: "Main", provider: "claude", isMain: true, displayOrder: 0, thread: thread)
        ]

        project.threads = [thread]
        fixture.context.insert(project)
        try fixture.context.save()
        addTeardownBlock { try? FileManager.default.removeItem(at: parentURL) }

        try await fixture.viewModel.deleteProject(project)

        let destroyCalls = await fixture.agentsManager.destroyCalls()
        let deleteBranchCalls = await fixture.worktreeManager.deleteBranchCalls()
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let removeAllCalls = await fixture.worktreeManager.removeAllCalls()

        XCTAssertEqual(destroyCalls, ["main"])
        XCTAssertTrue(deleteBranchCalls.isEmpty)
        XCTAssertTrue(removeCalls.isEmpty)
        XCTAssertTrue(removeAllCalls.isEmpty)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Project>()), 0)
    }

    func testThreadStatusUsesDocumentedPriorityAndArchivedOverride() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["busy", "waiting", "error", "unread", "neutral"]
        )
        thread.conversations.first { $0.id == "unread" }?.isUnread = true
        try fixture.context.save()

        await fixture.agentsManager.setStatus(.busy, for: "busy")
        await fixture.agentsManager.setStatus(.waitingForUser, for: "waiting")
        await fixture.agentsManager.setStatus(.error, for: "error")
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .busy)

        await fixture.agentsManager.setStatus(.neutral, for: "busy")
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .waitingForUser)

        await fixture.agentsManager.setStatus(.neutral, for: "waiting")
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .error)

        await fixture.agentsManager.setStatus(.neutral, for: "error")
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .unread)

        thread.conversations.first { $0.id == "unread" }?.isUnread = false
        try fixture.context.save()
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .stopped)

        try fixture.markThreadArchived(thread)
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .archived)
    }

    func testDefaultThreadCleanupActionReflectsSettingsService() throws {
        let fixture = try SidebarTestFixture()

        XCTAssertEqual(fixture.viewModel.defaultThreadCleanupAction, .archive)

        fixture.settingsService.update { $0.defaultThreadCleanupAction = .delete }

        XCTAssertEqual(fixture.viewModel.defaultThreadCleanupAction, .delete)
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
