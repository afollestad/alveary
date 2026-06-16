@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptRowFactoryTests {
    func testActivityGroupUsesGenericHeaderAndSpecificExpandedChildren() throws {
        let factory = AppKitTranscriptRowFactory()
        let rows = factory.makeRows(
            for: [
                .toolGroup(
                    id: "tools",
                    tools: [activityTool(id: "read-1", name: "Read", summary: "Reading AGENTS.md", isComplete: true)]
                ),
                .standaloneTool(
                    id: "edit-row",
                    tool: activityTool(id: "edit-1", name: "Edit", summary: "Edit `Sources/Foo.swift`", isComplete: true)
                ),
                .subAgentBlock(id: "agents", agents: [activityAgent(id: "agent-1")])
            ],
            configuration: .init(expandedRowIDs: ["activity-tools"])
        )
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptActivityGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        group.layoutSubtreeIfNeeded()

        XCTAssertEqual(rows.map(\.id), ["activity-tools"])
        XCTAssertTrue(group.renderedText.contains("Reading 1 file, editing 1 file, and exploring 1 sub-agent"))
        XCTAssertTrue(group.renderedText.contains("Read AGENTS.md"))
        XCTAssertTrue(group.renderedText.contains("Edited Sources/Foo.swift"))
        XCTAssertTrue(group.renderedText.contains("Inspect code"))

        let headers = group.descendants(of: AppKitTranscriptToolHeaderRowView.self)
        XCTAssertEqual(headers.count, 4)
        XCTAssertTrue(headers[0].showsLeadingIconForTesting)
        XCTAssertTrue(headers.dropFirst().allSatisfy { !$0.showsLeadingIconForTesting })
    }

    func testPendingPromptParticipatesInActivityGroupSummaryWithoutChildExpansion() throws {
        let factory = AppKitTranscriptRowFactory()
        let prompt = PromptEntry(
            id: "prompt-1",
            questions: [
                activityPromptQuestion("Choose syntax?"),
                activityPromptQuestion("Choose preview location?")
            ],
            submittedSummary: nil
        )
        let items: [ChatItem] = [
            .toolGroup(
                id: "tools",
                tools: [activityTool(id: "read-1", name: "Read", summary: "Reading AGENTS.md", isComplete: true)]
            ),
            .promptBlock(id: "prompt-row", prompt: prompt),
            .standaloneTool(
                id: "edit-row",
                tool: activityTool(id: "edit-1", name: "Edit", summary: "Edit `Sources/Foo.swift`", isComplete: true)
            )
        ]

        let rows = factory.makeRows(for: items, configuration: .init(expandedRowIDs: ["activity-tools"]))
        let expandableRowIDs = AppKitTranscriptActivityGrouping.expandableRowIDs(for: items)
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptActivityGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 620, height: 1_000)
        group.layoutSubtreeIfNeeded()

        XCTAssertEqual(rows.map(\.id), ["activity-tools"])
        XCTAssertTrue(expandableRowIDs.contains("activity-tools"))
        XCTAssertFalse(expandableRowIDs.contains("prompt-row"))
        XCTAssertTrue(group.renderedText.contains("Reading 1 file, asking 2 questions, and editing 1 file"))
        XCTAssertTrue(group.renderedText.contains("Asking 2 questions"))
        XCTAssertFalse(group.renderedText.contains("Choose syntax?"))
    }

    func testPromptWithNoParsedQuestionsStillContributesOneQuestionToActivitySummary() throws {
        let factory = AppKitTranscriptRowFactory()
        let prompt = PromptEntry(id: "prompt-1", questions: [], submittedSummary: nil)
        let items: [ChatItem] = [
            .standaloneTool(id: "read-row", tool: activityTool(id: "read-1", summary: "Read `AGENTS.md`", isComplete: false)),
            .promptBlock(id: "prompt-row", prompt: prompt),
            .promptBlock(
                id: "parsed-prompt-row",
                prompt: PromptEntry(id: "prompt-2", questions: [activityPromptQuestion("Parsed?")], submittedSummary: nil)
            )
        ]

        let rows = factory.makeRows(for: items, configuration: .init(expandedRowIDs: ["activity-read-row"]))
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptActivityGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 620, height: 1_000)
        group.layoutSubtreeIfNeeded()

        XCTAssertEqual(rows.map(\.id), ["activity-read-row"])
        XCTAssertTrue(group.renderedText.contains("Reading 1 file and asking 2 questions"))
        XCTAssertTrue(group.renderedText.contains("Asking 1 question"))
    }

    func testSubmittedPromptUsageRowExpandsToQuestionAnswers() throws {
        let factory = AppKitTranscriptRowFactory()
        let prompt = PromptEntry(
            id: "prompt-1",
            questions: [
                activityPromptQuestion("When images are inserted as text, which Markdown source should the editor insert?"),
                activityPromptQuestion("Where should the horizontal image preview strip live?")
            ],
            submittedSummary: """
            Q: When images are inserted as text, which Markdown source should the editor insert?
            A: Image Syntax (Recommended)

            Q: Where should the horizontal image preview strip live?
            A: Inside Editor (Recommended)
            """
        )

        let rows = factory.makeRows(for: [.promptBlock(id: "prompt-row", prompt: prompt)], configuration: .init(expandedRowIDs: ["prompt-row"]))
        let row = try XCTUnwrap(rows.first?.view as? AppKitTranscriptPromptUsageRowView)
        row.frame = NSRect(x: 0, y: 0, width: 720, height: 1_000)
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(rows.map(\.id), ["prompt-row"])
        XCTAssertEqual(AppKitTranscriptActivityGrouping.expandableRowIDs(for: [.promptBlock(id: "prompt-row", prompt: prompt)]), ["prompt-row"])
        XCTAssertTrue(row.renderedText.contains("Asked 2 questions"))
        XCTAssertTrue(row.renderedText.contains("When images are inserted as text"))
        XCTAssertTrue(row.renderedText.contains("Image Syntax (Recommended)"))
        XCTAssertTrue(row.renderedText.contains("Where should the horizontal image preview strip live?"))
        XCTAssertTrue(row.renderedText.contains("Inside Editor (Recommended)"))
    }

    func testSubmittedPromptChildExpansionPersistsInsideMixedActivityGroup() throws {
        let factory = AppKitTranscriptRowFactory()
        let prompt = PromptEntry(
            id: "prompt-1",
            questions: [activityPromptQuestion("Choose syntax?")],
            submittedSummary: "Q: Choose syntax?\nA: Image Syntax"
        )
        let items: [ChatItem] = [
            .standaloneTool(id: "read-row", tool: activityTool(id: "read-1", summary: "Read `AGENTS.md`")),
            .promptBlock(id: "prompt-row", prompt: prompt)
        ]
        let migrated = AppKitTranscriptActivityGrouping.migratedExpandedRowIDs(["prompt-row"], for: items)

        let rows = factory.makeRows(for: items, configuration: .init(expandedRowIDs: migrated))
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptActivityGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 620, height: 1_000)
        group.layoutSubtreeIfNeeded()

        XCTAssertEqual(migrated, ["activity-read-row", "prompt-row"])
        XCTAssertTrue(group.renderedText.contains("Read 1 file and asked 1 question"))
        XCTAssertTrue(group.renderedText.contains("Asked 1 question"))
        XCTAssertTrue(group.renderedText.contains("Choose syntax?"))
        XCTAssertTrue(group.renderedText.contains("Image Syntax"))
        let promptRow = try XCTUnwrap(group.descendants(of: AppKitTranscriptPromptUsageRowView.self).first)
        let detailsView = try XCTUnwrap(promptRow.descendants(of: AppKitTranscriptPromptUsageDetailsView.self).first)
        let responseRow = try XCTUnwrap(detailsView.subviews.first { !($0 is AppKitTranscriptElbowConnectorView) })
        XCTAssertEqual(promptRow.usesLocalClipAnimationForExpansion, true)
        XCTAssertEqual(detailsView.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(responseRow.frame.minX, transcriptInlineToolRowMetrics(for: TranscriptTypography()).detailLeadingInset, accuracy: 0.5)
    }

    func testPromptReplacementKeepsActivityGroupCacheFresh() throws {
        let factory = AppKitTranscriptRowFactory()
        let firstItems: [ChatItem] = [
            .standaloneTool(id: "read-row", tool: activityTool(id: "read-1", summary: "Read `AGENTS.md`")),
            .promptBlock(
                id: "prompt-row",
                prompt: PromptEntry(id: "prompt-1", questions: [activityPromptQuestion("First?")], submittedSummary: nil)
            )
        ]
        let secondItems: [ChatItem] = [
            .standaloneTool(id: "read-row", tool: activityTool(id: "read-1", summary: "Read `AGENTS.md`")),
            .promptBlock(
                id: "prompt-row",
                prompt: PromptEntry(id: "prompt-2", questions: [activityPromptQuestion("Second?")], submittedSummary: "Q: Second?\nA: B")
            )
        ]

        _ = factory.makeRows(for: firstItems, configuration: .init(expandedRowIDs: ["activity-read-row"]))
        let rows = factory.makeRows(for: secondItems, configuration: .init(expandedRowIDs: ["activity-read-row", "prompt-row"]))
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptActivityGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 620, height: 1_000)
        group.layoutSubtreeIfNeeded()

        XCTAssertEqual(rows.map(\.id), ["activity-read-row"])
        XCTAssertTrue(group.renderedText.contains("Asked 1 question"))
        XCTAssertFalse(group.renderedText.contains("First?"))
        XCTAssertTrue(group.renderedText.contains("Second?"))
        XCTAssertTrue(group.renderedText.contains("B"))
    }

    func testSingleFlattenedToolStaysSpecificAndUngrouped() throws {
        let factory = AppKitTranscriptRowFactory()
        let rows = factory.makeRows(
            for: [
                .standaloneTool(
                    id: "edit-row",
                    tool: activityTool(id: "edit-1", name: "Edit", summary: "Edit `Sources/Foo.swift`", isComplete: true)
                )
            ],
            configuration: .init()
        )
        let row = try XCTUnwrap(rows.first?.view as? AppKitTranscriptInlineToolRowView)
        row.frame = NSRect(x: 0, y: 0, width: 520, height: 300)
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(rows.map(\.id), ["edit-row"])
        XCTAssertTrue(row.renderedText.contains("Edited Sources/Foo.swift"))
        XCTAssertFalse(row.renderedText.contains("Edited 1 file"))
    }

    func testNonToolRowsSplitActivityGroups() {
        let factory = AppKitTranscriptRowFactory()
        let rows = factory.makeRows(
            for: [
                .standaloneTool(id: "read-row", tool: activityTool(id: "read-1")),
                .taskListBlock(id: "tasks", tasks: [TaskEntry(id: "task-1", content: "Review", activeForm: nil, status: .pending)]),
                .standaloneTool(
                    id: "edit-row",
                    tool: activityTool(id: "edit-1", name: "Edit", summary: "Edit `Sources/Foo.swift`", isComplete: true)
                )
            ],
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), ["read-row", "tasks", "edit-row"])
        XCTAssertTrue(rows[0].view is AppKitTranscriptInlineToolRowView)
        XCTAssertTrue(rows[1].view is AppKitTranscriptTaskListBlockView)
        XCTAssertTrue(rows[2].view is AppKitTranscriptInlineToolRowView)
    }

    func testPinnedApprovalBelowActivityRunDoesNotSplitActivityGroup() throws {
        let factory = AppKitTranscriptRowFactory()
        let approval = ToolApprovalRequest(
            sessionId: "session",
            toolUseId: "tool-bash",
            toolName: "Bash",
            toolInput: #"{"command":"date"}"#
        )
        let items: [ChatItem] = [
            .standaloneTool(
                id: "tool-bash",
                tool: activityTool(id: "tool-bash", name: "Bash", summary: "Executing `date`", isComplete: true)
            ),
            .toolGroup(
                id: "tools",
                tools: [activityTool(id: "read-1", name: "Read", summary: "Read `README.md`", isComplete: true)]
            ),
            .toolApproval(id: "approval-tool-bash", approval: approval, status: .approved)
        ]
        let rows = factory.makeRows(
            for: items,
            configuration: .init()
        )
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptActivityGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 620, height: 1_000)
        group.layoutSubtreeIfNeeded()

        guard case .activityGroup(_, let children) = AppKitTranscriptActivityGrouping.visualRows(for: items).first else {
            return XCTFail("Expected adjacent activity items to render as one visual group")
        }
        XCTAssertEqual(children.map(\.id), ["tool-tool-bash", "tool-read-1"])
        XCTAssertEqual(rows.map(\.id), ["activity-tool-bash", "approval-tool-bash-approval"])
        XCTAssertTrue(rows[1].view is AppKitTranscriptToolApprovalBlockView)
    }

    func testActivityGroupIDDoesNotCollideWithRawRowID() {
        let factory = AppKitTranscriptRowFactory()
        let rows = factory.makeRows(
            for: [
                .standaloneTool(id: "read-row", tool: activityTool(id: "read-1")),
                .standaloneTool(
                    id: "edit-row",
                    tool: activityTool(id: "edit-1", name: "Edit", summary: "Edit `Sources/Foo.swift`", isComplete: true)
                ),
                .assistantMessage(id: "activity-read-row", text: "Existing row")
            ],
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), ["activity-2-read-row", "activity-read-row"])
        XCTAssertTrue(rows[0].view is AppKitTranscriptActivityGroupView)
        XCTAssertTrue(rows[1].view is AppKitTranscriptTextBubbleRowView)
    }

    func testExpandedSingleToolMigratesToExpandedActivityGroupWhenSecondToolArrives() throws {
        let factory = AppKitTranscriptRowFactory()
        let rows = factory.makeRows(
            for: [
                .standaloneTool(id: "read-row", tool: activityTool(id: "read-1", summary: "Read `AGENTS.md`", output: "expanded-only")),
                .standaloneTool(
                    id: "edit-row",
                    tool: activityTool(id: "edit-1", name: "Edit", summary: "Edit `Sources/Foo.swift`", isComplete: true)
                )
            ],
            configuration: .init(expandedRowIDs: ["read-row"])
        )
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptActivityGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        group.layoutSubtreeIfNeeded()

        XCTAssertEqual(rows.map(\.id), ["activity-read-row"])
        XCTAssertTrue(group.renderedText.contains("Read 1 file and edited 1 file"))
        XCTAssertTrue(group.renderedText.contains("Read AGENTS.md"))
        XCTAssertTrue(group.renderedText.contains("Edited Sources/Foo.swift"))
        XCTAssertTrue(group.renderedText.contains("expanded-only"))
    }

    func testExpandedRawMultiToolGroupMigratesToExpandedActivityGroup() throws {
        let items: [ChatItem] = [
            .toolGroup(
                id: "tools",
                tools: [
                    activityTool(id: "read-1", summary: "Read `AGENTS.md`"),
                    activityTool(id: "edit-1", name: "Edit", summary: "Edit `Sources/Foo.swift`")
                ]
            )
        ]
        let migratedExpandedRowIDs = AppKitTranscriptActivityGrouping.migratedExpandedRowIDs(["tools"], for: items)
        let factory = AppKitTranscriptRowFactory()
        let rows = factory.makeRows(for: items, configuration: .init(expandedRowIDs: migratedExpandedRowIDs))
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptActivityGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        group.layoutSubtreeIfNeeded()

        XCTAssertEqual(migratedExpandedRowIDs, ["activity-tools"])
        XCTAssertTrue(group.renderedText.contains("Read AGENTS.md"))
        XCTAssertTrue(group.renderedText.contains("Edited Sources/Foo.swift"))
    }

    func testGroupedChildExpansionPrunesWhenChildExpansionIDIsRemoved() throws {
        let factory = AppKitTranscriptRowFactory()
        let items: [ChatItem] = [
            .standaloneTool(id: "read-row", tool: activityTool(id: "read-1", summary: "Read `AGENTS.md`", output: "expanded-only")),
            .standaloneTool(
                id: "edit-row",
                tool: activityTool(id: "edit-1", name: "Edit", summary: "Edit `Sources/Foo.swift`", isComplete: true)
            )
        ]

        _ = factory.makeRows(
            for: items,
            configuration: .init(expandedRowIDs: ["activity-read-row", "read-row"])
        )
        let rows = factory.makeRows(
            for: items,
            configuration: .init(expandedRowIDs: ["activity-read-row"])
        )
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptActivityGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        group.layoutSubtreeIfNeeded()

        XCTAssertTrue(group.renderedText.contains("Read AGENTS.md"))
        XCTAssertFalse(group.renderedText.contains("expanded-only"))
    }
}

private func activityTool(
    id: String,
    name: String = "Read",
    summary: String = "Read file",
    output: String? = nil,
    isComplete: Bool = true
) -> ToolEntry {
    ToolEntry(
        id: id,
        name: name,
        summary: summary,
        input: "{}",
        output: output,
        stderr: nil,
        isComplete: isComplete,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: false
    )
}

private func activityAgent(id: String) -> SubAgentEntry {
    SubAgentEntry(
        id: id,
        agentType: "explorer",
        description: "Inspect code",
        tools: [],
        result: "Found details",
        isComplete: false,
        toolUseCount: 0
    )
}

private func activityPromptQuestion(_ question: String) -> PromptEntry.PromptQuestion {
    PromptEntry.PromptQuestion(
        question: question,
        header: nil,
        options: [PromptEntry.PromptOption(label: "A", description: "First")],
        multiSelect: false
    )
}

private extension NSView {
    var renderedText: String {
        descendants(of: NSTextField.self).map(\.stringValue).joined(separator: "\n") + "\n"
            + descendants(of: AppKitMarkdownTextView.self).map(\.string).joined(separator: "\n")
    }

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
