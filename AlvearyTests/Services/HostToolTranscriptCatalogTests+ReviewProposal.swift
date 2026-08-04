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

    static let reviewInput = """
    {"body":"Looks good to me.","event":"approve","url":"https://github.com/octo/alpha/pull/7"}
    """

    static let reviewOutput = """
    {"event":"approve","message":"Opened a review confirmation.","number":7,"pending_comment_count":2,\
    "proposal_id":"proposal-1","repository":"octo/alpha","status":"pending_confirmation"}
    """
}
