import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ThreadHostToolServiceTests {
    func testLinkPullRequestDefaultsToTheCallingConversationsThread() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )

        let result = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("linked"))
        XCTAssertEqual(content["thread_id"], .string(fixture.conversation.id))
        XCTAssertEqual(content["thread_name"], .string("Source thread"))
        let pullRequest = try object(content["pull_request"])
        XCTAssertEqual(pullRequest["repository"], .string("octo/alpha"))
        XCTAssertEqual(pullRequest["number"], .number(7))
        XCTAssertEqual(pullRequest["title"], .string("Add caching"))
        XCTAssertEqual(fixture.thread.linkedPullRequests.map(\.id), [Self.identifier])
        // The result says out loud that GitHub is untouched.
        XCTAssertTrue(result.text.contains("pull request on GitHub is unchanged"), result.text)
    }

    func testLinkPullRequestTargetsANamedThread() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Release", conversationID: "release-main")
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )

        let result = await fixture.linkPullRequest(
            url: "octo/alpha#7",
            threadID: "release-main"
        )

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["thread_id"], .string("release-main"))
        XCTAssertEqual(target.linkedPullRequests.map(\.id), [Self.identifier])
        XCTAssertEqual(fixture.thread.linkedPullRequests, [])
    }

    func testLinkingTheSamePullRequestTwiceReportsAlreadyLinked() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )
        _ = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        let result = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        XCTAssertFalse(result.isError)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("already_linked"))
        XCTAssertEqual(fixture.thread.linkedPullRequests.count, 1)
        // Nothing linked this one automatically, so the message stays a plain restatement.
        XCTAssertFalse(result.text.contains("automatically"), result.text)
    }

    /// Automatic linking fires on the very message that asks for the link, so `link_pr` reaches an
    /// already-linked thread almost every time. The message has to say why, or "already linked"
    /// reads as if the user asked twice.
    func testAlreadyLinkedNamesAutomaticLinkingWhenTheUserHasItOn() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.sidebar.settingsService.update { $0.automaticallyLinkPullRequests = true }
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )
        _ = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        let result = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        XCTAssertEqual(try object(result.structuredContent)["status"], .string("already_linked"))
        XCTAssertTrue(result.text.contains("Alveary links pull requests automatically"), result.text)
    }

    /// The explanation gates on both flags, like the detection path: with the PR feature off, a
    /// stale automatic-linking flag never fires, so naming it would explain the wrong thing.
    func testAlreadyLinkedStaysPlainWhenThePullRequestFeatureIsOff() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.sidebar.settingsService.update {
            $0.pullRequestsEnabled = false
            $0.automaticallyLinkPullRequests = true
        }
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )
        _ = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        let result = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        XCTAssertEqual(try object(result.structuredContent)["status"], .string("already_linked"))
        XCTAssertFalse(result.text.contains("automatically"), result.text)
    }

    /// A mistyped or unreachable pull request is refused rather than stored.
    func testLinkPullRequestRejectsUnparsableAndUnreachableInput() async throws {
        let fixture = try ThreadHostToolFixture()

        let unparsable = await fixture.linkPullRequest(url: "not a pull request")
        XCTAssertTrue(unparsable.isError)
        XCTAssertTrue(unparsable.text.contains("is not a GitHub pull request"), unparsable.text)
        XCTAssertEqual(fixture.pullRequests.detailCallCount, 0)

        fixture.pullRequests.detailResult = .failure(.requestFailed(statusCode: 404))
        let unreachable = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")
        XCTAssertTrue(unreachable.isError)
        XCTAssertTrue(unreachable.text.contains("could not reach that pull request"), unreachable.text)
        XCTAssertEqual(try object(unreachable.structuredContent)["status"], .string("error"))
        XCTAssertEqual(fixture.thread.linkedPullRequests, [])
    }

    func testUnlinkPullRequestRemovesTheLocalLinkOnly() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )
        _ = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")
        let callsAfterLink = fixture.pullRequests.detailCallCount

        let result = await fixture.unlinkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("unlinked"))
        XCTAssertEqual(fixture.thread.linkedPullRequests, [])
        // Nothing about unlinking may reach GitHub.
        XCTAssertEqual(fixture.pullRequests.detailCallCount, callsAfterLink)
        XCTAssertTrue(result.text.contains("not closed, merged, or deleted"), result.text)
    }

    func testUnlinkingSomethingNotLinkedReportsNotLinked() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.unlinkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        XCTAssertFalse(result.isError)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("not_linked"))
        XCTAssertEqual(try object(content["pull_request"])["repository"], .string("octo/alpha"))
    }

    func testPullRequestToolsRejectUnknownThreadsAndArguments() async throws {
        let fixture = try ThreadHostToolFixture()

        let unknownThread = await fixture.linkPullRequest(
            url: "https://github.com/octo/alpha/pull/7",
            threadID: "missing-main"
        )
        XCTAssertTrue(unknownThread.isError)
        XCTAssertEqual(unknownThread.text, ThreadHostToolServiceError.threadNotFound.localizedDescription)

        let unknownKey = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.linkPullRequestToolName,
                arguments: [
                    "url": .string("https://github.com/octo/alpha/pull/7"),
                    "owner": .string("octo")
                ]
            )
        )
        XCTAssertTrue(unknownKey.isError)
        XCTAssertTrue(unknownKey.text.contains("unsupported field(s): owner"), unknownKey.text)

        // Only link_pr requires a url; unlink_pr resolves an omitted one against the thread.
        let missingURL = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ThreadHostToolCatalog.linkPullRequestToolName)
        )
        XCTAssertTrue(missingURL.isError)
        XCTAssertTrue(missingURL.text.contains("arguments.url"), missingURL.text)
    }

    func testUnlinkWithoutAURLRemovesTheThreadsOnlyLinkedPullRequest() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )
        _ = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        let result = await fixture.unlinkPullRequest()

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("unlinked"))
        XCTAssertEqual(try object(content["pull_request"])["number"], .number(7))
        XCTAssertEqual(fixture.thread.linkedPullRequests, [])
    }

    func testUnlinkWithoutAURLReportsNotLinkedWhenTheThreadCarriesNone() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.unlinkPullRequest()

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("not_linked"))
        // Nothing was named and nothing was linked, so there is no snapshot to echo.
        XCTAssertNil(content["pull_request"])
    }

    func testUnlinkWithoutAURLRefusesAndNamesCandidatesWhenSeveralAreLinked() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )
        _ = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.secondIdentifier, title: "Fix retries", status: .open)
        )
        _ = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/9")

        let result = await fixture.unlinkPullRequest()

        XCTAssertTrue(result.isError)
        XCTAssertEqual(
            result.text,
            ThreadHostToolServiceError.ambiguousPullRequestUnlink(
                threadName: "Source thread",
                linked: ["octo/alpha#7", "octo/alpha#9"]
            ).localizedDescription
        )
        // A refusal changes nothing.
        XCTAssertEqual(fixture.thread.linkedPullRequests.count, 2)
    }

    func testListPullRequestsReturnsTheThreadsLinksNewestFirst() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )
        _ = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.secondIdentifier, title: "Fix retries", status: .merged)
        )
        _ = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/9")

        let result = await fixture.listPullRequests()

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["thread_id"], .string(fixture.conversation.id))
        XCTAssertEqual(content["thread_name"], .string("Source thread"))
        guard case .array(let rows) = content["pull_requests"] else {
            return XCTFail("Expected a pull_requests array, got \(String(describing: content["pull_requests"]))")
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(try object(rows[0])["number"], .number(9))
        XCTAssertEqual(try object(rows[0])["title"], .string("Fix retries"))
        XCTAssertEqual(try object(rows[0])["status"], .string(PullRequestStatus.merged.rawValue))
        XCTAssertNotNil(try object(rows[0])["linked_at"])
        XCTAssertEqual(try object(rows[1])["number"], .number(7))
        XCTAssertTrue(result.text.contains("octo/alpha#9 Fix retries"), result.text)
    }

    func testListPullRequestsTargetsANamedThreadAndReportsAnEmptyOne() async throws {
        let fixture = try ThreadHostToolFixture()
        _ = try fixture.insertThread(name: "Release", conversationID: "release-main")
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )
        _ = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")

        let result = await fixture.listPullRequests(threadID: "release-main")

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["thread_id"], .string("release-main"))
        XCTAssertEqual(content["pull_requests"], .array([]))
        XCTAssertTrue(result.text.contains("0 linked pull requests"), result.text)
    }

    func testListPullRequestsStaysAvailableToAnAutomatedScheduledRun() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.thread.scheduledTaskRun = fixture.attachNonterminalScheduledRun()
        try fixture.modelContext.save()

        let result = await fixture.listPullRequests()

        XCTAssertFalse(result.isError, result.text)
    }

    /// Both change Alveary's own record and each undoes the other, so a scheduled run linking the
    /// pull request it just worked on needs no confirmation.
    func testAnAutomatedScheduledRunMayLinkAndUnlinkPullRequests() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: Self.identifier, title: "Add caching", status: .open)
        )
        fixture.thread.scheduledTaskRun = fixture.attachNonterminalScheduledRun()
        try fixture.modelContext.save()

        let linked = await fixture.linkPullRequest(url: "https://github.com/octo/alpha/pull/7")
        XCTAssertFalse(linked.isError, linked.text)
        XCTAssertEqual(try object(linked.structuredContent)["status"], .string("linked"))

        let unlinked = await fixture.unlinkPullRequest(url: "https://github.com/octo/alpha/pull/7")
        XCTAssertFalse(unlinked.isError, unlinked.text)
        XCTAssertEqual(try object(unlinked.structuredContent)["status"], .string("unlinked"))
    }

    static let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
    static let secondIdentifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 9)
}

