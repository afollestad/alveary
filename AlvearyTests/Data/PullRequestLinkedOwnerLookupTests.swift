import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// The pull-request pane's reverse lookup: which threads and projects link the
/// pull request being viewed. The links live in JSON columns, so the descriptors
/// only narrow to link-holding rows and the matcher does the real filtering.
@MainActor
final class PullRequestLinkedOwnerLookupTests: XCTestCase {
    private let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    // MARK: - Descriptors

    func testThreadDescriptorKeepsOnlyLinkHoldingSidebarThreads() throws {
        let context = ModelContext(try makeContainer())
        let linked = AgentThread(name: "Linked")
        let unlinked = AgentThread(name: "Unlinked")
        let draft = AgentThread(name: "Draft", isDraft: true)
        let archived = AgentThread(name: "Archived", archivedAt: Date(timeIntervalSince1970: 99))
        for thread in [linked, unlinked, draft, archived] {
            context.insert(thread)
        }
        for thread in [linked, draft, archived] {
            thread.linkedPullRequests = [link(number: 7, at: 10)]
        }
        try context.save()

        let fetched = try context.fetch(PullRequestLinkedOwnerLookup.linkHoldingThreads)

        XCTAssertEqual(fetched.map(\.name), ["Linked"])
    }

    func testProjectDescriptorKeepsOnlyLinkHoldingProjects() throws {
        let context = ModelContext(try makeContainer())
        let linked = Project(path: "/tmp/alpha", name: "Alpha")
        let unlinked = Project(path: "/tmp/beta", name: "Beta")
        context.insert(linked)
        context.insert(unlinked)
        linked.linkedPullRequests = [link(number: 7, at: 10)]
        try context.save()

        let fetched = try context.fetch(PullRequestLinkedOwnerLookup.linkHoldingProjects)

        XCTAssertEqual(fetched.map(\.name), ["Alpha"])
    }

    // MARK: - Matching

    func testOwnersMatchOnlyTheRequestedPullRequest() throws {
        let context = ModelContext(try makeContainer())
        let matching = AgentThread(name: "Matching")
        let other = AgentThread(name: "Other")
        context.insert(matching)
        context.insert(other)
        matching.linkedPullRequests = [link(number: 7, at: 10)]
        other.linkedPullRequests = [link(number: 8, at: 10)]

        let owners = PullRequestLinkedOwnerLookup.owners(
            projects: [],
            threads: [matching, other],
            linking: identifier
        )

        XCTAssertEqual(owners.map(\.displayName), ["Matching"])
        XCTAssertEqual(owners.map(\.linkOwner), [.thread(matching.persistentModelID)])
    }

    /// Projects lead, then threads; each group reads as its own linking history.
    func testOwnersListProjectsFirstThenThreadsByLinkTime() throws {
        let context = ModelContext(try makeContainer())
        let earlyProject = Project(path: "/tmp/alpha", name: "Alpha")
        let lateProject = Project(path: "/tmp/beta", name: "Beta")
        let earlyThread = AgentThread(name: "Early")
        let lateThread = AgentThread(name: "Late")
        context.insert(earlyProject)
        context.insert(lateProject)
        context.insert(earlyThread)
        context.insert(lateThread)
        lateProject.linkedPullRequests = [link(number: 7, at: 40)]
        earlyProject.linkedPullRequests = [link(number: 7, at: 30)]
        lateThread.linkedPullRequests = [link(number: 7, at: 20)]
        earlyThread.linkedPullRequests = [link(number: 7, at: 10)]

        let owners = PullRequestLinkedOwnerLookup.owners(
            projects: [lateProject, earlyProject],
            threads: [lateThread, earlyThread],
            linking: identifier
        )

        XCTAssertEqual(owners.map(\.displayName), ["Alpha", "Beta", "Early", "Late"])
        XCTAssertEqual(owners.map(\.isProject), [true, true, false, false])
    }

    func testOwnersBreakLinkTimeTiesByDisplayName() throws {
        let context = ModelContext(try makeContainer())
        let second = AgentThread(name: "Beta")
        let first = AgentThread(name: "Alpha")
        context.insert(second)
        context.insert(first)
        second.linkedPullRequests = [link(number: 7, at: 10)]
        first.linkedPullRequests = [link(number: 7, at: 10)]

        let owners = PullRequestLinkedOwnerLookup.owners(
            projects: [],
            threads: [second, first],
            linking: identifier
        )

        XCTAssertEqual(owners.map(\.displayName), ["Alpha", "Beta"])
    }

    /// Unlike the project popover's aggregate, owners are not deduplicated: each
    /// row selects a different sidebar item, so both have somewhere to go.
    func testOwnersKeepAProjectAndItsChildThreadSeparately() throws {
        let context = ModelContext(try makeContainer())
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        context.insert(project)
        let thread = AgentThread(name: "Child", project: project)
        context.insert(thread)
        let shared = link(number: 7, at: 10)
        project.linkedPullRequests = [shared]
        thread.linkedPullRequests = [shared]

        let owners = PullRequestLinkedOwnerLookup.owners(
            projects: [project],
            threads: [thread],
            linking: identifier
        )

        XCTAssertEqual(
            owners.map(\.linkOwner),
            [.project(project.persistentModelID), .thread(thread.persistentModelID)]
        )
    }

    func testMalformedLinkColumnMatchesNothing() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Broken")
        context.insert(thread)
        thread.linkedPullRequestsJSON = "{ not json"

        let owners = PullRequestLinkedOwnerLookup.owners(
            projects: [],
            threads: [thread],
            linking: identifier
        )

        XCTAssertTrue(owners.isEmpty)
    }

    // MARK: - Title

    func testTitleNamesOnlyTheKindsPresent() throws {
        let context = ModelContext(try makeContainer())
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        let thread = AgentThread(name: "Thread")
        context.insert(project)
        context.insert(thread)

        let projectOwner = PullRequestLinkingOwner.project(project)
        let threadOwner = PullRequestLinkingOwner.thread(thread)

        XCTAssertEqual(PullRequestLinkedOwnerLookup.title(for: [threadOwner]), "Linked threads")
        XCTAssertEqual(PullRequestLinkedOwnerLookup.title(for: [projectOwner]), "Linked projects")
        XCTAssertEqual(
            PullRequestLinkedOwnerLookup.title(for: [projectOwner, threadOwner]),
            "Linked threads and projects"
        )
    }

    // MARK: - Helpers

    private func link(number: Int, at seconds: TimeInterval) -> LinkedPullRequest {
        LinkedPullRequest(
            summary: makePullRequestSummary(number: number),
            linkedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
