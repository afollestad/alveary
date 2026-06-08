import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testClassificationRoutesMCPReadOnlyToGroupable() {
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "Read"), .groupable)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "WebSearch"), .groupable)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "ToolSearch"), .groupable)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "Skill"), .standalone)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "CommandExecution"), .standalone)
        for toolName in ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit"] {
            XCTAssertTrue(ClaudeApprovalDisplayPolicy.canRenderToolApproval(toolName))
            XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: toolName), .standalone)
        }
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "mcp__linear__search_issues"), .groupable)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "mcp__linear__list_projects"), .groupable)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "mcp__linear__create_issue"), .standalone)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "mcp__gdrive__update_file"), .standalone)
    }

    func testToolSearchSummaryFormatsQuery() {
        let stripped = ChatItemGrouper.toolSummary(
            name: "ToolSearch",
            input: "{\"max_results\":1,\"query\":\"select:WebFetch\"}"
        )
        XCTAssertEqual(stripped, "Searching for tool `WebFetch`")

        let multipleTools = ChatItemGrouper.toolSummary(
            name: "ToolSearch",
            input: "{\"max_results\":3,\"query\":\"select:EnterPlanMode,ExitPlanMode, AskUserQuestion\"}"
        )
        XCTAssertEqual(multipleTools, "Searching for tools `EnterPlanMode`, `ExitPlanMode`, and `AskUserQuestion`")

        let twoTools = ChatItemGrouper.toolSummary(
            name: "ToolSearch",
            input: "{\"max_results\":2,\"query\":\"select:EnterPlanMode,ExitPlanMode\"}"
        )
        XCTAssertEqual(twoTools, "Searching for tools `EnterPlanMode` and `ExitPlanMode`")

        let freeform = ChatItemGrouper.toolSummary(
            name: "ToolSearch",
            input: "{\"max_results\":5,\"query\":\"notebook jupyter\"}"
        )
        XCTAssertEqual(freeform, "Searching for tool `notebook jupyter`")
    }

    func testSkillSummaryFormatsInvocation() {
        let summary = ChatItemGrouper.toolSummary(
            name: "Skill",
            input: "{\"skill\":\"ai-rules-generated-watermark-portfolio-images\"}"
        )
        XCTAssertEqual(summary, "Invoking skill `ai-rules-generated-watermark-portfolio-images`")

        let missingSkill = ChatItemGrouper.toolSummary(
            name: "Skill",
            input: "{}"
        )
        XCTAssertEqual(missingSkill, "Invoking skill")

        let invalidSkillInput = ChatItemGrouper.toolSummary(
            name: "Skill",
            input: "{"
        )
        XCTAssertEqual(invalidSkillInput, "Invoking skill")
    }
}
