import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// The workspace ladder an address-feedback thread climbs, and the rungs it refuses to climb.
/// Reviewing is checked here too, because "stays project-less" is a property of that route rather
/// than an accident of it never having had a ladder.
@MainActor
extension PullRequestAgenticThreadServiceTests {
    /// A thread standing in for one the user already has open on the pull request's branch.
    @discardableResult
    private func makeLender(
        in fixture: SidebarTestFixture,
        projectPath: String,
        worktreePath: String,
        branch: String?,
        githubRepository: String? = nil
    ) -> AgentThread {
        let project = Project(path: projectPath, name: "alpha", githubRepository: githubRepository)
        let thread = AgentThread(
            name: "Lender",
            branch: branch,
            worktreePath: worktreePath,
            useWorktree: true,
            project: project
        )
        fixture.context.insert(project)
        fixture.context.insert(thread)
        try? fixture.context.save()
        return thread
    }

    private func linkedPullRequest(_ identifier: PullRequestIdentifier) -> LinkedPullRequest {
        LinkedPullRequest(
            summary: makePullRequestSummary(number: identifier.number, repo: identifier.nameWithOwner),
            linkedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func workspace(ofThreadWith conversationID: String, in fixture: SidebarTestFixture) -> TaskWorkspaceDescriptor? {
        fixture.context.resolveConversation(conversationID: conversationID)?.thread?.taskWorkspaceDescriptor
    }

    // MARK: - Rung 1: a thread that already links the pull request

    /// The link is the most precise evidence there is, and this rung runs in front of the return,
    /// so the thread's working directory is right the moment the sidebar selects it.
    func testALinkedThreadLendsItsCheckoutBeforeTheCallerNavigates() async throws {
        let fixture = try SidebarTestFixture()
        let worktreePath = CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-lender-worktree")
        let projectPath = CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-lender-project")
        let start = try makeStartFixture(fixture: fixture, existingDirectories: [worktreePath])
        let lender = makeLender(
            in: fixture,
            projectPath: projectPath,
            worktreePath: worktreePath,
            branch: "feat/change"
        )
        lender.linkedPullRequests = [linkedPullRequest(start.identifier)]
        try fixture.context.save()

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )

        // Before `dispatch` runs: the borrow is one of the rungs that answers synchronously.
        let workspace = workspace(ofThreadWith: started.conversationID, in: fixture)
        XCTAssertEqual(workspace?.primaryRoot, worktreePath)
        XCTAssertEqual(workspace?.ownershipStrategy, .projectLocal)
        XCTAssertEqual(workspace?.sourceProjectPath, projectPath)
        _ = try await started.dispatch.value
    }

    /// A linked thread that has moved on to another branch is not a checkout of this pull request,
    /// so lending it would put the agent on the wrong code.
    func testALinkedThreadOnADifferentBranchIsNotBorrowed() async throws {
        let fixture = try SidebarTestFixture()
        let worktreePath = CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-other-branch")
        let start = try makeStartFixture(fixture: fixture, existingDirectories: [worktreePath])
        let lender = makeLender(
            in: fixture,
            projectPath: CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-other-project"),
            worktreePath: worktreePath,
            branch: "feat/something-else",
            // Not borrowing is only observable when the ladder has somewhere else to go; without a
            // project for the repository the start would refuse before reaching that question.
            githubRepository: start.identifier.nameWithOwner
        )
        lender.linkedPullRequests = [linkedPullRequest(start.identifier)]
        try fixture.context.save()

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.ownershipStrategy, .privateOwned)
        _ = try await started.dispatch.value
    }

