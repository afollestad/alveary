import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// Rung 3 of the workspace ladder — checking the head branch out into a fresh worktree — plus the
/// refusal that replaced the old rung-4 degrade, and the field the whole feature depends on
/// staying nil.
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

    /// A lender the *link* vouches for but `thread.branch` cannot — nil there is the ordinary case
    /// for a Task thread, which is exactly why only git can settle whether the tree is usable.
    @discardableResult
    private func makeLinkedLender(
        in fixture: SidebarTestFixture,
        identifier: PullRequestIdentifier,
        root: String,
        sourceProjectPath: String,
        githubRepository: String? = nil
    ) throws -> AgentThread {
        let project = Project(
            path: sourceProjectPath,
            name: "lender",
            remoteName: "origin",
            githubRepository: githubRepository
        )
        let thread = AgentThread(
            name: "Lender",
            branch: nil,
            worktreePath: root,
            useWorktree: true,
            project: project
        )
        fixture.context.insert(project)
        fixture.context.insert(thread)
        thread.linkedPullRequests = [
            LinkedPullRequest(
                summary: makePullRequestSummary(number: identifier.number, repo: identifier.nameWithOwner),
                linkedAt: Date(timeIntervalSince1970: 100)
            )
        ]
        try fixture.context.save()
        return thread
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
        _ = try await started.dispatch.value

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
        _ = try await started.dispatch.value

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.primaryRoot, worktreePath)
    }

    /// There is no rung 4 any more. Addressing feedback edits and pushes, so a thread on a scratch
    /// directory could not do the job — it would burn a turn discovering that. Refusing costs
    /// nothing, because the pre-flight runs before anything is created.
    func testAnUnknownRepositoryRefusesBeforeCreatingAThread() async throws {
        let fixture = try SidebarTestFixture()
        let start = try makeStartFixture(fixture: fixture)
        try makeProject(
            in: fixture,
            path: try makeTemporaryDirectory("unrelated"),
            githubRepository: "octo/unrelated"
        )
        let threadsBefore = try fixture.context.fetch(FetchDescriptor<AgentThread>()).count

        do {
            _ = try await start.service.start(
                kind: .addressFeedback,
                identifier: start.identifier,
                url: start.url,
                knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
            )
            XCTFail("Expected the start to refuse")
        } catch {
            XCTAssertEqual(
                error as? PullRequestAgenticThreadService.StartError,
                .projectMissing(repository: "octo/alpha")
            )
        }

        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<AgentThread>()).count, threadsBefore)
        let createCalls = await fixture.worktreeManager.createFromBranchCalls()
        XCTAssertTrue(createCalls.isEmpty)
    }

    /// The refusal is about having nowhere to *cut* a checkout, so a lender that can supply one
    /// answers the question before any project is consulted.
    func testALenderMakesTheMissingProjectRefusalMoot() async throws {
        let fixture = try SidebarTestFixture()
        let lenderRoot = try makeTemporaryDirectory("lender")
        let projectPath = try makeTemporaryDirectory("lender-project")
        let start = try makeStartFixture(
            fixture: fixture,
            existingDirectories: [lenderRoot],
            branchesByRoot: [lenderRoot: "feat/change"]
        )
        try makeLinkedLender(
            in: fixture,
            identifier: start.identifier,
            root: lenderRoot,
            sourceProjectPath: projectPath
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        _ = try await started.dispatch.value

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.primaryRoot, lenderRoot)
    }

    /// `isOnBranch` can only compare against `thread.branch`, which is nil for every Task thread —
    /// so a linked lender is accepted on the strength of the link and only git can say whether it
    /// is actually on the head branch.
    func testALenderOnADifferentBranchIsAbandonedForAnOwnWorktree() async throws {
        let fixture = try SidebarTestFixture()
        let lenderRoot = try makeTemporaryDirectory("stale-lender")
        let projectPath = try makeTemporaryDirectory("stale-project")
        let worktreePath = try makeTemporaryDirectory("stale-worktree")
        let start = try makeStartFixture(
            fixture: fixture,
            existingDirectories: [lenderRoot],
            branchesByRoot: [lenderRoot: "main"]
        )
        try makeLinkedLender(
            in: fixture,
            identifier: start.identifier,
            root: lenderRoot,
            sourceProjectPath: projectPath,
            githubRepository: start.identifier.nameWithOwner
        )
        await fixture.worktreeManager.setCreateFromBranchResult(
            WorktreeInfo(path: worktreePath, branch: "feat/change")
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        _ = try await started.dispatch.value

        let workspace = workspace(ofThreadWith: started.conversationID, in: fixture)
        XCTAssertEqual(workspace?.primaryRoot, worktreePath)
        XCTAssertEqual(workspace?.ownershipStrategy, .projectWorktreeOwned)
    }

    /// A lender already on the head branch is the cheapest possible answer, so nothing is cut.
    func testALenderOnTheHeadBranchIsKeptAndNoWorktreeIsCut() async throws {
        let fixture = try SidebarTestFixture()
        let lenderRoot = try makeTemporaryDirectory("good-lender")
        let projectPath = try makeTemporaryDirectory("good-project")
        let start = try makeStartFixture(
            fixture: fixture,
            existingDirectories: [lenderRoot],
            branchesByRoot: [lenderRoot: "feat/change"]
        )
        try makeLinkedLender(
            in: fixture,
            identifier: start.identifier,
            root: lenderRoot,
            sourceProjectPath: projectPath,
            githubRepository: start.identifier.nameWithOwner
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        _ = try await started.dispatch.value

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.primaryRoot, lenderRoot)
        let createCalls = await fixture.worktreeManager.createFromBranchCalls()
        XCTAssertTrue(createCalls.isEmpty)
    }

    /// Discarding a checkout on a failed probe trades a likely-correct tree for a certainly-worse
    /// one, so an unreadable branch leaves the borrow alone.
    func testAnUnreadableBranchKeepsTheBorrow() async throws {
        let fixture = try SidebarTestFixture()
        let lenderRoot = try makeTemporaryDirectory("opaque-lender")
        let projectPath = try makeTemporaryDirectory("opaque-project")
        let start = try makeStartFixture(
            fixture: fixture,
            existingDirectories: [lenderRoot]
        )
        try makeLinkedLender(
            in: fixture,
            identifier: start.identifier,
            root: lenderRoot,
            sourceProjectPath: projectPath,
            githubRepository: start.identifier.nameWithOwner
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        _ = try await started.dispatch.value

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.primaryRoot, lenderRoot)
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
        _ = try await started.dispatch.value

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
        _ = try await started.dispatch.value

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
        _ = try await started.dispatch.value

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
        _ = try await started.dispatch.value

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
        _ = try await started.dispatch.value

        let calls = await fixture.worktreeManager.createFromBranchCalls()
        XCTAssertEqual(calls.first?.projectPath, preferred.path)
    }
}
