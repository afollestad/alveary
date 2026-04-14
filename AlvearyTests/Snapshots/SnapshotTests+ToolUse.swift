import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    private var longThinkingText: String {
        "The user is asking what context I have about this conversation and whether there were prior code changes in this thread."
            + "\n"
            + "I should summarize the repo, current branch, and recent actions."
    }

    func testThinkingBlockInlineShortText() {
        assertMacSnapshot(
            ThinkingBlock(text: "The user is asking what context I have about this conversation."),
            size: CGSize(width: 760, height: 120),
            named: "thinking_block_inline_short"
        )
    }

    func testThinkingBlockCollapsed() {
        assertMacSnapshot(
            ThinkingBlock(text: longThinkingText),
            size: CGSize(width: 760, height: 120),
            named: "thinking_block_collapsed"
        )
    }

    func testThinkingBlockExpanded() {
        assertMacSnapshot(
            ThinkingBlock(text: longThinkingText),
            size: CGSize(width: 760, height: 180),
            named: "thinking_block_expanded"
        )
    }

    func testWorkingBlockSingleErrorToolCollapsed() {
        assertMacSnapshot(
            WorkingBlock(tools: sampleErrorTools),
            size: CGSize(width: 760, height: 190),
            named: "working_block_single_error_collapsed"
        )
    }

    func testWorkingBlockExpandedErrorTool() {
        assertMacSnapshot(
            WorkingBlock(
                tools: sampleErrorTools,
                initiallyExpanded: true
            ),
            size: CGSize(width: 760, height: 260),
            named: "working_block_expanded_error"
        )
    }
}
