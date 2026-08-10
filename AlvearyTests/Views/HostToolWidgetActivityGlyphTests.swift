import AppKit
import XCTest

@testable import Alveary

/// The one mapping deciding which cards wear GitHub's own octicon instead of the shell's status
/// glyph. It is pure, so every card's rule is checked here rather than through a rendered row.
@MainActor
final class HostToolWidgetActivityGlyphTests: XCTestCase {
    private static let pullRequest = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    /// A lookup that decides nothing has no outcome to report, so the glyph names the pull
    /// requests it is finding for as long as the call has not failed.
    func testTheListCardWearsThePullRequestOcticonUntilItFails() {
        XCTAssertEqual(activityOcticon(listEntry(status: .running, isComplete: false)), .pullRequest16)
        XCTAssertEqual(activityOcticon(listEntry(status: .listed)), .pullRequest16)
        XCTAssertEqual(activityOcticon(listEntry(status: .listedWithoutRows)), .pullRequest16)
    }

    /// A refusal is the one thing the summary cannot carry on its own, so the status glyph takes
    /// the slot back.
    func testAFailedListCardFallsBackToTheStatusGlyph() {
        XCTAssertNil(activityOcticon(listEntry(status: .failed, isError: true)))
        XCTAssertNil(activityOcticon(listEntry(status: .failed)))
    }

    func testTheInstructionsCardWearsTheCodeReviewOcticonUntilItFails() {
        XCTAssertEqual(activityOcticon(instructionsEntry(status: .running, isComplete: false)), .codeReview16)
        XCTAssertEqual(activityOcticon(instructionsEntry(status: .loaded)), .codeReview16)
        XCTAssertNil(activityOcticon(instructionsEntry(status: .failed, isError: true)))
    }

    /// The proposal is the one card whose glyph goes back to the status symbol once it lands:
    /// the verdict the user submitted is what the resolved card has to report.
    func testTheReviewProposalKeepsItsOcticonOnlyWhilePending() {
        XCTAssertEqual(activityOcticon(reviewProposalEntry(status: .pendingConfirmation)), .pullRequest16)
        XCTAssertNil(activityOcticon(reviewProposalEntry(status: .pendingConfirmation, outcome: .confirmed)))
        XCTAssertNil(activityOcticon(reviewProposalEntry(status: .pendingConfirmation, outcome: .rejected)))
        XCTAssertNil(activityOcticon(reviewProposalEntry(status: .failed, isError: true)))
    }

    /// These cards name a change rather than an activity, so their glyph is the outcome itself.
    func testCardsWithoutAnActivityKeepTheStatusGlyph() {
        XCTAssertNil(activityOcticon(linkEntry()))
        XCTAssertNil(activityOcticon(threadActionEntry()))
        XCTAssertNil(activityOcticon(scheduledProposalEntry()))
    }

    private func activityOcticon(_ entry: HostToolWidgetEntry) -> Octicon? {
        AppKitTranscriptHostToolWidgetRowView.activityOcticon(for: entry)
    }

    private func listEntry(
        status: PullRequestListWidgetContent.Status,
        isComplete: Bool = true,
        isError: Bool = false
    ) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-list-prs",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.listToolName),
            content: .pullRequestList(
                PullRequestListWidgetContent(
                    filter: .all,
                    rows: [
                        .init(identifier: Self.pullRequest, title: "Retry transient GitHub failures", status: .open)
                    ],
                    totalCount: 1,
                    hasWarnings: false,
                    message: nil,
                    status: status
                )
            ),
            isComplete: isComplete,
            isError: isError
        )
    }

    private func instructionsEntry(
        status: ReviewInstructionsWidgetContent.Status,
        isComplete: Bool = true,
        isError: Bool = false
    ) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-instructions",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.reviewInstructionsToolName),
            content: .pullRequestReviewInstructions(
                ReviewInstructionsWidgetContent(
                    kind: .review,
                    identifier: Self.pullRequest,
                    instructions: status == .loaded ? "Focus on correctness." : nil,
                    status: status
                )
            ),
            isComplete: isComplete,
            isError: isError
        )
    }

    private func reviewProposalEntry(
        status: PullRequestReviewProposalWidgetContent.Status,
        outcome: HostToolWidgetOutcome? = nil,
        isError: Bool = false
    ) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-propose-review",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName),
            content: .pullRequestReviewProposal(
                PullRequestReviewProposalWidgetContent(
                    event: .approve,
                    identifier: Self.pullRequest,
                    body: "Looks good.",
                    commentCount: 0,
                    pendingCommentCount: nil,
                    proposalID: "proposal-1",
                    message: nil,
                    status: status
                )
            ),
            isComplete: true,
            isError: isError,
            outcomeKey: "proposal-1",
            outcome: outcome
        )
    }

    private func linkEntry() -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-link",
            toolName: ThreadHostToolCatalog.linkPullRequestToolName,
            content: .pullRequestLink(
                PullRequestLinkWidgetContent(
                    action: .link,
                    identifier: Self.pullRequest,
                    title: "Retry transient GitHub failures",
                    message: nil,
                    status: .applied
                )
            ),
            isComplete: true
        )
    }

    private func threadActionEntry() -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-thread",
            toolName: ThreadHostToolCatalog.pinThreadToolName,
            content: .threadAction(
                ThreadActionWidgetContent(
                    action: .pin,
                    threadID: "conv-1",
                    name: "Add caching",
                    projectPath: nil,
                    message: nil,
                    status: .applied
                )
            ),
            isComplete: true
        )
    }

    private func scheduledProposalEntry() -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-schedule",
            toolName: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.proposeToolName),
            content: .scheduledTaskProposal(
                ScheduledTaskProposalWidgetContent(
                    action: .create,
                    proposedTitle: "Nightly sweep",
                    recurrence: nil,
                    timeZoneIdentifier: nil,
                    targetDefinitionID: nil,
                    proposalID: "proposal-2",
                    message: nil,
                    status: .pendingConfirmation
                )
            ),
            isComplete: true,
            outcomeKey: "proposal-2"
        )
    }
}
