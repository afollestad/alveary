import XCTest

@testable import Alveary

@MainActor
extension HostToolTranscriptCatalogTests {
    func testDescriptorLookupCoversBothPullRequestLinkTools() {
        for hostToolName in [
            ThreadHostToolCatalog.linkPullRequestToolName,
            ThreadHostToolCatalog.unlinkPullRequestToolName
        ] {
            XCTAssertNotNil(HostToolTranscriptCatalog.descriptor(forToolName: hostToolName), hostToolName)
            // Claude qualifies host tool names; Codex reports them bare. Both must match.
            XCTAssertNotNil(
                HostToolTranscriptCatalog.descriptor(
                    forToolName: HostToolTranscriptCatalog.toolName(hostToolName)
                ),
                hostToolName
            )
        }
        // Listing links changes nothing, so it stays an ordinary tool row.
        XCTAssertNil(
            HostToolTranscriptCatalog.descriptor(forToolName: ThreadHostToolCatalog.listPullRequestsToolName)
        )
    }

    /// Both tools apply immediately, so their result is the whole outcome; there is no
    /// marker to correlate and nothing to resolve later.
    func testPullRequestLinkWidgetsCarryNoOutcomeKey() {
        let descriptor = HostToolTranscriptCatalog.descriptor(
            forToolName: ThreadHostToolCatalog.linkPullRequestToolName
        )
        XCTAssertNil(descriptor?.outcomeKey(Self.linkedOutput))
    }

