import Foundation
import XCTest

@testable import Alveary

final class PullRequestReviewPromptBuilderTests: XCTestCase {
    private let identifier = PullRequestIdentifier(owner: "octo", repo: "alveary", number: 42)
    // swiftlint:disable:next force_unwrapping
    private let url = URL(string: "https://github.com/octo/alveary/pull/42")!

    func testBuildJoinsTrimmedHalvesWithABlankLine() {
        let prompt = PullRequestReviewPromptBuilder.build(
            editablePrompt: "  Review it.  \n",
            context: "\n## Pull request\n- Pull request: `octo/alveary#42`"
        )

        XCTAssertEqual(prompt, "Review it.\n\n## Pull request\n- Pull request: `octo/alveary#42`")
    }

    func testBuildDropsAnEmptyHalfRatherThanLeavingBlankLines() {
        XCTAssertEqual(PullRequestReviewPromptBuilder.build(editablePrompt: "   ", context: "Context"), "Context")
        XCTAssertEqual(PullRequestReviewPromptBuilder.build(editablePrompt: "Prompt", context: "  "), "Prompt")
    }

    func testContextNamesTheTargetSoARewrittenPromptCannotLoseIt() {
        let context = PullRequestReviewPromptBuilder.context(url: url, identifier: identifier, title: "Add review")

        XCTAssertTrue(context.contains("`octo/alveary#42`"))
        XCTAssertTrue(context.contains("Add review"))
        XCTAssertTrue(context.contains("https://github.com/octo/alveary/pull/42"))
    }

    func testContextOmitsAnUnknownOrBlankTitleRow() {
        let missing = PullRequestReviewPromptBuilder.context(url: url, identifier: identifier, title: nil)
        let blank = PullRequestReviewPromptBuilder.context(url: url, identifier: identifier, title: "   ")

        XCTAssertFalse(missing.contains("Title:"))
        XCTAssertFalse(blank.contains("Title:"))
        // The identifier and URL still anchor the review.
        XCTAssertTrue(missing.contains("`octo/alveary#42`"))
    }

    func testSingleAgentInstructionsScopeSavedTextBelowTheFixedWorkflow() {
        var settings = AppSettings()
        settings.pullRequestReviewPrompt = "Use my exact custom criteria."

        let prompt = PullRequestReviewPromptBuilder.reviewInstructions(
            settings: settings,
            url: url,
            identifier: identifier,
            title: nil
        )

        let workflowRange = prompt.range(of: "## Review workflow")
        let criteriaRange = prompt.range(of: "## Saved review criteria")
        XCTAssertNotNil(workflowRange)
        XCTAssertNotNil(criteriaRange)
        XCTAssertLessThan(workflowRange?.lowerBound ?? prompt.endIndex, criteriaRange?.lowerBound ?? prompt.startIndex)
        XCTAssertTrue(prompt.contains("Use my exact custom criteria."))
        XCTAssertTrue(prompt.contains("exactly one `propose_pr_review` call"))
        XCTAssertTrue(prompt.contains("Follow every `next_cursor` with `cursor`, including while the diff is preparing"))
    }

    func testSingleAgentInstructionsRetainVerdictAndSummaryPolicy() {
        let prompt = PullRequestReviewPromptBuilder.reviewInstructions(
            settings: AppSettings(),
            url: url,
            identifier: identifier,
            title: nil
        )

        XCTAssertTrue(prompt.contains("propose `comment` when there is feedback to stage"))
        XCTAssertTrue(prompt.contains("propose `request_changes` when P0 or P1 findings remain"))
        XCTAssertTrue(prompt.contains("`approve` when nothing blocking remains"))
        XCTAssertTrue(prompt.contains("a single sentence naming the finding itself"))
        XCTAssertTrue(prompt.contains("do not publish it or wait for an outcome"))
    }

    func testTeamCriteriaPreserveCustomTextUnderTheReadOnlyContract() {
        var settings = AppSettings()
        settings.pullRequestReviewPrompt = "Use my exact custom criteria."

        let prompt = PullRequestReviewPromptBuilder.teamCriteria(settings: settings)

        XCTAssertTrue(prompt.contains("Use my exact custom criteria."))
        XCTAssertTrue(prompt.contains("Do not call host tools"))
        XCTAssertTrue(prompt.contains("## Saved review criteria"))
        XCTAssertFalse(prompt.contains("## Pull request"))
    }

    func testSingleAgentWrapperNamesEveryToolItsWorkflowDependsOn() {
        let prompt = PullRequestReviewPromptBuilder.reviewInstructions(
            settings: AppSettings(),
            url: url,
            identifier: identifier,
            title: nil
        )

        for tool in Self.workflowToolNames {
            XCTAssertTrue(prompt.contains(tool), "The fixed review wrapper no longer mentions \(tool)")
        }
    }

    func testDefaultReviewCriteriaContainNoHostWorkflowDirections() {
        let criteria = AppSettings.defaultPullRequestReviewPrompt

        for tool in Self.workflowToolNames {
            XCTAssertFalse(criteria.contains(tool), "Review criteria unexpectedly direct the workflow through \(tool)")
        }
        XCTAssertTrue(criteria.contains("Check correctness, security, performance, readability, and maintainability."))
        XCTAssertTrue(criteria.contains("**[P1]**"))
    }

    /// The fixed wrapper names its tools in prose rather than resolving them from the catalog, so a
    /// rename would leave it pointing at tools that no longer exist and the review would fall
    /// back to whatever the agent improvises.
    func testEveryToolTheDefaultPromptNamesIsInTheHostCatalog() {
        let exposed = Set(AlvearyHostToolCatalog.tools.map(\.name))

        for tool in Self.workflowToolNames {
            XCTAssertTrue(exposed.contains(tool), "\(tool) is named by the review prompt but is not an alveary_host tool")
        }
    }

    private static let workflowToolNames = [
        PullRequestHostToolCatalog.detailToolName,
        PullRequestHostToolCatalog.timelineToolName,
        PullRequestHostToolCatalog.diffToolName,
        PullRequestHostToolCatalog.reviewProposalToolName,
        PullRequestHostToolCatalog.proposeReviewToolName
    ]
}
