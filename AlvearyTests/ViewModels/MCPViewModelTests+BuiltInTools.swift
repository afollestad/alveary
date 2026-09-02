import XCTest

@testable import Alveary

@MainActor
extension MCPViewModelTests {
    func testBuiltInToolGroupsDefaultToTheHostCatalog() {
        let viewModel = MCPViewModel(mcpService: MCPMockService(servers: [], recommended: [], availableAgents: []))

        XCTAssertEqual(viewModel.builtInToolGroups, BuiltInMCPToolGroup.all)
        XCTAssertEqual(viewModel.builtInToolGroup(id: "threads")?.title, "Threads")
        XCTAssertNil(viewModel.builtInToolGroup(id: "missing"))
    }

    func testSearchKeepsAGroupWhoseTitleMatchesAndNarrowsOthersToMatchingTools() {
        let listThreads = makeBuiltInTool()
        let archiveThread = makeBuiltInTool(
            name: "archive_thread",
            title: "Archive an Alveary thread",
            description: "Archives a thread.",
            isReadOnly: false
        )
        let threads = makeBuiltInToolGroup(tools: [listThreads, archiveThread])
        let scheduling = makeBuiltInToolGroup(
            id: "scheduling",
            title: "Scheduled tasks",
            tools: [
                makeBuiltInTool(
                    name: "propose_scheduled_task",
                    title: "Propose a scheduled task change",
                    description: "Creates, edits, pauses, resumes, deletes, or runs a scheduled task.",
                    isReadOnly: false
                )
            ]
        )
        let viewModel = MCPViewModel(
            mcpService: MCPMockService(servers: [], recommended: [], availableAgents: []),
            builtInToolGroups: [scheduling, threads]
        )

        XCTAssertEqual(viewModel.filteredBuiltInToolGroups, [scheduling, threads])
        // A title match keeps the whole group, tools included.
        viewModel.searchQuery = "THREADS"
        XCTAssertEqual(viewModel.filteredBuiltInToolGroups, [threads])
        // A tool match narrows the group to what matched: by name, title, or description.
        viewModel.searchQuery = "archive_"
        XCTAssertEqual(viewModel.filteredBuiltInToolGroups.map(\.tools), [[archiveThread]])
        viewModel.searchQuery = "propose"
        XCTAssertEqual(viewModel.filteredBuiltInToolGroups.map(\.id), ["scheduling"])
        viewModel.searchQuery = "hosting this conversation"
        XCTAssertEqual(viewModel.filteredBuiltInToolGroups.map(\.tools), [[listThreads]])
        viewModel.searchQuery = "nothing matches"
        XCTAssertTrue(viewModel.filteredBuiltInToolGroups.isEmpty)
        // The pane still lists the whole group while the card is narrowed.
        viewModel.searchQuery = "archive_"
        XCTAssertEqual(viewModel.builtInToolGroup(id: "threads"), threads)
    }

    /// A built-in group's pane has nothing to save, so its session carries no draft and the
    /// shared Save path must not reach the service; only the header's close ends it.
    func testBuiltInToolGroupDetailsOpenADraftlessSessionThatSubmitLeavesAlone() async throws {
        let group = makeBuiltInToolGroup()
        let service = MCPMockService(servers: [], recommended: [], availableAgents: [])
        let viewModel = MCPViewModel(mcpService: service, builtInToolGroups: [group])
        await viewModel.load()
        let loadAllCount = service.loadAllCallCount

        viewModel.requestBuiltInToolGroupDetails(group)

        let target = MCPPaneTarget.builtInToolGroup(group.id)
        XCTAssertEqual(viewModel.activePaneTarget, target)
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-built-in-threads")
        let session = try XCTUnwrap(viewModel.paneSessions[target])
        XCTAssertNil(session.draft)

        await viewModel.submitActivePane()

        // A save runs `load()` again; an untouched count proves the service was never reached.
        XCTAssertEqual(service.loadAllCallCount, loadAllCount)
        XCTAssertEqual(viewModel.activePaneTarget, target)
        XCTAssertEqual(viewModel.paneSessions[target]?.generation, session.generation)
        XCTAssertTrue(viewModel.pendingPaneDismissals.isEmpty)

        viewModel.dismissActivePane()

        XCTAssertNil(viewModel.paneSessions[target])
        XCTAssertNil(viewModel.activePaneTarget)
        XCTAssertEqual(viewModel.paneDismissalGeneration, 1)
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-built-in-threads")
    }

    func testReopeningABuiltInToolGroupKeepsItsSessionAndFocusRestorationIDFollowsTheInvoker() {
        let group = makeBuiltInToolGroup()
        let viewModel = MCPViewModel(
            mcpService: MCPMockService(servers: [], recommended: [], availableAgents: []),
            builtInToolGroups: [group]
        )

        viewModel.requestBuiltInToolGroupDetails(group, focusRestorationID: "custom-invoker")
        XCTAssertEqual(viewModel.paneFocusRestorationID, "custom-invoker")
        let generation = viewModel.paneSessions[.builtInToolGroup(group.id)]?.generation
        viewModel.deactivatePane()
        viewModel.requestBuiltInToolGroupDetails(group)

        XCTAssertEqual(viewModel.paneSessions[.builtInToolGroup(group.id)]?.generation, generation)
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-built-in-threads")
    }
}

func makeBuiltInToolGroup(
    id: String = "threads",
    title: String = "Threads",
    tools: [BuiltInMCPTool] = [makeBuiltInTool()]
) -> BuiltInMCPToolGroup {
    BuiltInMCPToolGroup(id: id, title: title, tools: tools)
}

func makeBuiltInTool(
    name: String = "list_threads",
    title: String = "List Alveary threads",
    description: String = "Lists the user's active threads and marks the one hosting this conversation.",
    isReadOnly: Bool = true
) -> BuiltInMCPTool {
    BuiltInMCPTool(name: name, title: title, description: description, isReadOnly: isReadOnly)
}
