@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptRowFactoryTests: XCTestCase {
    func testBuildsRowsForCoreItemFamiliesAndReusesViews() {
        let factory = AppKitTranscriptRowFactory()
        let items: [ChatItem] = [
            .userMessage(id: "user", text: "Hello"),
            .assistantMessage(id: "assistant", text: "Hi"),
            .toolGroup(id: "tools", tools: [tool(id: "tool-1")]),
            .standaloneTool(id: "standalone", tool: tool(id: "tool-2")),
            .subAgentBlock(id: "agents", agents: [agent(id: "agent-1")]),
            .taskListBlock(id: "tasks", tasks: [task(id: "task-1")]),
            .centeredNote(id: "note", kind: .enteredPlanMode),
            .error(id: "error", message: "Failed")
        ]

        let firstRows = factory.makeRows(for: items, configuration: .init())
        let secondRows = factory.makeRows(for: items, configuration: .init())

        XCTAssertEqual(firstRows.map(\.id), ["user", "assistant", "tools", "standalone", "agents", "tasks", "note", "error"])
        XCTAssertTrue(firstRows[0].view is AppKitTranscriptTextBubbleRowView)
        XCTAssertTrue(firstRows[2].view is AppKitTranscriptToolGroupView)
        XCTAssertTrue(firstRows[3].view is AppKitTranscriptInlineToolRowView)
        XCTAssertTrue(firstRows[4].view is AppKitTranscriptSubAgentBlockView)
        XCTAssertTrue(firstRows[5].view is AppKitTranscriptTaskListBlockView)
        XCTAssertTrue(firstRows[6].view is AppKitTranscriptCenteredNoteView)
        XCTAssertTrue(firstRows[7].view is AppKitTranscriptErrorBannerView)
        XCTAssertTrue(firstRows[0].view === secondRows[0].view)
    }

    func testApprovalWithPlanEmitsSeparatePlanAndApprovalRows() {
        let factory = AppKitTranscriptRowFactory()
        let approval = ToolApprovalRequest(
            sessionId: "session",
            toolUseId: "approval",
            toolName: "ExitPlanMode",
            toolInput: #"{"plan":"Ship it"}"#
        )

        let rows = factory.makeRows(
            for: [.toolApproval(id: "approval-item", approval: approval, status: nil)],
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), ["approval-item-plan", "approval-item-approval"])
        XCTAssertTrue(rows[0].view is AppKitTranscriptTextBubbleRowView)
        XCTAssertTrue(rows[1].view is AppKitTranscriptToolApprovalBlockView)
    }

    func testApprovalControlSuppressionKeepsPlanMarkdownRow() {
        let factory = AppKitTranscriptRowFactory()
        let approval = ToolApprovalRequest(
            sessionId: "session",
            toolUseId: "approval",
            toolName: "ExitPlanMode",
            toolInput: #"{"plan":"Ship it"}"#
        )
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.suppressesApprovalControls = { $0.toolName == "ExitPlanMode" }

        let rows = factory.makeRows(
            for: [.toolApproval(id: "approval-item", approval: approval, status: nil)],
            configuration: configuration
        )

        XCTAssertEqual(rows.map(\.id), ["approval-item-plan"])
        XCTAssertTrue(rows[0].view is AppKitTranscriptTextBubbleRowView)
    }

    func testApprovalRowsUseConfiguredSelectedApprovalSelection() throws {
        let factory = AppKitTranscriptRowFactory()
        let approval = ToolApprovalRequest(
            sessionId: "session",
            toolUseId: "approval",
            toolName: "Bash",
            toolInput: #"{"command":"git status --short"}"#
        )

        let rows = factory.makeRows(
            for: [.toolApproval(id: "approval-item", approval: approval, status: nil)],
            configuration: .init(selectedApprovalSelection: {
                XCTAssertEqual($0.sessionId, "session")
                return .sessionGroup
            })
        )
        let approvalBlock = try XCTUnwrap(rows.first?.view as? AppKitTranscriptToolApprovalBlockView)
        approvalBlock.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        approvalBlock.layoutSubtreeIfNeeded()

        XCTAssertNotNil(approvalBlock.descendants(of: NSSegmentedControl.self).first { $0.label(forSegment: 0) == "Approve similar" })
    }

    func testPromptBusyStateIsPromptSpecific() {
        let factory = AppKitTranscriptRowFactory()
        let prompt = PromptEntry(id: "prompt", questions: [], submittedSummary: nil)
        var checkedPromptID: String?

        let rows = factory.makeRows(
            for: [.promptBlock(id: "prompt-row", prompt: prompt)],
            configuration: .init(isPromptBusy: { prompt in
                checkedPromptID = prompt.id
                return true
            })
        )

        XCTAssertEqual(checkedPromptID, "prompt")
        XCTAssertTrue(rows[0].view is AppKitTranscriptPromptBlockView)
    }

    func testTransientRowsAppendAfterChatItems() {
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(
            for: [.assistantMessage(id: "assistant", text: "Hi")],
            transientRows: .init(isTurnActive: true),
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), ["assistant", AppKitTranscriptTransientRows.thinkingRowID])
        XCTAssertTrue(rows[1].view is AppKitTranscriptThinkingIndicatorView)
    }

    func testAwaitingExitPlanModeFollowUpAppendsThinkingTransientRow() {
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(
            for: [.centeredNote(id: "staying", kind: .stayingInPlanMode)],
            transientRows: .init(isAwaitingExitPlanModeFollowUp: true),
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), ["staying", AppKitTranscriptTransientRows.thinkingRowID])
        XCTAssertTrue(rows[1].view is AppKitTranscriptThinkingIndicatorView)
    }

    func testStreamingTransientRowTakesPriorityOverThinking() {
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(isTurnActive: true, streamingText: "Streaming"),
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), [AppKitTranscriptTransientRows.streamingRowID])
        XCTAssertTrue(rows[0].view is AppKitTranscriptStreamingBubbleView)
    }

    func testInterruptedTransientRowUsesCenteredNote() {
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(showsInterruptedNote: true),
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), [AppKitTranscriptTransientRows.interruptedRowID])
        XCTAssertTrue(rows[0].view is AppKitTranscriptCenteredNoteView)
    }

    func testRemovedRowsArePrunedFromViewCache() {
        let factory = AppKitTranscriptRowFactory()
        let initialRows = factory.makeRows(
            for: [
                .assistantMessage(id: "removed", text: "First"),
                .assistantMessage(id: "kept", text: "Second")
            ],
            configuration: .init()
        )
        let removedView = initialRows[0].view
        let keptView = initialRows[1].view

        let prunedRows = factory.makeRows(
            for: [.assistantMessage(id: "kept", text: "Second")],
            configuration: .init()
        )
        let readdedRows = factory.makeRows(
            for: [
                .assistantMessage(id: "removed", text: "First"),
                .assistantMessage(id: "kept", text: "Second")
            ],
            configuration: .init()
        )

        XCTAssertTrue(prunedRows[0].view === keptView)
        XCTAssertFalse(readdedRows[0].view === removedView)
        XCTAssertTrue(readdedRows[1].view === keptView)
    }

    func testHeightInvalidationCallbackIsAttachedToRows() {
        let factory = AppKitTranscriptRowFactory()
        var invalidatedRowIDs: [String] = []
        let rows = factory.makeRows(
            for: [.assistantMessage(id: "assistant", text: "First")],
            configuration: .init(
                onRowHeightInvalidated: { rowID, _ in
                    invalidatedRowIDs.append(rowID)
                }
            )
        )

        let bubble = rows[0].view as? AppKitTranscriptTextBubbleRowView
        bubble?.configure(.init(role: .assistant, markdown: String(repeating: "wrap ", count: 80), bubbleMaxWidth: 120))

        XCTAssertTrue(invalidatedRowIDs.contains("assistant"))
    }

    func testCenteredNoteHeightInvalidationReportsRowID() {
        let factory = AppKitTranscriptRowFactory()
        var invalidatedRowIDs: [String] = []

        _ = factory.makeRows(
            for: [.centeredNote(id: "note", kind: .enteredPlanMode)],
            configuration: .init(onRowHeightInvalidated: { rowID, _ in
                invalidatedRowIDs.append(rowID)
            })
        )

        XCTAssertTrue(invalidatedRowIDs.contains("note"))
    }

    func testStreamingHeightInvalidationRequestsNonAnimatedRelayout() {
        let factory = AppKitTranscriptRowFactory()
        var invalidations: [(rowID: String, animatesLayoutChanges: Bool)] = []

        let rows = factory.makeRows(
            for: [],
            transientRows: .init(isTurnActive: true, streamingText: "Streaming"),
            configuration: .init(onRowHeightInvalidated: { rowID, animatesLayoutChanges in
                invalidations.append((rowID, animatesLayoutChanges))
            })
        )

        let streamingBubble = rows.first?.view as? AppKitTranscriptStreamingBubbleView
        streamingBubble?.configure(
            .init(text: "Streaming " + String(repeating: "content ", count: 40), bubbleMaxWidth: 220)
        )

        XCTAssertTrue(
            invalidations.contains {
                $0.rowID == AppKitTranscriptTransientRows.streamingRowID && !$0.animatesLayoutChanges
            }
        )
    }

    func testRetryableUserMessageWiresRetryCallback() throws {
        let factory = AppKitTranscriptRowFactory()
        var retriedMessageID: String?
        let rows = factory.makeRows(
            for: [.userMessage(id: "user", text: "Failed")],
            configuration: .init(
                retryableFailedMessageIDs: ["user"],
                onRetryFailedUserMessage: { retriedMessageID = $0 }
            )
        )

        let bubble = try XCTUnwrap(rows[0].view as? AppKitTranscriptTextBubbleRowView)
        bubble.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        bubble.layoutSubtreeIfNeeded()
        let retryButton = try XCTUnwrap(bubble.subviews.compactMap { $0 as? NSButton }.first)

        retryButton.performClick(nil)

        XCTAssertEqual(retriedMessageID, "user")
    }

    func testCompletedMarkdownMutationWithEmptyExpandedRowsStaysCollapsedThroughCachedFactoryRow() throws {
        let factory = AppKitTranscriptRowFactory()
        var expansionChanges: [(rowID: String, isExpanded: Bool)] = []
        let configuration = AppKitTranscriptRowFactory.Configuration(
            onRowExpansionChanged: { rowID, isExpanded in
                expansionChanges.append((rowID, isExpanded))
            }
        )
        let runningItem = ChatItem.standaloneTool(
            id: "tool-write",
            tool: markdownWriteTool(id: "write-1", isComplete: false)
        )
        let completedItem = ChatItem.standaloneTool(
            id: "tool-write",
            tool: markdownWriteTool(id: "write-1", isComplete: true)
        )

        let initialRows = factory.makeRows(for: [runningItem], configuration: configuration)
        let row = try XCTUnwrap(initialRows.first?.view as? AppKitTranscriptInlineToolRowView)
        row.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        row.layoutSubtreeIfNeeded()

        let completedRows = factory.makeRows(for: [completedItem], configuration: configuration)
        let completedRow = try XCTUnwrap(completedRows.first?.view as? AppKitTranscriptInlineToolRowView)
        completedRow.layoutSubtreeIfNeeded()

        XCTAssertTrue(completedRow === row)
        XCTAssertTrue(completedRow.descendants(of: AppKitMarkdownView.self).isEmpty)
        XCTAssertTrue(expansionChanges.isEmpty)

        completedRow.setExpanded(true)
        completedRow.layoutSubtreeIfNeeded()

        XCTAssertFalse(completedRow.descendants(of: AppKitMarkdownView.self).isEmpty)
    }

    func testSingleEntryToolGroupKeepsCompletedMarkdownWriteCollapsedUntilUserExpands() throws {
        let factory = AppKitTranscriptRowFactory()
        let rows = factory.makeRows(
            for: [.toolGroup(id: "single-write", tools: [markdownWriteTool(id: "write-1", isComplete: true)])],
            configuration: .init()
        )
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptToolGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.layoutSubtreeIfNeeded()

        XCTAssertTrue(group.descendants(of: AppKitMarkdownView.self).isEmpty)

        let singleToolRow = try XCTUnwrap(group.descendants(of: AppKitTranscriptInlineToolRowView.self).first)
        singleToolRow.setExpanded(true)
        group.layoutSubtreeIfNeeded()

        XCTAssertFalse(group.descendants(of: AppKitMarkdownView.self).isEmpty)
    }

    func testToolGroupExpansionPersistsThroughParentCallback() throws {
        let factory = AppKitTranscriptRowFactory()
        var expansionChanges: [(rowID: String, isExpanded: Bool)] = []
        let rows = factory.makeRows(
            for: [.toolGroup(id: "tools", tools: [tool(id: "read"), tool(id: "grep")])],
            configuration: .init(onRowExpansionChanged: { rowID, isExpanded in
                expansionChanges.append((rowID, isExpanded))
            })
        )
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptToolGroupView)

        group.setExpanded(true)

        XCTAssertEqual(expansionChanges.map(\.rowID), ["tools"])
        XCTAssertEqual(expansionChanges.map(\.isExpanded), [true])
    }

    func testSingleEntryToolGroupExpansionPersistsThroughParentCallback() throws {
        let factory = AppKitTranscriptRowFactory()
        var expansionChanges: [(rowID: String, isExpanded: Bool)] = []
        let rows = factory.makeRows(
            for: [.toolGroup(id: "single-tool", tools: [tool(id: "read")])],
            configuration: .init(onRowExpansionChanged: { rowID, isExpanded in
                expansionChanges.append((rowID, isExpanded))
            })
        )
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptToolGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 400)
        group.layoutSubtreeIfNeeded()
        let singleToolRow = try XCTUnwrap(group.descendants(of: AppKitTranscriptInlineToolRowView.self).first)

        singleToolRow.setExpanded(true)

        XCTAssertEqual(expansionChanges.map(\.rowID), ["single-tool"])
        XCTAssertEqual(expansionChanges.map(\.isExpanded), [true])
    }

    func testSubAgentExpansionPersistsThroughParentCallback() throws {
        let factory = AppKitTranscriptRowFactory()
        var expansionChanges: [(rowID: String, isExpanded: Bool)] = []
        let rows = factory.makeRows(
            for: [.subAgentBlock(id: "agents", agents: [agent(id: "agent")])],
            configuration: .init(onRowExpansionChanged: { rowID, isExpanded in
                expansionChanges.append((rowID, isExpanded))
            })
        )
        let block = try XCTUnwrap(rows.first?.view as? AppKitTranscriptSubAgentBlockView)

        block.setExpanded(true)

        XCTAssertEqual(expansionChanges.map(\.rowID), ["agents"])
        XCTAssertEqual(expansionChanges.map(\.isExpanded), [true])
    }

    func testSubAgentExpansionEchoDoesNotInvalidateCachedRow() throws {
        let factory = AppKitTranscriptRowFactory()
        var invalidatedRowIDs: [String] = []
        let item = ChatItem.subAgentBlock(id: "agents", agents: [agent(id: "agent")])
        let initialRows = factory.makeRows(
            for: [item],
            configuration: .init(onRowHeightInvalidated: { rowID, _ in
                invalidatedRowIDs.append(rowID)
            })
        )
        let block = try XCTUnwrap(initialRows.first?.view as? AppKitTranscriptSubAgentBlockView)
        block.frame = NSRect(x: 0, y: 0, width: 460, height: 400)
        block.layoutSubtreeIfNeeded()

        block.setExpanded(true)
        block.layoutSubtreeIfNeeded()
        invalidatedRowIDs = []

        _ = factory.makeRows(
            for: [item],
            configuration: .init(
                expandedRowIDs: ["agents"],
                onRowHeightInvalidated: { rowID, _ in
                    invalidatedRowIDs.append(rowID)
                }
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidatedRowIDs.isEmpty)
    }

    private func tool(id: String) -> ToolEntry {
        ToolEntry(
            id: id,
            name: "Read",
            summary: "Read file",
            input: "{}",
            output: nil,
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }

    private func markdownWriteTool(id: String, isComplete: Bool) -> ToolEntry {
        ToolEntry(
            id: id,
            name: "Write",
            summary: "Write `let-s-test-plan-mode-peppy-puzzle.md`",
            input: ##"{"file_path":"/tmp/let-s-test-plan-mode-peppy-puzzle.md","content":"# Plan\n\n- Keep tools collapsed."}"##,
            output: isComplete ? "Wrote file" : nil,
            stderr: nil,
            isComplete: isComplete,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }

    private func agent(id: String) -> SubAgentEntry {
        SubAgentEntry(
            id: id,
            agentType: "explorer",
            description: "Inspect code",
            tools: [],
            result: nil,
            isComplete: false,
            toolUseCount: 0
        )
    }

    private func task(id: String) -> TaskEntry {
        TaskEntry(id: id, content: "Review", activeForm: nil, status: .pending)
    }
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
