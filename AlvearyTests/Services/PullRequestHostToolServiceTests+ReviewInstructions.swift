import AgentCLIKit
import Foundation
import SwiftData
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
        // Only the title and URL are needed, so the light read proves the pull request exists.
        XCTAssertEqual(fixture.pullRequests.reviewContextCallCount, 1)
        XCTAssertEqual(fixture.pullRequests.detailCallCount, 0)
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

    func testReviewInstructionsRouteTeamModeWithoutStartingWork() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        launch.host.settingsService.update {
            $0.pullRequestReviewMode = .reviewTeam
            $0.pullRequestReviewPrompt = "Focus on concurrency."
        }

        let result = await launch.host.handle(PullRequestHostToolCatalog.reviewInstructionsToolName)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains(PullRequestHostToolCatalog.startReviewToolName), result.text)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertTrue(launch.prompts.prompts.isEmpty)
        XCTAssertTrue(launch.coordinator.runs.isEmpty)
    }

    func testReviewInstructionsKeepSingleAgentWorkInTheCallingConversation() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        launch.host.settingsService.update {
            $0.pullRequestReviewMode = .singleAgent
            $0.pullRequestReviewPrompt = "Focus on concurrency."
        }

        let result = await launch.host.handle(PullRequestHostToolCatalog.reviewInstructionsToolName)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains("Focus on concurrency."), result.text)
        XCTAssertFalse(result.text.contains(PullRequestHostToolCatalog.startReviewToolName), result.text)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertTrue(launch.prompts.prompts.isEmpty)
    }

    func testDedicatedSingleReviewKeepsItsLaunchInstructionsAfterTheSettingChanges() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        launch.host.settingsService.update { $0.pullRequestReviewPrompt = "Original review criteria." }
        let detail = makePullRequestDetail(
            id: try XCTUnwrap(PullRequestHostToolFixture.identifier), url: URL(string: PullRequestHostToolFixture.url)
        )
        launch.host.pullRequests.detailResult = .success(detail)
        let started = await launch.host.handle(
            PullRequestHostToolCatalog.startReviewToolName,
            arguments: ["url": .string("https://github.com/OCTO/Alpha/pull/7")]
        )
        XCTAssertFalse(started.isError, started.text)
        guard case .string(let destinationID)? = try object(started.structuredContent)["thread_id"] else {
            return XCTFail("Review launch returned no destination")
        }
        let destinationContext = launch.host.agentContext(harnessID: .claude, conversationID: destinationID)
        launch.host.settingsService.update {
            $0.pullRequestReviewMode = .reviewTeam
            $0.pullRequestReviewPrompt = "Replacement review criteria."
        }

        let readsBeforeDestination = launch.host.pullRequests.detailCallCount + launch.host.pullRequests.reviewContextCallCount
        let destinationInstructions = await launch.host.handle(
            PullRequestHostToolCatalog.reviewInstructionsToolName, context: destinationContext
        )
        // The launch already fetched this pull request; its saved instructions need no GitHub read.
        XCTAssertEqual(
            launch.host.pullRequests.detailCallCount + launch.host.pullRequests.reviewContextCallCount, readsBeforeDestination
        )
        let sourceInstructions = await launch.host.handle(PullRequestHostToolCatalog.reviewInstructionsToolName)

        XCTAssertFalse(destinationInstructions.isError, destinationInstructions.text)
        XCTAssertTrue(destinationInstructions.text.contains("Original review criteria."))
        XCTAssertFalse(destinationInstructions.text.contains("Replacement review criteria."))
        XCTAssertFalse(destinationInstructions.text.contains(PullRequestHostToolCatalog.startReviewToolName))
        XCTAssertTrue(sourceInstructions.text.contains(PullRequestHostToolCatalog.startReviewToolName))
        XCTAssertTrue(sourceInstructions.text.contains("Replacement review criteria."))

        let otherIdentifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 8)
        launch.host.pullRequests.detailResult = .success(makePullRequestDetail(id: otherIdentifier))
        let otherInstructions = await launch.host.handle(
            PullRequestHostToolCatalog.reviewInstructionsToolName,
            arguments: ["url": .string("https://github.com/octo/alpha/pull/8")], context: destinationContext
        )

        XCTAssertFalse(otherInstructions.isError, otherInstructions.text)
        XCTAssertTrue(otherInstructions.text.contains(PullRequestHostToolCatalog.startReviewToolName))
        XCTAssertTrue(otherInstructions.text.contains("Replacement review criteria."))
        XCTAssertFalse(otherInstructions.text.contains("Original review criteria."))
    }

    /// The fragment is the only thing that tells the model to call this before reviewing; without
    /// it the tool exists but nothing routes to it.
    func testTheFragmentTellsTheModelToCallItBeforeReviewing() {
        let fragment = PullRequestHostToolCatalog.instructionsFragment

        XCTAssertTrue(fragment.contains(PullRequestHostToolCatalog.reviewInstructionsToolName))
        XCTAssertTrue(fragment.contains("asks you to review a pull request"))
    }
}
