import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testMarkdownSnapshotPathNormalizesTildePaths() throws {
        let grouper = ChatItemGrouper()
        let writeCall = try pathToolCall(
            id: "write-1",
            name: "Write",
            input: pathWriteInput(filePath: "~/plan.md", content: "# Plan\n\n- Original")
        )
        let editCall = try pathToolCall(
            id: "edit-1",
            name: "Edit",
            input: pathEditInput(filePath: "\(NSHomeDirectory())/plan.md", oldString: "- Original", newString: "- Updated")
        )

        grouper.update(events: [writeCall, pathToolResult(id: "write-1"), editCall, pathToolResult(id: "edit-1")])

        let editTool = try XCTUnwrap(pathStandaloneTool(in: grouper, id: "edit-1"))
        XCTAssertEqual(editTool.previewOverride?.content, "# Plan\n\n- Updated")
        XCTAssertEqual(editTool.previewOverride?.baseURL, URL(fileURLWithPath: NSHomeDirectory()))
    }

    func testMarkdownSnapshotPathKeepsRelativeKeysRelative() throws {
        let grouper = ChatItemGrouper()
        let writeCall = try pathToolCall(
            id: "write-1",
            name: "Write",
            input: pathWriteInput(filePath: "docs/plan.md", content: "# Plan\n\n- Original")
        )
        let relativeEditCall = try pathToolCall(
            id: "edit-1",
            name: "Edit",
            input: pathEditInput(filePath: "docs/plan.md", oldString: "- Original", newString: "- Relative")
        )
        let absoluteEditCall = try pathToolCall(
            id: "edit-2",
            name: "Edit",
            input: pathEditInput(filePath: "/tmp/docs/plan.md", oldString: "- Relative", newString: "- Absolute")
        )
        let finalRelativeEditCall = try pathToolCall(
            id: "edit-3",
            name: "Edit",
            input: pathEditInput(filePath: "docs/plan.md", oldString: "- Relative", newString: "- Final")
        )

        grouper.update(events: [
            writeCall,
            pathToolResult(id: "write-1"),
            relativeEditCall,
            pathToolResult(id: "edit-1"),
            absoluteEditCall,
            pathToolResult(id: "edit-2"),
            finalRelativeEditCall,
            pathToolResult(id: "edit-3")
        ])

        XCTAssertEqual(pathStandaloneTool(in: grouper, id: "edit-1")?.previewOverride?.content, "# Plan\n\n- Relative")
        XCTAssertNil(pathStandaloneTool(in: grouper, id: "edit-2")?.previewOverride)
        XCTAssertEqual(pathStandaloneTool(in: grouper, id: "edit-3")?.previewOverride?.content, "# Plan\n\n- Final")
        XCTAssertNil(pathStandaloneTool(in: grouper, id: "edit-3")?.previewOverride?.baseURL)
    }
}

private func pathWriteInput(filePath: String, content: String) throws -> String {
    try pathJSON(["file_path": filePath, "content": content])
}

private func pathEditInput(filePath: String, oldString: String, newString: String) throws -> String {
    try pathJSON(["file_path": filePath, "old_string": oldString, "new_string": newString])
}

private func pathJSON(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try XCTUnwrap(String(data: data, encoding: .utf8))
}

private func pathToolCall(id: String, name: String, input: String) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "\(id)-call",
        conversationId: "conversation-1",
        type: "tool_call",
        toolId: id,
        toolName: name,
        toolInput: input
    )
}

private func pathToolResult(id: String) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "\(id)-result",
        conversationId: "conversation-1",
        type: "tool_result",
        toolId: id,
        toolOutput: "ok"
    )
}

@MainActor
private func pathStandaloneTool(in grouper: ChatItemGrouper, id: String) -> ToolEntry? {
    grouper.items.compactMap { item -> ToolEntry? in
        guard case .standaloneTool(_, let tool) = item,
              tool.id == id else {
            return nil
        }
        return tool
    }.first
}
