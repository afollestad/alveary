import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testMarkdownWriteThenEditProducesFullPreview() throws {
        let grouper = ChatItemGrouper()
        let events = try markdownMutationEvents(
            writeContent: "# Plan\n\n- Open index.html",
            edits: [
                editEvent(
                    id: "edit-1",
                    oldString: "- Open index.html",
                    newString: "- Open index.html\n- Add follow-up line"
                )
            ]
        )

        grouper.update(events: events)

        let editTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-1"))
        XCTAssertEqual(editTool.previewOverride?.language, "markdown")
        XCTAssertEqual(
            editTool.previewOverride?.content,
            "# Plan\n\n- Open index.html\n- Add follow-up line"
        )
    }

    func testMarkdownEditPreviewsAccumulateAcrossMultipleEdits() throws {
        let grouper = ChatItemGrouper()
        let events = try markdownMutationEvents(
            writeContent: "# Plan\n\n- First",
            edits: [
                editEvent(id: "edit-1", oldString: "- First", newString: "- First\n- Second"),
                editEvent(id: "edit-2", oldString: "# Plan", newString: "# Updated Plan")
            ]
        )

        grouper.update(events: events)

        let editTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-2"))
        XCTAssertEqual(editTool.previewOverride?.content, "# Updated Plan\n\n- First\n- Second")
    }

    func testMarkdownMultiEditAppliesEditsSequentially() throws {
        let grouper = ChatItemGrouper()
        let events = try markdownMutationEvents(
            writeContent: "# Plan\n\nFirst\nSecond",
            edits: [
                multiEditEvent(
                    id: "multi-edit-1",
                    edits: [
                        ["old_string": "First", "new_string": "## First"],
                        ["old_string": "Second", "new_string": "- Second"]
                    ]
                )
            ]
        )

        grouper.update(events: events)

        let editTool = try XCTUnwrap(standaloneTool(in: grouper, id: "multi-edit-1"))
        XCTAssertEqual(editTool.previewOverride?.content, "# Plan\n\n## First\n- Second")
    }

    func testMarkdownMultiEditInvalidEditDoesNotPartiallyUpdateSnapshot() throws {
        let grouper = ChatItemGrouper()
        let events = try markdownMutationEvents(
            writeContent: "# Plan\n\nFirst\nSecond",
            edits: [
                multiEditEvent(
                    id: "multi-edit-1",
                    edits: [
                        ["old_string": "First", "new_string": "Updated"],
                        ["old_string": "Missing", "new_string": "Skipped"]
                    ]
                ),
                editEvent(id: "edit-1", oldString: "First", newString: "Final")
            ]
        )

        grouper.update(events: events)

        let failedTool = try XCTUnwrap(standaloneTool(in: grouper, id: "multi-edit-1"))
        let successfulTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-1"))
        XCTAssertNil(failedTool.previewOverride)
        XCTAssertEqual(successfulTool.previewOverride?.content, "# Plan\n\nFinal\nSecond")
    }

    func testMarkdownEditReplaceAllPermitsRepeatedMatches() throws {
        let grouper = ChatItemGrouper()
        let events = try markdownMutationEvents(
            writeContent: "# Plan\n\nitem item item",
            edits: [
                editEvent(id: "edit-1", oldString: "item", newString: "done", replaceAll: true)
            ]
        )

        grouper.update(events: events)

        let editTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-1"))
        XCTAssertEqual(editTool.previewOverride?.content, "# Plan\n\ndone done done")
    }

    func testMarkdownEditRepeatedMatchWithoutReplaceAllFallsBackAndKeepsSnapshot() throws {
        let grouper = ChatItemGrouper()
        let events = try markdownMutationEvents(
            writeContent: "# Plan\n\nitem item",
            edits: [
                editEvent(id: "edit-1", oldString: "item", newString: "done"),
                editEvent(id: "edit-2", oldString: "item item", newString: "all done")
            ]
        )

        grouper.update(events: events)

        let failedPreviewTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-1"))
        let successfulPreviewTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-2"))
        XCTAssertNil(failedPreviewTool.previewOverride)
        XCTAssertEqual(successfulPreviewTool.previewOverride?.content, "# Plan\n\nall done")
    }

    func testMarkdownEditAllowsEmptyNewStringDeletion() throws {
        let grouper = ChatItemGrouper()
        let events = try markdownMutationEvents(
            writeContent: "# Plan\n\nRemove this\nKeep this",
            edits: [
                editEvent(id: "edit-1", oldString: "Remove this\n", newString: "")
            ]
        )

        grouper.update(events: events)

        let editTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-1"))
        XCTAssertEqual(editTool.previewOverride?.content, "# Plan\n\nKeep this")
    }

    func testMarkdownEditFailureDoesNotUpdateSnapshot() throws {
        let grouper = ChatItemGrouper()
        let events = try markdownMutationEvents(
            writeContent: "# Plan\n\n- Original",
            edits: [
                editEvent(id: "edit-1", oldString: "- Original", newString: "- Failed", isError: true),
                editEvent(id: "edit-2", oldString: "- Original", newString: "- Successful")
            ]
        )

        grouper.update(events: events)

        let failedTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-1"))
        let successfulTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-2"))
        XCTAssertNil(failedTool.previewOverride)
        XCTAssertEqual(successfulTool.previewOverride?.content, "# Plan\n\n- Successful")
    }

    func testMarkdownEditInterruptionDoesNotUpdateSnapshot() throws {
        let grouper = ChatItemGrouper()
        let events = try markdownMutationEvents(
            writeContent: "# Plan\n\n- Original",
            edits: [
                editEvent(id: "edit-1", oldString: "- Original", newString: "- Interrupted", interrupted: true),
                editEvent(id: "edit-2", oldString: "- Original", newString: "- Successful")
            ]
        )

        grouper.update(events: events)

        let interruptedTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-1"))
        let successfulTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-2"))
        XCTAssertNil(interruptedTool.previewOverride)
        XCTAssertEqual(successfulTool.previewOverride?.content, "# Plan\n\n- Successful")
    }

    func testDeniedMarkdownEditDoesNotUpdateSnapshot() throws {
        let grouper = ChatItemGrouper()
        let writeCall = try toolCall(id: "write-1", name: "Write", input: writeInput(content: "# Plan\n\n- Original"))
        let writeResult = toolResult(id: "write-1")
        let deniedEditCall = try toolCall(
            id: "edit-1",
            name: "Edit",
            input: editInput(oldString: "- Original", newString: "- Denied")
        )
        let deniedApproval = try toolApproval(id: "edit-1", input: editInput(oldString: "- Original", newString: "- Denied"))
        let successfulEditCall = try toolCall(
            id: "edit-2",
            name: "Edit",
            input: editInput(oldString: "- Original", newString: "- Successful")
        )
        let successfulEditResult = toolResult(id: "edit-2")

        grouper.update(events: [
            writeCall,
            writeResult,
            deniedEditCall,
            deniedApproval,
            successfulEditCall,
            successfulEditResult
        ])

        let deniedTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-1"))
        let successfulTool = try XCTUnwrap(standaloneTool(in: grouper, id: "edit-2"))
        XCTAssertNil(deniedTool.previewOverride)
        XCTAssertEqual(successfulTool.previewOverride?.content, "# Plan\n\n- Successful")
    }

    func testInvalidMarkdownMutationInputsFallBackWithoutUpdatingSnapshot() throws {
        let grouper = ChatItemGrouper()
        let fixture = try invalidMarkdownMutationFixture()
        grouper.update(events: fixture.events)

        for id in fixture.failedToolIDs {
            XCTAssertNil(standaloneTool(in: grouper, id: id)?.previewOverride)
        }
        XCTAssertEqual(standaloneTool(in: grouper, id: fixture.successfulToolID)?.previewOverride?.content, "# Plan\n\n- Successful")
    }

    func testMarkdownPreviewReconstructsOnFullRebuild() throws {
        let grouper = ChatItemGrouper()
        let events = try markdownMutationEvents(
            writeContent: "# Plan\n\n- Original",
            edits: [
                editEvent(id: "edit-1", oldString: "- Original", newString: "- Updated")
            ]
        )

        grouper.update(events: events)
        let incrementalPreview = standaloneTool(in: grouper, id: "edit-1")?.previewOverride
        grouper.update(events: events, forceFullRebuild: true)
        let rebuiltPreview = standaloneTool(in: grouper, id: "edit-1")?.previewOverride

        XCTAssertEqual(incrementalPreview, rebuiltPreview)
        XCTAssertEqual(rebuiltPreview?.content, "# Plan\n\n- Updated")
    }

    func testMarkdownSnapshotsSurviveInFlightResetButClearOnFullReset() throws {
        let grouper = ChatItemGrouper()
        let writeCall = try toolCall(id: "write-1", name: "Write", input: writeInput(content: "# Plan\n\n- Original"))
        let writeResult = toolResult(id: "write-1")
        let editCall = try toolCall(
            id: "edit-1",
            name: "Edit",
            input: editInput(oldString: "- Original", newString: "- Updated")
        )
        let editResult = toolResult(id: "edit-1")

        grouper.update(events: [writeCall, writeResult])
        grouper.resetInFlightStateForNewSession()
        grouper.update(events: [writeCall, writeResult, editCall, editResult])

        XCTAssertEqual(standaloneTool(in: grouper, id: "edit-1")?.previewOverride?.content, "# Plan\n\n- Updated")

        grouper.resetAllState()
        grouper.update(events: [editCall, editResult])

        XCTAssertNil(standaloneTool(in: grouper, id: "edit-1")?.previewOverride)
    }
}

