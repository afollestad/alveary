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
