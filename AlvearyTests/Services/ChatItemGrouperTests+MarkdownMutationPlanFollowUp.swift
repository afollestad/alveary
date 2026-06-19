import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testExitPlanModePlanSeedsLaterMarkdownEditPreview() throws {
        let grouper = ChatItemGrouper()
        let plan = "# Plan\n\n- Existing"
        let editCall = planFollowUpToolCall(
            id: "edit-1",
            name: "Edit",
            input: try planFollowUpEditInput(oldString: "- Existing", newString: "- Existing\n- Follow-up")
        )

        grouper.update(events: [
            try planFollowUpExitPlanApproval(plan: plan),
            editCall,
            planFollowUpToolResult(id: "edit-1")
        ])

        let editTool = try XCTUnwrap(planFollowUpStandaloneTool(in: grouper, id: "edit-1"))
        XCTAssertEqual(editTool.previewOverride?.content, "# Plan\n\n- Existing\n- Follow-up")
        XCTAssertEqual(editTool.previewOverride?.origin, .exitPlanModeFollowUp)
    }

    func testExitPlanModeFallbackPlanSeedsLaterMarkdownEditPreview() throws {
        let grouper = ChatItemGrouper()
        let plan = "# Plan\n\n- Existing"
        let editCall = planFollowUpToolCall(
            id: "edit-1",
            name: "Edit",
            input: try planFollowUpEditInput(oldString: "- Existing", newString: "- Existing\n- Follow-up")
        )

        grouper.update(events: [
            planFollowUpAssistantMessage(plan),
            planFollowUpToolCall(id: "exit-plan", name: "ExitPlanMode", input: "{}"),
            try planFollowUpExitPlanApproval(plan: nil),
            editCall,
            planFollowUpToolResult(id: "edit-1")
        ])

        let editTool = try XCTUnwrap(planFollowUpStandaloneTool(in: grouper, id: "edit-1"))
        XCTAssertEqual(editTool.previewOverride?.content, "# Plan\n\n- Existing\n- Follow-up")
        XCTAssertEqual(editTool.previewOverride?.origin, .exitPlanModeFollowUp)
    }

    func testExitPlanModePlanMarksExistingMarkdownWriteSnapshotAsFollowUp() throws {
        let grouper = ChatItemGrouper()
        let plan = "# Plan\n\n- Existing"
        let writeCall = planFollowUpToolCall(
            id: "write-1",
            name: "Write",
            input: try planFollowUpWriteInput(content: plan)
        )
        let editCall = planFollowUpToolCall(
            id: "edit-1",
            name: "Edit",
            input: try planFollowUpEditInput(oldString: "- Existing", newString: "- Existing\n- Follow-up")
        )

        grouper.update(events: [
            writeCall,
            planFollowUpToolResult(id: "write-1"),
            try planFollowUpExitPlanApproval(plan: plan),
            editCall,
            planFollowUpToolResult(id: "edit-1")
        ])

        let editTool = try XCTUnwrap(planFollowUpStandaloneTool(in: grouper, id: "edit-1"))
        XCTAssertEqual(editTool.previewOverride?.content, "# Plan\n\n- Existing\n- Follow-up")
        XCTAssertEqual(editTool.previewOverride?.origin, .exitPlanModeFollowUp)
    }

    func testExitPlanModeApprovalSuppressesDuplicatePlanFollowUpPreview() throws {
        let grouper = ChatItemGrouper()
        let plan = "# Plan\n\n- Existing"
        let revisedPlan = "# Plan\n\n- Existing\n- Follow-up"
        let editCall = planFollowUpToolCall(
            id: "edit-1",
            name: "Edit",
            input: try planFollowUpEditInput(oldString: "- Existing", newString: "- Existing\n- Follow-up")
        )

        grouper.update(events: [
            try planFollowUpExitPlanApproval(toolId: "exit-plan-1", plan: plan),
            editCall,
            planFollowUpToolResult(id: "edit-1"),
            try planFollowUpExitPlanApproval(
                id: "approval-2",
                toolId: "exit-plan-2",
                plan: revisedPlan
            )
        ])

        let editTool = try XCTUnwrap(planFollowUpStandaloneTool(in: grouper, id: "edit-1"))
        XCTAssertNil(editTool.previewOverride)
        let approvalPlans = planFollowUpApprovalPlans(in: grouper)
        XCTAssertEqual(approvalPlans, [plan, revisedPlan])
    }

    func testAmbiguousExitPlanModePlanSeedFallsBackToSnippetPreview() throws {
        let grouper = ChatItemGrouper()
        let editCall = planFollowUpToolCall(
            id: "edit-1",
            name: "Edit",
            input: try planFollowUpEditInput(oldString: "- Existing", newString: "- Existing\n- Follow-up")
        )

        grouper.update(events: [
            try planFollowUpExitPlanApproval(id: "approval-1", plan: "# First Plan\n\n- Existing"),
            try planFollowUpExitPlanApproval(id: "approval-2", plan: "# Second Plan\n\n- Existing"),
            editCall,
            planFollowUpToolResult(id: "edit-1")
        ])

        let editTool = try XCTUnwrap(planFollowUpStandaloneTool(in: grouper, id: "edit-1"))
        XCTAssertNil(editTool.previewOverride)
    }
}

