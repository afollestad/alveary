import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// `get_pr_address_feedback_instructions` is the review tool's opposite number: it is how a
/// feedback run started in an existing thread picks up the user's guidance, and the model calling
/// it is how Alveary learns feedback is about to be addressed.
extension PullRequestHostToolServiceTests {
    func testAddressFeedbackInstructionsReturnTheUsersOwnGuidance() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.settingsService.update { $0.pullRequestAddressFeedbackPrompt = "Reply before resolving." }
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7), status: .open)
        )

        let result = await fixture.handle(
            PullRequestHostToolCatalog.addressFeedbackInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/7")]
        )

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains("Reply before resolving."), result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["repository"], .string("octo/alpha"))
        XCTAssertEqual(content["number"], .number(7))
    }

    /// The two tools read different settings. Returning the review prompt here would send an
    /// agent that was asked to fix things off to write a review instead.
    func testAddressFeedbackInstructionsDoNotReturnTheReviewPrompt() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.settingsService.update {
            $0.pullRequestReviewPrompt = "REVIEW-ONLY-MARKER"
            $0.pullRequestAddressFeedbackPrompt = "FEEDBACK-ONLY-MARKER"
        }
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7), status: .open)
        )

        let feedback = await fixture.handle(
            PullRequestHostToolCatalog.addressFeedbackInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/7")]
        )
        let review = await fixture.handle(
            PullRequestHostToolCatalog.reviewInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/7")]
        )

        XCTAssertTrue(feedback.text.contains("FEEDBACK-ONLY-MARKER"), feedback.text)
        XCTAssertFalse(feedback.text.contains("REVIEW-ONLY-MARKER"), feedback.text)
        XCTAssertTrue(review.text.contains("REVIEW-ONLY-MARKER"), review.text)
        XCTAssertFalse(review.text.contains("FEEDBACK-ONLY-MARKER"), review.text)
    }

    /// Both routes fetch their guidance through this tool, and the tool composes it through the
    /// shared builder — so a drift between the two would surface here.
    func testAddressFeedbackInstructionsComposeThroughTheSharedBuilder() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        let detail = makePullRequestDetail(id: identifier, status: .open)
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(
            PullRequestHostToolCatalog.addressFeedbackInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/7")]
        )

        let composed = PullRequestReviewPromptBuilder.addressFeedbackInstructions(
            settings: fixture.settingsService.current,
            url: detail.url ?? PullRequestHostToolService.fallbackURL(for: identifier),
            identifier: identifier,
            title: detail.title
        )
        XCTAssertEqual(result.text, composed)
    }

    func testAddressFeedbackInstructionsCarryThePullRequestContextBlock() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7), status: .open)
        )

        let result = await fixture.handle(
            PullRequestHostToolCatalog.addressFeedbackInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/7")]
        )

        XCTAssertTrue(result.text.contains("`octo/alpha#7`"), result.text)
    }

    /// A URL naming a pull request that does not exist should fail here rather than halfway
    /// through a run the model has already started narrating.
    func testAddressFeedbackInstructionsFailWhenThePullRequestCannotBeFetched() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.detailResult = .failure(.requestFailed(statusCode: 404))

        let result = await fixture.handle(
            PullRequestHostToolCatalog.addressFeedbackInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/7")]
        )

        XCTAssertTrue(result.isError)
    }

    /// The fragment is the only thing that routes to this tool, and it also has to keep the two
    /// jobs apart — without that, "address the feedback" reaches the reviewing tool.
    func testTheFragmentRoutesAddressingFeedbackToItsOwnTool() {
        let fragment = PullRequestHostToolCatalog.instructionsFragment

        XCTAssertTrue(fragment.contains(PullRequestHostToolCatalog.addressFeedbackInstructionsToolName))
        XCTAssertTrue(fragment.contains("address, fix, answer, or resolve feedback"))
        XCTAssertTrue(fragment.contains("Reviewing gives new feedback"))
    }

    /// Each description names the other, so a model choosing between them is told which is which
    /// rather than guessing from the names.
    func testTheTwoInstructionToolsNameEachOther() throws {
        let tools = PullRequestHostToolCatalog.tools
        let review = try XCTUnwrap(tools.first { $0.name == PullRequestHostToolCatalog.reviewInstructionsToolName })
        let feedback = try XCTUnwrap(
            tools.first { $0.name == PullRequestHostToolCatalog.addressFeedbackInstructionsToolName }
        )

        XCTAssertTrue(review.description.contains(PullRequestHostToolCatalog.addressFeedbackInstructionsToolName))
        XCTAssertTrue(feedback.description.contains(PullRequestHostToolCatalog.reviewInstructionsToolName))
        // The name reads like a feedback reader, so the description has to disown that outright.
        XCTAssertTrue(feedback.description.contains("This returns instructions, not the feedback"))
        XCTAssertTrue(feedback.description.contains(PullRequestHostToolCatalog.timelineToolName))
    }
}
