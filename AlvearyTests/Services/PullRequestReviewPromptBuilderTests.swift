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

    /// The workflow is the whole point of the packaged prompt: without it the agent has no
    /// reason to finish by proposing a review the user can confirm.
    func testDefaultPromptNamesEveryToolItsWorkflowDependsOn() {
        let prompt = AppSettings.defaultPullRequestReviewPrompt

        for tool in Self.workflowToolNames {
            XCTAssertTrue(prompt.contains(tool), "The default review prompt no longer mentions \(tool)")
        }
    }

    /// The prompt names its tools as plain text, so a rename would leave it pointing at tools
    /// that no longer exist and the review would fall back to whatever the agent improvises.
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
        PullRequestHostToolCatalog.addReviewCommentsToolName,
        PullRequestHostToolCatalog.proposeReviewToolName
    ]
}