    func testLinkContentReadsTheRequestBeforeItsResultArrives() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .link,
                input: Self.linkInput,
                output: nil,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .running)
        XCTAssertEqual(content.identifier, Self.pullRequest)
        XCTAssertNil(content.title)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry(content)), "Linking pull request…")
        XCTAssertNil(entry(content).openablePullRequest)
    }

    func testLinkedResultNamesThePullRequestAndOpensIt() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .link,
                input: Self.linkInput,
                output: Self.linkedOutput,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .applied)
        XCTAssertEqual(content.identifier, Self.pullRequest)

        let entry = entry(content)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "PR linked to thread: octo/alpha#7")
        XCTAssertEqual(HostToolWidgetSummary.detail(for: entry), "Add caching")
        XCTAssertEqual(entry.openablePullRequest, Self.pullRequest)
        XCTAssertTrue(entry.isSettledWithoutDecision)
    }

    /// Automatic linking usually wins the race, so this is the common outcome and must not
    /// read as a failure.
    func testAlreadyLinkedResultSaysSoAndStillOpens() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .link,
                input: Self.linkInput,
                output: Self.output(status: "already_linked"),
                isError: false
            )
        )
        XCTAssertEqual(content.status, .unchanged)

        let entry = entry(content)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "PR already linked to thread: octo/alpha#7")
        XCTAssertEqual(entry.openablePullRequest, Self.pullRequest)
    }

    func testUnlinkedResultUsesItsOwnCopy() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .unlink,
                input: Self.linkInput,
                output: Self.output(status: "unlinked"),
                isError: false
            )
        )
        XCTAssertEqual(content.status, .applied)

        let entry = entry(content, action: .unlink)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "PR unlinked from thread: octo/alpha#7")
        // The pull request still exists on GitHub, so an unlink card opens it too.
        XCTAssertEqual(entry.openablePullRequest, Self.pullRequest)
    }

    /// `unlink_pr` takes an optional URL, and a thread carrying no links echoes no snapshot,
    /// so the card has no pull request to name or open.
    func testUnlinkWithNothingLinkedNamesNoPullRequest() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .unlink,
                input: "{}",
                output: #"{"status":"not_linked","thread_id":"conv-1","thread_name":"Add caching","message":"Nothing changed."}"#,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .unchanged)
        XCTAssertNil(content.identifier)

        let entry = entry(content, action: .unlink)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "No pull request was linked to the thread")
        XCTAssertNil(entry.openablePullRequest)
    }

    func testNamedPullRequestThatWasNotLinkedSaysSo() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .unlink,
                input: Self.linkInput,
                output: Self.output(status: "not_linked"),
                isError: false
            )
        )
        XCTAssertEqual(
            HostToolWidgetSummary.text(for: entry(content, action: .unlink)),
            "PR was not linked to thread: octo/alpha#7"
        )
    }

    /// A refusal has no snapshot, so the reason takes the detail line the title would have.
    func testFailedLinkReportsTheReasonAndCannotBeOpened() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .link,
                input: Self.linkInput,
                output: "GitHub could not be reached.",
                isError: true
            )
        )
        XCTAssertEqual(content.status, .failed)

        let entry = HostToolWidgetEntry(
            id: "tool-1",
            toolName: ThreadHostToolCatalog.linkPullRequestToolName,
            content: .pullRequestLink(content),
            isComplete: true,
            isError: true
        )
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "Could not link the pull request")
        XCTAssertEqual(HostToolWidgetSummary.detail(for: entry), "GitHub could not be reached.")
        XCTAssertNil(entry.openablePullRequest)
    }

    /// Codex surfaces the plain-text fallback rather than structured content, so the request's
    /// own URL is the only source for the pull request the card names.
    func testPlainTextResultStillReadsAsApplied() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .link,
                input: Self.linkInput,
                output: "Linked octo/alpha#7 to the thread \"Add caching\" in Alveary.",
                isError: false
            )
        )
        XCTAssertEqual(content.status, .applied)
        XCTAssertEqual(content.identifier, Self.pullRequest)
        XCTAssertEqual(content.message, "Linked octo/alpha#7 to the thread \"Add caching\" in Alveary.")
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry(content)), "PR linked to thread: octo/alpha#7")
    }

    /// `unlink_pr` resolves an omitted URL against the thread, so with a text-fallback provider
    /// the host's own message is the only thing naming the pull request it removed. Without it
    /// the card cannot say which one, and cannot open it.
    func testPlainTextUnlinkNamesThePullRequestFromItsMessage() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .unlink,
                input: "{}",
                output: """
                Removed octo/alpha#7 from the thread "Add caching" in Alveary. \
                The pull request itself was not closed, merged, or deleted.
                """,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .applied)
        XCTAssertEqual(content.identifier, Self.pullRequest)

        let entry = entry(content, action: .unlink)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "PR unlinked from thread: octo/alpha#7")
        XCTAssertEqual(entry.openablePullRequest, Self.pullRequest)
    }

    /// A structured receipt with no `pull_request` means there is genuinely nothing to name.
    /// The message fallback is for text-fallback providers only — parsing a receipt's message
    /// would let a pull-request-shaped thread name invent one.
    func testStructuredReceiptWithoutASnapshotNeverParsesItsMessage() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .unlink,
                input: "{}",
                output: #"{"status":"not_linked","thread_id":"conv-1","thread_name":"Fix octo/alpha#7","message":"#
                    + #""The thread \"Fix octo/alpha#7\" has no linked pull requests. Nothing changed."}"#,
                isError: false
            )
        )
        XCTAssertNil(content.identifier)
        XCTAssertEqual(
            HostToolWidgetSummary.text(for: entry(content, action: .unlink)),
            "No pull request was linked to the thread"
        )
    }

    /// "No pull request was linked" belongs to the thread that carried none — an applied call
    /// that simply never named one must not borrow it.
    func testAppliedCallWithNothingToNameKeepsItsOwnCopy() throws {
        let content = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .unlink,
                input: "{}",
                output: "Removed the pull request from this thread.",
                isError: false
            )
        )
        XCTAssertNil(content.identifier)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry(content, action: .unlink)), "PR unlinked from thread")
    }

    func testUnreadableRequestFallsBackToTheGenericToolRow() {
        XCTAssertNil(
            PullRequestLinkWidgetParsing.content(action: .link, input: "not json", output: nil, isError: false)
        )
        XCTAssertNil(
            PullRequestLinkWidgetParsing.content(action: .link, input: nil, output: nil, isError: false)
        )
    }

    private func entry(
        _ content: PullRequestLinkWidgetContent,
        action: PullRequestLinkWidgetContent.Action = .link
    ) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-1",
            toolName: action == .link
                ? ThreadHostToolCatalog.linkPullRequestToolName
                : ThreadHostToolCatalog.unlinkPullRequestToolName,
            content: .pullRequestLink(content),
            isComplete: content.status != .running
        )
    }

    static let pullRequest = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    static let linkInput = #"{"url":"https://github.com/octo/alpha/pull/7"}"#

    static var linkedOutput: String {
        output(status: "linked")
    }

    static func output(status: String) -> String {
        """
        {"status":"\(status)","thread_id":"conv-1","thread_name":"Add caching","message":"Nothing changed.",\
        "pull_request":{"repository":"octo/alpha","number":7,"title":"Add caching","status":"open",\
        "url":"https://github.com/octo/alpha/pull/7"}}
        """
    }
}