private struct MarkdownEditFixture {
    let id: String
    let toolName: String
    let input: String
    let isError: Bool
    let interrupted: Bool
}

private struct InvalidMarkdownMutationFixture {
    let events: [ConversationEventRecord]
    let failedToolIDs: [String]
    let successfulToolID: String
}

private func markdownMutationEvents(writeContent: String, edits: [MarkdownEditFixture]) throws -> [ConversationEventRecord] {
    let writeCall = try toolCall(id: "write-1", name: "Write", input: writeInput(content: writeContent))
    let writeResult = toolResult(id: "write-1")
    let editEvents = edits.flatMap { edit in
        [
            toolCallRecord(id: edit.id, name: edit.toolName, input: edit.input),
            toolResult(id: edit.id, isError: edit.isError, interrupted: edit.interrupted)
        ]
    }
    return [writeCall, writeResult] + editEvents
}

private func invalidMarkdownMutationFixture() throws -> InvalidMarkdownMutationFixture {
    let invalidCalls: [(id: String, call: ConversationEventRecord)] = [
        ("edit-1", toolCallRecord(id: "edit-1", name: "Edit", input: "{")),
        (
            "edit-2",
            try toolCall(
                id: "edit-2",
                name: "Edit",
                input: editInput(filePath: "/tmp/plan.txt", oldString: "- Original", newString: "- Text")
            )
        ),
        (
            "edit-3",
            try toolCall(
                id: "edit-3",
                name: "Edit",
                input: editInput(filePath: "/tmp/other.md", oldString: "- Original", newString: "- Missing")
            )
        ),
        ("edit-4", try toolCall(id: "edit-4", name: "Edit", input: editInput(oldString: "- Missing", newString: "- Unmatched"))),
        (
            "edit-5",
            try toolCall(
                id: "edit-5",
                name: "Edit",
                input: jsonString(["old_string": "- Original", "new_string": "- Missing path"])
            )
        ),
        ("edit-6", try toolCall(id: "edit-6", name: "Edit", input: editInput(oldString: "", newString: "- Empty old string")))
    ]
    let successfulCall = try toolCall(id: "edit-7", name: "Edit", input: editInput(oldString: "- Original", newString: "- Successful"))
    let writeCall = try toolCall(id: "write-1", name: "Write", input: writeInput(content: "# Plan\n\n- Original"))
    let invalidEvents = invalidCalls.flatMap { [$0.call, toolResult(id: $0.id)] }
    let events = [writeCall, toolResult(id: "write-1")] + invalidEvents + [successfulCall, toolResult(id: "edit-7")]
    return InvalidMarkdownMutationFixture(events: events, failedToolIDs: invalidCalls.map(\.id), successfulToolID: "edit-7")
}

