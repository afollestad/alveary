import XCTest

@testable import Alveary

@MainActor
extension HostToolTranscriptCatalogTests {
    func testDescriptorLookupCoversTheReviewProposalToolInBothNameShapes() {
        let hostToolName = PullRequestHostToolCatalog.proposeReviewToolName
        XCTAssertNotNil(HostToolTranscriptCatalog.descriptor(forToolName: hostToolName))
        // Claude qualifies host tool names; Codex reports them bare. Both must match.
        XCTAssertNotNil(
            HostToolTranscriptCatalog.descriptor(
                forToolName: HostToolTranscriptCatalog.toolName(hostToolName)
            )
        )
        // The reads that only report stay ordinary tool rows. `list_involved_prs` is the
        // exception and has its own coverage in the `+PullRequestList` companion.
        for readOnly in [
            PullRequestHostToolCatalog.detailToolName,
            PullRequestHostToolCatalog.timelineToolName,
            PullRequestHostToolCatalog.diffToolName
        ] {
            XCTAssertNil(HostToolTranscriptCatalog.descriptor(forToolName: readOnly), readOnly)
        }
    }

    /// The only pull request tool that decides nothing on its own, so it is the only one that
    /// correlates with a durable outcome marker.
    func testReviewProposalCarriesItsProposalIDAsTheOutcomeKey() {
        let descriptor = HostToolTranscriptCatalog.descriptor(
            forToolName: PullRequestHostToolCatalog.proposeReviewToolName
        )
        XCTAssertEqual(descriptor?.outcomeKey(Self.reviewOutput), "proposal-1")
        XCTAssertNil(descriptor?.outcomeKey(nil))
    }