extension ThreadHostToolFixture {
    func linkPullRequest(url: String, threadID: String? = nil) async -> AgentCLIKit.AgentHostToolResult {
        await pullRequestCall(ThreadHostToolCatalog.linkPullRequestToolName, url: url, threadID: threadID)
    }

    /// `url` is optional here for the same reason it is on the tool: a thread carrying one linked
    /// pull request has nothing to disambiguate.
    func unlinkPullRequest(url: String? = nil, threadID: String? = nil) async -> AgentCLIKit.AgentHostToolResult {
        await pullRequestCall(ThreadHostToolCatalog.unlinkPullRequestToolName, url: url, threadID: threadID)
    }

    func listPullRequests(threadID: String? = nil) async -> AgentCLIKit.AgentHostToolResult {
        await pullRequestCall(ThreadHostToolCatalog.listPullRequestsToolName, url: nil, threadID: threadID)
    }

    private func pullRequestCall(
        _ toolName: String,
        url: String?,
        threadID: String?
    ) async -> AgentCLIKit.AgentHostToolResult {
        var arguments: [String: AgentCLIKit.JSONValue] = [:]
        if let url {
            arguments["url"] = .string(url)
        }
        if let threadID {
            arguments["thread_id"] = .string(threadID)
        }
        return await service.handle(
            context: agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: toolName, arguments: arguments)
        )
    }
}