private func planFollowUpWriteInput(filePath: String = "/tmp/plan.md", content: String) throws -> String {
    try planFollowUpJSON(["file_path": filePath, "content": content])
}

private func planFollowUpEditInput(
    filePath: String = "/tmp/plan.md",
    oldString: String,
    newString: String
) throws -> String {
    try planFollowUpJSON([
        "file_path": filePath,
        "old_string": oldString,
        "new_string": newString
    ])
}

private func planFollowUpJSON(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try XCTUnwrap(String(data: data, encoding: .utf8))
}

private func planFollowUpAssistantMessage(_ content: String) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "assistant-plan",
        conversationId: "conversation-1",
        type: "message",
        role: "assistant",
        content: content
    )
}

private func planFollowUpToolCall(id: String, name: String, input: String) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "\(id)-call",
        conversationId: "conversation-1",
        type: "tool_call",
        toolId: id,
        toolName: name,
        toolInput: input
    )
}

private func planFollowUpToolResult(id: String) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "\(id)-result",
        conversationId: "conversation-1",
        type: "tool_result",
        toolId: id,
        toolOutput: "ok"
    )
}

private func planFollowUpExitPlanApproval(
    id: String = "approval",
    toolId: String = "exit-plan",
    plan: String?
) throws -> ConversationEventRecord {
    let input: String
    if let plan {
        input = try planFollowUpJSON(["plan": plan])
    } else {
        input = "{}"
    }

    return ConversationEventRecord(
        id: id,
        conversationId: "conversation-1",
        type: "tool_approval",
        content: "session-1",
        toolId: toolId,
        toolName: "ExitPlanMode",
        toolInput: input,
        toolApprovalStatus: ToolApprovalStatus.denied.rawValue
    )
}

@MainActor
private func planFollowUpStandaloneTool(in grouper: ChatItemGrouper, id: String) -> ToolEntry? {
    grouper.items.compactMap { item -> ToolEntry? in
        guard case .standaloneTool(_, let tool) = item,
              tool.id == id else {
            return nil
        }
        return tool
    }.first
}

@MainActor
private func planFollowUpApprovalPlans(in grouper: ChatItemGrouper) -> [String] {
    grouper.items.flatMap { item -> [String] in
        switch item {
        case .toolApproval(_, let approval, _):
            return approval.planMarkdown.map { [$0] } ?? []
        case .toolApprovalBatch(_, let approvals, _):
            return approvals.compactMap(\.planMarkdown)
        default:
            return []
        }
    }
}