    /// A private workspace is a scratch directory, not a checkout — and it belongs to a thread
    /// whose deletion would remove it out from under the borrower.
    func testAThreadWithOnlyAPrivateWorkspaceIsNeverBorrowed() async throws {
        let fixture = try SidebarTestFixture()
        let privateRoot = CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-private-lender")
        let start = try makeStartFixture(fixture: fixture, existingDirectories: [privateRoot])
        let lender = AgentThread(
            name: "Private lender",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: privateRoot,
                ownershipStrategy: .privateOwned,
                ownershipMarkerID: "marker"
            )
        )
        fixture.context.insert(lender)
        lender.linkedPullRequests = [linkedPullRequest(start.identifier)]
        // Refusing the borrow is only observable with a rung 3 to fall to.
        let project = Project(
            path: CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-private-project"),
            name: "alpha",
            githubRepository: start.identifier.nameWithOwner
        )
        fixture.context.insert(project)
        try fixture.context.save()

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )

        let workspace = workspace(ofThreadWith: started.conversationID, in: fixture)
        XCTAssertEqual(workspace?.ownershipStrategy, .privateOwned)
        XCTAssertNotEqual(workspace?.primaryRoot, privateRoot)
        _ = try await started.dispatch.value
    }

    /// A checkout the user deleted from disk is a stale row, not a workspace.
    func testALenderWhoseDirectoryIsGoneIsSkipped() async throws {
        let fixture = try SidebarTestFixture()
        let start = try makeStartFixture(fixture: fixture, existingDirectories: [])
        let lender = makeLender(
            in: fixture,
            projectPath: CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-gone-project"),
            worktreePath: CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-gone-worktree"),
            branch: "feat/change",
            githubRepository: start.identifier.nameWithOwner
        )
        lender.linkedPullRequests = [linkedPullRequest(start.identifier)]
        try fixture.context.save()

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.ownershipStrategy, .privateOwned)
        _ = try await started.dispatch.value
    }

    // MARK: - Rung 2: a thread already on the head branch

    /// No link, but the branch matches — and this rung has to precede creating a worktree, because
    /// git refuses a second worktree on a branch that is already checked out somewhere.
    func testAThreadOnTheHeadBranchLendsItsCheckoutWhenNothingIsLinked() async throws {
        let fixture = try SidebarTestFixture()
        let worktreePath = CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-branch-worktree")
        let start = try makeStartFixture(fixture: fixture, existingDirectories: [worktreePath])
        makeLender(
            in: fixture,
            projectPath: CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-branch-project"),
            worktreePath: worktreePath,
            branch: "feat/change"
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )

        let workspace = workspace(ofThreadWith: started.conversationID, in: fixture)
        XCTAssertEqual(workspace?.primaryRoot, worktreePath)
        XCTAssertEqual(workspace?.ownershipStrategy, .projectLocal)
        _ = try await started.dispatch.value
        let createCalls = await start.fixture.worktreeManager.createFromBranchCalls()
        XCTAssertTrue(createCalls.isEmpty)
    }

    /// When the caller had no detail, the head branch only becomes known after the deferred
    /// fetch, so the borrow lands through the upgrade rather than in front of the return.
    func testALenderFoundOnlyAfterTheDeferredFetchStillLendsItsCheckout() async throws {
        let fixture = try SidebarTestFixture()
        let worktreePath = CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-deferred-worktree")
        let start = try makeStartFixture(fixture: fixture, existingDirectories: [worktreePath])
        makeLender(
            in: fixture,
            projectPath: CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-deferred-project"),
            worktreePath: worktreePath,
            branch: "feat/change",
            // With no detail up front there is no branch to match, so the pre-flight sees no borrow
            // and needs a project for the repository to let the start through at all.
            githubRepository: start.identifier.nameWithOwner
        )

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url
        )

        // Un-borrowed in front of the return: with no detail there is no branch to match.
        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.ownershipStrategy, .privateOwned)
        _ = try await started.dispatch.value

        let workspace = workspace(ofThreadWith: started.conversationID, in: fixture)
        XCTAssertEqual(workspace?.primaryRoot, worktreePath)
        XCTAssertEqual(workspace?.ownershipStrategy, .projectLocal)
    }

    /// Reviewing needs no checkout, and borrowing one would have it reviewing whatever is checked
    /// out there rather than the pull request.
    func testAReviewThreadTakesNoCheckoutEvenWhenALenderExists() async throws {
        let fixture = try SidebarTestFixture()
        let worktreePath = CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-review-worktree")
        let start = try makeStartFixture(fixture: fixture, existingDirectories: [worktreePath])
        makeLender(
            in: fixture,
            projectPath: CanonicalPath.normalize(NSTemporaryDirectory() + "alveary-review-project"),
            worktreePath: worktreePath,
            branch: "feat/change"
        )

        let started = try await start.service.start(
            kind: .review,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        _ = try await started.dispatch.value

        XCTAssertEqual(workspace(ofThreadWith: started.conversationID, in: fixture)?.ownershipStrategy, .privateOwned)
        let createCalls = await start.fixture.worktreeManager.createFromBranchCalls()
        XCTAssertTrue(createCalls.isEmpty)
    }
}
