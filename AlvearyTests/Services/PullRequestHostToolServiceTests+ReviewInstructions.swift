import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// `get_pr_review_instructions` is how a review asked for in an existing thread picks up the
/// user's guidance — and the model calling it is how Alveary learns a review was asked for at
/// all, instead of guessing from the wording of a message.
extension PullRequestHostToolServiceTests {
    func testReviewInstructionsReturnTheUsersOwnGuidance() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.settingsService.update { $0.pullRequestReviewPrompt = "Only comment on the tests." }
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7), status: .open)
        )

        let result = await fixture.handle(
            PullRequestHostToolCatalog.reviewInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/7")]
        )

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains("Only comment on the tests."), result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["repository"], .string("octo/alpha"))
        XCTAssertEqual(content["number"], .number(7))
    }

    /// Both routes fetch their guidance through this tool, and the tool composes it through the
    /// shared builder — so a drift between the two would surface here.
    func testReviewInstructionsComposeThroughTheSharedBuilder() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        let detail = makePullRequestDetail(id: identifier, status: .open)
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(
            PullRequestHostToolCatalog.reviewInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/7")]
        )

        let composed = PullRequestReviewPromptBuilder.reviewInstructions(
            settings: fixture.settingsService.current,
            url: detail.url ?? PullRequestHostToolService.fallbackURL(for: identifier),
            identifier: identifier,
            title: detail.title
        )
        XCTAssertEqual(result.text, composed)
    }

    func testReviewInstructionsCarryThePullRequestContextBlock() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7), status: .open)
        )

        let result = await fixture.handle(
            PullRequestHostToolCatalog.reviewInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/7")]
        )

        // Without the context block a rewritten prompt would leave the agent with no target.
        XCTAssertTrue(result.text.contains("`octo/alpha#7`"), result.text)
    }

    /// A URL naming a pull request that does not exist should fail here rather than halfway
    /// through a review the model has already started narrating.
    func testReviewInstructionsFailWhenThePullRequestCannotBeFetched() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.detailResult = .failure(.requestFailed(statusCode: 404))

        let result = await fixture.handle(
            PullRequestHostToolCatalog.reviewInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/7")]
        )

        XCTAssertTrue(result.isError)
    }

    func testReviewInstructionsRejectAnUnparseableURL() async throws {
        let fixture = try PullRequestHostToolFixture()

        let result = await fixture.handle(
            PullRequestHostToolCatalog.reviewInstructionsToolName,
            arguments: ["url": .string("https://example.com/not-a-pull-request")]
        )

        XCTAssertTrue(result.isError)
    }

    /// The fragment is the only thing that tells the model to call this before reviewing; without
    /// it the tool exists but nothing routes to it.
    func testTheFragmentTellsTheModelToCallItBeforeReviewing() {
        let fragment = PullRequestHostToolCatalog.instructionsFragment

        XCTAssertTrue(fragment.contains(PullRequestHostToolCatalog.reviewInstructionsToolName))
        XCTAssertTrue(fragment.contains("asks you to review a pull request"))
    }
}
