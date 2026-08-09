import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// Rung 3 of the workspace ladder — checking the head branch out into a fresh worktree — plus the
/// rung-4 degrade and the field the whole feature depends on staying nil.
@MainActor
extension PullRequestAgenticThreadServiceTests {
    /// Registration validates both directories against the real filesystem, so these have to be
    /// real. Removed on teardown so a failed assertion does not leave them behind.
    private func makeTemporaryDirectory(_ name: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return CanonicalPath.normalize(url.path)
    }

    @discardableResult
    private func makeProject(
        in fixture: SidebarTestFixture,
        path: String,
        githubRepository: String? = nil,
        gitRemote: String? = nil,
        remoteName: String? = "origin"
    ) throws -> Project {
        let project = Project(
            path: path,
            name: "alpha",
            gitRemote: gitRemote,
            remoteName: remoteName,
            githubRepository: githubRepository
        )
        fixture.context.insert(project)
        try fixture.context.save()
        return project
    }

    private func workspace(ofThreadWith conversationID: String, in fixture: SidebarTestFixture) -> TaskWorkspaceDescriptor? {
        fixture.context.resolveConversation(conversationID: conversationID)?.thread?.taskWorkspaceDescriptor
    }

    /// The checkout is a network fetch plus a git command, so it runs behind the navigation and
    /// upgrades the thread in place once it lands.
    func testWithNoLenderTheRepositorysProjectGetsAWorktreeOnTheHeadBranch() async throws {
        let fixture = try SidebarTestFixture()
        let start = try makeStartFixture(fixture: fixture)
        let projectPath = try makeTemporaryDirectory("project")
        let worktreePath = try makeTemporaryDirectory("worktree")
        try makeProject(in: fixture, path: projectPath, githubRepository: start.identifier.nameWithOwner)
        await fixture.worktreeManager.setCreateFromBranchResult(
            WorktreeInfo(path: worktreePath, branch: "feat/change")
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        try await started.dispatch.value

        let calls = await fixture.worktreeManager.createFromBranchCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.projectPath, projectPath)
        XCTAssertEqual(calls.first?.branch, "feat/change")
        XCTAssertEqual(calls.first?.remoteName, "origin")
        let workspace = workspace(ofThreadWith: started.conversationID, in: fixture)
        XCTAssertEqual(workspace?.primaryRoot, worktreePath)
        XCTAssertEqual(workspace?.ownershipStrategy, .projectWorktreeOwned)
        XCTAssertEqual(workspace?.sourceProjectPath, projectPath)
    }

    /// `githubRepository` is written once at import and never refreshed, so a project that grew a
    /// GitHub remote afterwards is only reachable through the derived fallback.
    func testAProjectIsMatchedByItsRemoteWhenGithubRepositoryWasNeverSet() async throws {
        let fixture = try SidebarTestFixture()
        let start = try makeStartFixture(fixture: fixture)
        let projectPath = try makeTemporaryDirectory("remote-project")
        let worktreePath = try makeTemporaryDirectory("remote-worktree")
        try makeProject(in: fixture, path: projectPath, gitRemote: "git@github.com:octo/alpha.git")
        await fixture.worktreeManager.setCreateFromBranchResult(
            WorktreeInfo(path: worktreePath, branch: "feat/change")
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        try await started.dispatch.value

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.primaryRoot, worktreePath)
    }

    /// Rung 4. The agent can still read the feedback, reply, and resolve; the instructions have it
    /// say it has no checkout rather than edit whatever it landed in.
    func testAnUnknownRepositoryLeavesThePrivateWorkspaceInPlace() async throws {
        let fixture = try SidebarTestFixture()
        let start = try makeStartFixture(fixture: fixture)
        try makeProject(
            in: fixture,
            path: try makeTemporaryDirectory("unrelated"),
            githubRepository: "octo/unrelated"
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        try await started.dispatch.value

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.ownershipStrategy, .privateOwned)
        let createCalls = await fixture.worktreeManager.createFromBranchCalls()
        XCTAssertTrue(createCalls.isEmpty)
    }

