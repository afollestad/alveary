import BlockInputKit
import XCTest

@testable import Alveary

/// Every packaged prompt is edited in `SettingsPromptEditorSheet`, which commits
/// `AppMarkdownDraft.markdown`. A default that does not survive that round trip
/// gains blank lines the first time a user opens it and presses Save — which is
/// what hand-wrapped list continuations do, since an indented follow-on line
/// parses as its own paragraph rather than joining the item above it.
@MainActor
final class PromptDefaultsMarkdownRoundTripTests: XCTestCase {
    func testEveryPackagedPromptSurvivesTheEditorUnchanged() {
        for (name, prompt) in Self.packagedPrompts {
            XCTAssertEqual(
                AppMarkdownDraft(markdown: prompt).markdown,
                prompt,
                "\(name) does not round-trip through the prompt editor"
            )
        }
    }

    /// Opening an untouched default must leave Reset disabled, which is only true
    /// when the seeded document serializes back to the packaged text.
    func testAnUntouchedDefaultLeavesResetDisabled() {
        for (name, prompt) in Self.packagedPrompts {
            let draft = AppMarkdownDraft(markdown: prompt, referenceMarkdown: prompt)
            XCTAssertTrue(draft.matchesReference, "\(name) reports itself edited before any edit")
        }
    }

    /// The source files wrap with `\#` continuations, which is easy to drop when
    /// editing the prose. A real line break inside a paragraph still round-trips,
    /// so only this catches it — it renders as a hard break in the editor and the
    /// transcript card, which is the "weird line breaks" this authoring style fixed.
    func testNoPackagedPromptCarriesAHardWrapInsideABlock() {
        for (name, prompt) in Self.packagedPrompts {
            for block in BlockInputDocument(markdown: prompt).blocks where block.text.contains("\n") {
                XCTFail("\(name) hard-wraps a block: \(block.text.prefix(80))...")
            }
        }
    }

    /// The tool names the workflow depends on are backticked, so markdown cannot
    /// read the underscore pairs in `get_pr_timeline` and `get_pr_diff` as
    /// emphasis and render them as "get*pr*timeline".
    func testTheReviewPromptBackticksEveryToolItNames() {
        let prompt = AppSettings.defaultPullRequestReviewPrompt
        for tool in ["alveary_host", "get_pr", "get_pr_timeline", "get_pr_diff", "propose_pr_review"] {
            XCTAssertTrue(prompt.contains("`\(tool)`"), "\(tool) is not backticked")
        }
    }

    private static var packagedPrompts: [(String, String)] {
        [
            ("defaultPullRequestReviewPrompt", AppSettings.defaultPullRequestReviewPrompt),
            ("defaultPullRequestGenerationPrompt", AppSettings.defaultPullRequestGenerationPrompt),
            ("defaultCommitMessageGenerationPrompt", AppSettings.defaultCommitMessageGenerationPrompt),
            ("defaultSessionHandoffPrompt", AppSettings.defaultSessionHandoffPrompt)
        ]
    }
}
