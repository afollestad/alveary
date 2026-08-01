import Foundation
import XCTest

@testable import Alveary

final class PullRequestGenerationPromptBuilderTests: XCTestCase {
    func testBuildJoinsPromptAndContext() {
        let prompt = PullRequestGenerationPromptBuilder.build(
            editablePrompt: "  Generate a PR.  ",
            context: "## Branch\n`feature` into `main`"
        )

        XCTAssertEqual(prompt, "Generate a PR.\n\n## Branch\n`feature` into `main`")
    }

    func testContextListsEverySubjectButBoundsDiffs() {
        let bigDiff = String(repeating: "x", count: PullRequestGenerationPromptBuilder.maxTotalDiffCharacters)
        let context = PullRequestGenerationPromptBuilder.context(
            baseBranch: "main",
            headBranch: "feature",
            commitSubjects: ["First", "Second", "Third"],
            commits: [
                PullRequestGenerationCommit(subject: "First", diff: bigDiff),
                PullRequestGenerationCommit(subject: "Second", diff: "+ second diff")
            ]
        )

        XCTAssertTrue(context.contains("- First"))
        XCTAssertTrue(context.contains("- Second"))
        XCTAssertTrue(context.contains("- Third"))
        // The first commit consumed the whole budget, so the second's diff is out.
        XCTAssertFalse(context.contains("+ second diff"))
        XCTAssertTrue(context.contains("## First"))
    }

    func testContextMarksATruncatedDiff() {
        let overBudget = String(
            repeating: "y",
            count: PullRequestGenerationPromptBuilder.maxTotalDiffCharacters + 10
        )
        let context = PullRequestGenerationPromptBuilder.context(
            baseBranch: "main",
            headBranch: "feature",
            commitSubjects: ["Big"],
            commits: [PullRequestGenerationCommit(subject: "Big", diff: overBudget)]
        )

        XCTAssertTrue(context.contains("[diff truncated]"))
    }

    func testParseResponseSplitsTitleAndBody() throws {
        let parsed = try XCTUnwrap(
            PullRequestGenerationPromptBuilder.parseResponse("Add caching\n\nCaches responses.\nMore detail.")
        )

        XCTAssertEqual(parsed.title, "Add caching")
        XCTAssertEqual(parsed.body, "Caches responses.\nMore detail.")
    }

    func testParseResponseStripsAMarkdownHeadingMarker() throws {
        let parsed = try XCTUnwrap(PullRequestGenerationPromptBuilder.parseResponse("## Add caching\n\nBody."))

        XCTAssertEqual(parsed.title, "Add caching")
    }

    func testParseResponseToleratesLeadingBlankLinesAndTitleOnly() throws {
        let parsed = try XCTUnwrap(PullRequestGenerationPromptBuilder.parseResponse("\n\nAdd caching\n"))

        XCTAssertEqual(parsed.title, "Add caching")
        XCTAssertEqual(parsed.body, "")
    }

    func testParseResponseRejectsEmptyText() {
        XCTAssertNil(PullRequestGenerationPromptBuilder.parseResponse("   \n \n"))
        XCTAssertNil(PullRequestGenerationPromptBuilder.parseResponse("###\n\nBody without a title."))
    }
}