    /// A checkout that fails degrades to rung 4 rather than failing the thread, which by then the
    /// user is already looking at.
    func testAFailedCheckoutLeavesThePrivateWorkspaceInPlace() async throws {
        let fixture = try SidebarTestFixture()
        let start = try makeStartFixture(fixture: fixture)
        try makeProject(
            in: fixture,
            path: try makeTemporaryDirectory("failing-project"),
            githubRepository: start.identifier.nameWithOwner
        )
        await fixture.worktreeManager.setCreateFromBranchResult(nil, error: .createFromBranchFailed)

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        try await started.dispatch.value

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.ownershipStrategy, .privateOwned)
    }

    /// The link ignores a detail naming a different pull request; the ladder must too, or the
    /// checkout would land on that other pull request's head branch.
    func testAMismatchedKnownDetailDoesNotSteerTheCheckout() async throws {
        let fixture = try SidebarTestFixture()
        let start = try makeStartFixture(fixture: fixture)
        let projectPath = try makeTemporaryDirectory("mismatch-project")
        let worktreePath = try makeTemporaryDirectory("mismatch-worktree")
        try makeProject(in: fixture, path: projectPath, githubRepository: start.identifier.nameWithOwner)
        await fixture.worktreeManager.setCreateFromBranchResult(
            WorktreeInfo(path: worktreePath, branch: "feat/change")
        )
        let otherIdentifier = makePullRequestSummary(number: 8, status: .open).id
        let mismatched = makePullRequestDetail(
            id: otherIdentifier,
            status: .open,
            headRefName: "feat/other-pull-request"
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: mismatched
        )
        try await started.dispatch.value

        // The deferred fetch answered with the real head branch, not the mismatched detail's.
        let calls = await fixture.worktreeManager.createFromBranchCalls()
        XCTAssertEqual(calls.map(\.branch), ["feat/change"])
    }

    /// Registration failing after the checkout landed must not leave an unowned worktree in the
    /// user's project — and its removal must not name a branch, which is the live head.
    func testAFailedRegistrationRemovesTheFreshWorktreeAndKeepsThePrivateWorkspace() async throws {
        let fixture = try SidebarTestFixture()
        let start = try makeStartFixture(fixture: fixture)
        let projectPath = try makeTemporaryDirectory("register-project")
        try makeProject(in: fixture, path: projectPath, githubRepository: start.identifier.nameWithOwner)
        // A worktree path that does not exist fails ownership registration's filesystem check.
        let missingWorktree = CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-register-missing")
        await fixture.worktreeManager.setCreateFromBranchResult(
            WorktreeInfo(path: missingWorktree, branch: "feat/change")
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        try await started.dispatch.value

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.ownershipStrategy, .privateOwned)
        let removeCalls = await fixture.worktreeManager.removeCalls()
        XCTAssertEqual(removeCalls, [
            SidebarMockWorktreeManager.RemoveCall(
                projectPath: projectPath,
                worktreePath: missingWorktree,
                branch: nil
            )
        ])
    }

    /// The hazard the whole ownership split exists for: `cleanupOwnedTaskWorktree` deletes the
    /// thread's `branch` when git still reports it on the worktree, and here that branch is the
    /// user's live pull request head. Nil is what makes permanent deletion remove only the
    /// worktree — so a Task carries its checkout in the descriptor and nowhere else.
    func testACheckedOutThreadNeverNamesThePullRequestHeadBranch() async throws {
        let fixture = try SidebarTestFixture()
        let start = try makeStartFixture(fixture: fixture)
        let projectPath = try makeTemporaryDirectory("branch-project")
        let worktreePath = try makeTemporaryDirectory("branch-worktree")
        try makeProject(in: fixture, path: projectPath, githubRepository: start.identifier.nameWithOwner)
        await fixture.worktreeManager.setCreateFromBranchResult(
            WorktreeInfo(path: worktreePath, branch: "feat/change")
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        try await started.dispatch.value

        let thread = fixture.context.resolveConversation(conversationID: started.conversationID)?.thread
        XCTAssertEqual(thread?.taskWorkspaceDescriptor?.ownershipStrategy, .projectWorktreeOwned)
        XCTAssertNil(thread?.branch)
        XCTAssertNil(thread?.worktreePath)
        XCTAssertEqual(thread?.useWorktree, false)
        XCTAssertEqual(thread?.pendingCleanupBranches, [])
    }

    /// Two clones of one repository are both valid answers, so the pane's own project decides.
    func testThePreferredProjectWinsWhenSeveralHoldTheRepository() async throws {
        let fixture = try SidebarTestFixture()
        let start = try makeStartFixture(fixture: fixture)
        let worktreePath = try makeTemporaryDirectory("preferred-worktree")
        // Sorted by path, "a-" would win on its own; the preference has to override that.
        try makeProject(
            in: fixture,
            path: try makeTemporaryDirectory("a-clone"),
            githubRepository: start.identifier.nameWithOwner
        )
        let preferred = try makeProject(
            in: fixture,
            path: try makeTemporaryDirectory("z-clone"),
            githubRepository: start.identifier.nameWithOwner
        )
        await fixture.worktreeManager.setCreateFromBranchResult(
            WorktreeInfo(path: worktreePath, branch: "feat/change")
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open),
            preferredProjectID: preferred.persistentModelID
        )
        try await started.dispatch.value

        let calls = await fixture.worktreeManager.createFromBranchCalls()
        XCTAssertEqual(calls.first?.projectPath, preferred.path)
    }
}
