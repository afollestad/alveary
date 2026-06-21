import XCTest

@testable import Alveary

final class CommitPromptBuilderTests: XCTestCase {
    func testBuildPrefixesUnstagedScopeWhenIncludingUnstagedChanges() {
        let prompt = CommitMessageGenerationPromptBuilder.build(
            editablePrompt: "Editable instructions",
            includeUnstagedChanges: true,
            context: "Diff context"
        )

        XCTAssertTrue(prompt.hasPrefix("You are generating a commit message for **UNSTAGED** changes."))
        XCTAssertTrue(prompt.contains("\n\nEditable instructions\n\n"))
        XCTAssertTrue(prompt.hasSuffix("Diff context"))
    }

    func testBuildPrefixesStagedScopeWhenExcludingUnstagedChanges() {
        let prompt = CommitMessageGenerationPromptBuilder.build(
            editablePrompt: "Editable instructions",
            includeUnstagedChanges: false,
            context: "Diff context"
        )

        XCTAssertTrue(prompt.hasPrefix("You are generating a commit message for **STAGED** changes."))
    }

    func testDefaultEditablePromptIncludesCommitGuidelines() {
        let prompt = AppSettings.defaultCommitMessageGenerationPrompt

        XCTAssertTrue(prompt.contains("Consider any existing project level or global level commit message guidelines."))
        XCTAssertTrue(
            prompt.contains(
                "Wrap file names, class names, function names, variable names, or other code tokens with single ticks (`)."
            )
        )
        XCTAssertTrue(prompt.contains("Co-authored-by: Claude <noreply@anthropic.com>"))
        XCTAssertTrue(prompt.contains("Co-authored-by: Codex <noreply@openai.com>"))
    }
}