private func editEvent(
    id: String,
    filePath: String = "/tmp/plan.md",
    oldString: String,
    newString: String,
    replaceAll: Bool = false,
    isError: Bool = false,
    interrupted: Bool = false
) throws -> MarkdownEditFixture {
    try MarkdownEditFixture(
        id: id,
        toolName: "Edit",
        input: editInput(filePath: filePath, oldString: oldString, newString: newString, replaceAll: replaceAll),
        isError: isError,
        interrupted: interrupted
    )
}

private func multiEditEvent(id: String, edits: [[String: Any]]) throws -> MarkdownEditFixture {
    try MarkdownEditFixture(
        id: id,
        toolName: "MultiEdit",
        input: jsonString(["file_path": "/tmp/plan.md", "edits": edits]),
        isError: false,
        interrupted: false
    )
}

private func writeInput(filePath: String = "/tmp/plan.md", content: String) throws -> String {
    try jsonString(["file_path": filePath, "content": content])
}

private func editInput(
    filePath: String = "/tmp/plan.md",
    oldString: String,
    newString: String,
    replaceAll: Bool = false
) throws -> String {
    var json: [String: Any] = [
        "file_path": filePath,
        "old_string": oldString,
        "new_string": newString
    ]
    if replaceAll {
        json["replace_all"] = true
    }
    return try jsonString(json)
}

private func jsonString(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try XCTUnwrap(String(data: data, encoding: .utf8))
}

private func toolCall(
    id: String,
    name: String,
    input: String
) throws -> ConversationEventRecord {
    toolCallRecord(id: id, name: name, input: input)
}

private func toolCallRecord(
    id: String,
    name: String,
    input: String
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "\(id)-call",
        conversationId: "conversation-1",
        type: "tool_call",
        toolId: id,
        toolName: name,
        toolInput: input
    )
}

private func toolResult(
    id: String,
    isError: Bool = false,
    interrupted: Bool = false
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "\(id)-result",
        conversationId: "conversation-1",
        type: "tool_result",
        toolId: id,
        toolOutput: "ok",
        toolOutputInterrupted: interrupted,
        isError: isError
    )
}

private func toolApproval(id: String, input: String) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "\(id)-approval",
        conversationId: "conversation-1",
        type: "tool_approval",
        content: "session-1",
        toolId: id,
        toolName: "Edit",
        toolInput: input,
        toolApprovalStatus: ToolApprovalStatus.denied.rawValue
    )
}

@MainActor
private func standaloneTool(in grouper: ChatItemGrouper, id: String) -> ToolEntry? {
    grouper.items.compactMap { item -> ToolEntry? in
        guard case .standaloneTool(_, let tool) = item,
              tool.id == id else {
            return nil
        }
        return tool
    }.first
}
