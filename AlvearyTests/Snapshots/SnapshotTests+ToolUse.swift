import XCTest
import SwiftUI

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testToolGroupMultipleCollapsed() {
        assertMacSnapshot(
            ToolGroupBlock(tools: sampleGroupTools),
            size: CGSize(width: 760, height: 80),
            named: "tool_group_multiple_collapsed"
        )
    }

    func testToolGroupSingleEntry() {
        assertMacSnapshot(
            ToolGroupBlock(tools: [sampleGroupTools[0]]),
            size: CGSize(width: 760, height: 80),
            named: "tool_group_single_entry"
        )
    }

    func testToolGroupAggregateInProgress() {
        assertMacSnapshot(
            ToolGroupBlock(tools: sampleGroupToolsInProgress),
            size: CGSize(width: 760, height: 80),
            named: "tool_group_aggregate_in_progress"
        )
    }

    func testToolGroupAggregateError() {
        assertMacSnapshot(
            ToolGroupBlock(tools: sampleGroupToolsWithError),
            size: CGSize(width: 760, height: 80),
            named: "tool_group_aggregate_error"
        )
    }

    func testToolGroupExpandedIndentsChildren() {
        assertMacSnapshot(
            ToolGroupBlock(tools: sampleGroupTools, initiallyExpanded: true),
            size: CGSize(width: 760, height: 240),
            named: "tool_group_expanded_indents_children"
        )
    }

    func testStandaloneBashErrorCollapsed() {
        assertMacSnapshot(
            StandaloneToolRow(tool: sampleStandaloneBashErrorTool),
            size: CGSize(width: 760, height: 80),
            named: "standalone_bash_error_collapsed"
        )
    }

    func testStandaloneEditRow() {
        assertMacSnapshot(
            StandaloneToolRow(tool: sampleStandaloneEditTool),
            size: CGSize(width: 760, height: 80),
            named: "standalone_edit_row"
        )
    }

    func testStandaloneSkillInvocationRow() {
        assertMacSnapshot(
            StandaloneToolRow(tool: sampleStandaloneSkillTool, initiallyExpanded: true),
            size: CGSize(width: 760, height: 80),
            named: "standalone_skill_invocation_row"
        )
    }

    func testStandaloneBashErrorExpanded() {
        assertMacSnapshot(
            StandaloneToolRow(tool: sampleStandaloneBashErrorTool, initiallyExpanded: true),
            size: CGSize(width: 760, height: 240),
            named: "standalone_bash_error_expanded"
        )
    }

    func testStandaloneMarkdownReadExpandedRendersMarkdown() {
        let description = """
        Apply a signature watermark to portfolio photos in images/portfolio/. Use when the user asks to sign, watermark, \
        or add a signature to portfolio images, or to re-apply or adjust the watermark opacity/font/position.
        """
        let tool = ToolEntry(
            id: "read-markdown",
            name: "Read",
            summary: "Read `SKILL.md`",
            input: "{\"file_path\":\"/tmp/alveary/SKILL.md\"}",
            output: """
            1\t---
            2\tname: watermark-portfolio-images
            3\tdescription: \(description)
            4\t---
            5\t# Watermark Portfolio Images
            6\t
            7\tRun `python3 watermark.py`.
            8\t
            9\t- Keep originals
            10\t- Skip signed files
            11\t
            12\t## Parameters
            13\t
            14\t| Setting | Value |
            15\t|---|---|
            16\t| Font | Gingerink (`GingerinkPersonalUse-rvJd7.ttf`) |
            17\t| Position | Bottom-right: `padding_x = max(12, int(width * 0.02))` |
            """,
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )

        assertMacSnapshot(
            StandaloneToolRow(tool: tool, initiallyExpanded: true),
            size: CGSize(width: 760, height: 420),
            named: "standalone_markdown_read_expanded"
        )
    }

    func testStandaloneExpandedThenCollapsedSpacing() {
        assertMacSnapshot(
            VStack(alignment: .leading, spacing: 6) {
                StandaloneToolRow(tool: sampleStandaloneBashPwdTool, initiallyExpanded: true)
                StandaloneToolRow(tool: sampleStandaloneBashDateTool)
            },
            size: CGSize(width: 520, height: 160),
            named: "standalone_expanded_then_collapsed_spacing"
        )
    }
}
