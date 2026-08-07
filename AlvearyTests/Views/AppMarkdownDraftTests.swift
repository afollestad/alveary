import XCTest

@testable import Alveary

/// Every `AppMarkdownEditor` host commits `AppMarkdownDraft.markdown`, so text put
/// into a draft has to come back out unchanged. The commit modal is the sharpest
/// case — its text becomes a real commit message.
@MainActor
final class AppMarkdownDraftTests: XCTestCase {
    func testACommitMessageWithABodyAndTrailerRoundTrips() {
        assertRoundTrips("""
        Let a review proposal drop its staged comments before submitting

        The footer's Submit review action posted every staged comment, so a proposal \
        the user had partly rejected still reached GitHub in full. `submitReview(event:)` \
        now prunes them first.

        Co-authored-by: Claude <noreply@anthropic.com>
        """)
    }

    func testACommitMessageWithABulletedBodyRoundTrips() {
        assertRoundTrips("""
        Swap the prompt editors for BlockInputKit

        - `SettingsPromptEditorSheet` fills its sheet and scrolls internally.
        - `DiffGitCommitModal` grows between four and six visible lines.
          - Three when a branch-name field takes a line above it.

        Co-authored-by: Codex <noreply@openai.com>
        """)
    }

    func testInstructionsWithHeadingsAndNestedListsRoundTrip() {
        assertRoundTrips("""
        Review the diff before every commit.

        ## Workflow

        1. Read the staged changes.
        2. Name what changed and why.

        ## Guidance

        - Wrap code tokens in backticks.
          - Paths, symbols, and flags all count.
        - Keep the subject line under 72 characters.
        """)
    }

    func testAnEmptyDraftReportsItselfEmpty() {
        let draft = AppMarkdownDraft(markdown: "")
        XCTAssertTrue(draft.isEffectivelyEmpty)
        XCTAssertEqual(draft.markdown, "")
    }

    func testMatchesReferenceTracksReplacementsAndIsFalseWithoutAReference() {
        let unreferenced = AppMarkdownDraft(markdown: "Anything")
        XCTAssertFalse(unreferenced.matchesReference)

        let draft = AppMarkdownDraft(markdown: "Edited", referenceMarkdown: "Packaged default")
        XCTAssertFalse(draft.matchesReference)

        draft.replaceText("Packaged default")
        XCTAssertTrue(draft.matchesReference)

        draft.replaceText("Edited again")
        XCTAssertFalse(draft.matchesReference)
    }

    private func assertRoundTrips(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(AppMarkdownDraft(markdown: markdown).markdown, markdown, file: file, line: line)
    }
}
