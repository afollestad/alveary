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
            let draft = AppMarkdownDraft(markdown: prompt, referenceMarkdown: prompt)
            XCTAssertEqual(draft.markdown, prompt, "\(name) does not round-trip through the prompt editor")
            XCTAssertTrue(draft.matchesReference, "\(name) reports itself edited before any edit")
            // A hard break can round-trip unchanged while still rendering an unwanted line break.
            for block in draft.store.document.blocks where block.text.contains("\n") {
                XCTFail("\(name) hard-wraps a block: \(block.text.prefix(80))...")
            }
        }
    }

    func testTheAddressFeedbackPromptBackticksEveryToolItNames() {
        let prompt = AppSettings.defaultPullRequestAddressFeedbackPrompt
        let tools = ["alveary_host", "get_pr", "get_pr_timeline", "get_pr_diff", "reply_to_pr_thread", "resolve_pr_thread", "comment_on_pr"]
        for tool in tools {
            XCTAssertTrue(prompt.contains("`\(tool)`"), "\(tool) is not backticked")
        }
    }

    private static var packagedPrompts: [(String, String)] {
        [
            ("defaultPullRequestReviewPrompt", AppSettings.defaultPullRequestReviewPrompt),
            ("defaultPullRequestAddressFeedbackPrompt", AppSettings.defaultPullRequestAddressFeedbackPrompt),
            ("defaultPullRequestGenerationPrompt", AppSettings.defaultPullRequestGenerationPrompt),
            ("defaultCommitMessageGenerationPrompt", AppSettings.defaultCommitMessageGenerationPrompt),
            ("defaultSessionHandoffPrompt", AppSettings.defaultSessionHandoffPrompt)
        ]
    }
}
