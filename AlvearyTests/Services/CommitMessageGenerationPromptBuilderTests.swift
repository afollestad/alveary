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
}