    func testReviewContentReadsTheRequestBeforeItsResultArrives() throws {
        let content = try XCTUnwrap(
            PullRequestReviewProposalWidgetParsing.content(
                input: Self.reviewInput,
                output: nil,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .running)
        XCTAssertEqual(content.event, .approve)
        XCTAssertEqual(content.identifier?.displayKey, "octo/alpha#7")
        XCTAssertEqual(content.body, "Looks good to me.")
        XCTAssertNil(content.commentCount)
    }

    /// The staged comments ride the request, so the card can count them while the call runs.
    func testStagedCommentsAreCountedFromTheRequestItself() throws {
        let input = """
        {"comments":[{"body":"Guard this.","line":3,"path":"Sources/A.swift"},\
        {"body":"And this.","line":5,"path":"Sources/A.swift"}],\
        "event":"comment","url":"https://github.com/octo/alpha/pull/7"}
        """
        let content = try XCTUnwrap(
            PullRequestReviewProposalWidgetParsing.content(input: input, output: nil, isError: false)
        )
        XCTAssertEqual(content.commentCount, 2)
    }

    func testReviewContentReadsTheReceiptOnceTheCallLands() throws {
        let content = try XCTUnwrap(
            PullRequestReviewProposalWidgetParsing.content(
                input: Self.reviewInput,
                output: Self.reviewOutput,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .pendingConfirmation)
        XCTAssertEqual(content.proposalID, "proposal-1")
        XCTAssertEqual(content.pendingCommentCount, 2)
    }

    /// Codex emits the plain-text fallback rather than structured content. That is still a
    /// proposal awaiting the user, and the transcript resolves it by conversation instead.
    func testAPlainTextResultStillRendersAsPendingConfirmation() throws {
        let content = try XCTUnwrap(
            PullRequestReviewProposalWidgetParsing.content(
                input: Self.reviewInput,
                output: "Opened a review confirmation in Alveary for octo/alpha#7.",
                isError: false
            )
        )
        XCTAssertEqual(content.status, .pendingConfirmation)
        XCTAssertNil(content.proposalID)
        XCTAssertEqual(content.message, "Opened a review confirmation in Alveary for octo/alpha#7.")
    }

    func testARefusedCallRendersAsFailed() throws {
        let content = try XCTUnwrap(
            PullRequestReviewProposalWidgetParsing.content(
                input: Self.reviewInput,
                output: #"{"message":"Requesting changes requires a body.","status":"error"}"#,
                isError: true
            )
        )
        XCTAssertEqual(content.status, .failed)
    }

    /// Without a verdict the card cannot say what confirming would do, so the call keeps the
    /// generic tool row rather than rendering a decision it cannot describe.
    func testAMissingVerdictFallsBackToTheGenericToolRow() {
        XCTAssertNil(
            PullRequestReviewProposalWidgetParsing.content(
                input: #"{"url":"https://github.com/octo/alpha/pull/7"}"#,
                output: nil,
                isError: false
            )
        )
    }

    /// The pending copy is the one phrase that asks, so the pull request belongs inside the
    /// question — appending it would put the shared colon after the question mark.
    func testThePendingSummaryNamesThePullRequestInsideTheQuestion() throws {
        for (event, expected) in [
            ("approve", "Approve octo/alpha#7?"),
            ("request_changes", "Request changes on octo/alpha#7?"),
            ("comment", "Submit review of octo/alpha#7?")
        ] {
            let entry = try Self.reviewEntry(event: event)
            XCTAssertEqual(HostToolWidgetSummary.text(for: entry), expected)
        }
    }

    /// Resolved copy states rather than asks, so it keeps the shared `phrase: name` shape.
    func testResolvedReviewSummariesKeepTheSharedColonShape() throws {
        let confirmed = try Self.reviewEntry(event: "approve").withOutcome(.confirmed, title: "approve")
        XCTAssertEqual(HostToolWidgetSummary.text(for: confirmed), "Pull request approved: octo/alpha#7")

        let rejected = try Self.reviewEntry(event: "approve").withOutcome(.rejected)
        XCTAssertEqual(HostToolWidgetSummary.text(for: rejected), "Review not submitted: octo/alpha#7")
    }

    /// The card draws this substring in bold, so it has to be a range of the summary itself.
    func testTheEmphasizedNameIsThePullRequestTheSummaryAlreadyNames() throws {
        let entry = try Self.reviewEntry(event: "approve")
        let emphasis = try XCTUnwrap(HostToolWidgetSummary.emphasis(for: entry))
        XCTAssertEqual(emphasis, "octo/alpha#7")
        XCTAssertTrue(HostToolWidgetSummary.text(for: entry).contains(emphasis))

        // The link cards name a pull request the same way, so they weight it the same way.
        let linked = try XCTUnwrap(
            PullRequestLinkWidgetParsing.content(
                action: .link,
                input: Self.linkInput,
                output: Self.linkedOutput,
                isError: false
            )
        )
        let linkEntry = HostToolWidgetEntry(
            id: "tool-2",
            toolName: ThreadHostToolCatalog.linkPullRequestToolName,
            content: .pullRequestLink(linked),
            isComplete: true
        )
        let linkEmphasis = try XCTUnwrap(HostToolWidgetSummary.emphasis(for: linkEntry))
        XCTAssertEqual(linkEmphasis, "octo/alpha#7")
        XCTAssertTrue(HostToolWidgetSummary.text(for: linkEntry).contains(linkEmphasis))
    }

    static func reviewEntry(event: String) throws -> HostToolWidgetEntry {
        let content = try XCTUnwrap(
            PullRequestReviewProposalWidgetParsing.content(
                input: #"{"event":"\#(event)","url":"https://github.com/octo/alpha/pull/7"}"#,
                output: reviewOutput,
                isError: false
            )
        )
        return HostToolWidgetEntry(
            id: "tool-1",
            toolName: PullRequestHostToolCatalog.proposeReviewToolName,
            content: .pullRequestReviewProposal(content),
            isComplete: true,
            outcomeKey: content.proposalID
        )
    }

    static let reviewInput = """
    {"body":"Looks good to me.","event":"approve","url":"https://github.com/octo/alpha/pull/7"}
    """

    static let reviewOutput = """
    {"event":"approve","message":"Opened a review confirmation.","number":7,"pending_comment_count":2,\
    "proposal_id":"proposal-1","repository":"octo/alpha","status":"pending_confirmation"}
    """
}
