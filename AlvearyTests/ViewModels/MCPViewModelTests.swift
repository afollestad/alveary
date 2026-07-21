import XCTest

@testable import Alveary

@MainActor
final class MCPViewModelTests: XCTestCase {
    func testPaneFocusRestorationIDUsesInvokingControlAndSurvivesDismissal() async {
        let recommended = RecommendedMCPServer(
            template: MCPServer(
                name: "playwright",
                transport: .stdio,
                command: "npx",
                args: nil,
                url: nil,
                headers: nil,
                env: nil,
                providers: []
            ),
            description: "Browser automation",
            headerPrompts: []
        )
        let viewModel = MCPViewModel(
            mcpService: MCPMockService(servers: [], recommended: [recommended], availableAgents: [])
        )
        await viewModel.load()

        viewModel.requestAddCustom(focusRestorationID: "mcp-add-empty")
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-add-empty")
        viewModel.dismissActivePane()
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-add-empty")

        viewModel.requestAddRecommended(recommended)
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-recommended-playwright")
        viewModel.dismissActivePane()
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-recommended-playwright")

        viewModel.requestAddCustom()
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-add")
        viewModel.dismissActivePane()
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-add")
    }

    func testLoadPopulatesStateAndSearchFiltersLocally() async {
        let service = MCPMockService(
            servers: [
                MCPServer(
                    name: "context7",
                    transport: .http,
                    command: nil,
                    args: nil,
                    url: "https://mcp.context7.com/mcp",
                    headers: nil,
                    env: nil,
                    providers: ["claude"]
                )
            ],
            recommended: [
                RecommendedMCPServer(
                    template: MCPServer(
                        name: "playwright",
                        transport: .stdio,
                        command: "npx",
                        args: ["-y", "@anthropic/mcp-playwright"],
                        url: nil,
                        headers: nil,
                        env: nil,
                        providers: []
                    ),
                    description: "Browser automation for testing.",
                    headerPrompts: ["PLAYWRIGHT_TOKEN"]
                )
            ],
            availableAgents: [
                MCPAgentAvailability(agentId: "claude", name: "Claude Code", supportedTransports: [.stdio, .http])
            ]
        )
        let viewModel = MCPViewModel(mcpService: service)

        await viewModel.load()
        let loadAllCount = service.loadAllCallCount
        let loadRecommendedCount = service.loadRecommendedCallCount
        viewModel.searchQuery = "token"

        XCTAssertEqual(viewModel.servers.map(\.name), ["context7"])
        XCTAssertEqual(viewModel.availableAgents.map(\.agentId), ["claude"])
        XCTAssertTrue(viewModel.filteredServers.isEmpty)
        XCTAssertEqual(viewModel.filteredRecommended.map(\.template.name), ["playwright"])
        XCTAssertEqual(service.loadAllCallCount, loadAllCount)
        XCTAssertEqual(service.loadRecommendedCallCount, loadRecommendedCount)
    }

    func testAddServerRefreshesLists() async throws {
        let server = MCPServer(
            name: "context7",
            transport: .http,
            command: nil,
            args: nil,
            url: "https://mcp.context7.com/mcp",
            headers: nil,
            env: nil,
            providers: ["claude"]
        )
        let service = MCPMockService(
            servers: [],
            recommended: [
                RecommendedMCPServer(template: server, description: "Docs", headerPrompts: [])
            ],
            availableAgents: []
        )
        let viewModel = MCPViewModel(mcpService: service)

        try await viewModel.addServer(server, for: ["claude"])

        XCTAssertEqual(viewModel.servers.map(\.name), ["context7"])
        XCTAssertTrue(viewModel.recommended.isEmpty)
    }

    func testRemoveServerRefreshesLists() async throws {
        let server = MCPServer(
            name: "playwright",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@anthropic/mcp-playwright"],
            url: nil,
            headers: nil,
            env: nil,
            providers: ["claude"]
        )
        let service = MCPMockService(
            servers: [server],
            recommended: [],
            availableAgents: []
        )
        let viewModel = MCPViewModel(mcpService: service)

        try await viewModel.removeServer(server)

        XCTAssertTrue(viewModel.servers.isEmpty)
        XCTAssertEqual(viewModel.recommended.map(\.template.name), ["playwright"])
    }

    func testRemoveServerDiscardsMatchingCachedEditSession() async throws {
        let server = MCPServer(
            name: "playwright",
            transport: .stdio,
            command: "npx",
            args: nil,
            url: nil,
            headers: nil,
            env: nil,
            providers: ["claude"]
        )
        let service = MCPMockService(
            servers: [server],
            recommended: [],
            availableAgents: []
        )
        let viewModel = MCPViewModel(mcpService: service)
        viewModel.requestEdit(server)
        let generation = try XCTUnwrap(viewModel.paneSessions[.edit(server.name)]?.generation)

        try await viewModel.removeServer(server)

        let request = PaneSessionDismissalRequest(target: MCPPaneTarget.edit(server.name), generation: generation)
        XCTAssertTrue(viewModel.pendingPaneDismissals.contains(request))
        XCTAssertNotNil(viewModel.paneSessions[.edit(server.name)])
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-add")

        viewModel.deactivatePane(.edit(server.name), generation: generation)
        viewModel.dismissPane(.edit(server.name), generation: generation)
        XCTAssertNil(viewModel.paneSessions[.edit(server.name)])
        XCTAssertNil(viewModel.activePaneTarget)
        XCTAssertFalse(viewModel.pendingPaneDismissals.contains(request))
    }

    func testPaneSessionsRestoreEachTargetDraft() async throws {
        let service = MCPMockService(
            servers: [],
            recommended: [],
            availableAgents: [
                MCPAgentAvailability(agentId: "claude", name: "Claude", supportedTransports: [.stdio])
            ]
        )
        let viewModel = MCPViewModel(mcpService: service)
        await viewModel.load()
        let server = MCPServer(
            name: "existing",
            transport: .stdio,
            command: "npx",
            args: nil,
            url: nil,
            headers: nil,
            env: nil,
            providers: ["claude"]
        )

        viewModel.requestAddCustom()
        var customDraft = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.draft)
        customDraft.name = "unsaved-custom"
        viewModel.updateActiveDraft(customDraft)
        viewModel.requestEdit(server)
        viewModel.requestAddCustom()

        XCTAssertEqual(viewModel.paneSessions[.addCustom]?.draft.name, "unsaved-custom")
        XCTAssertNotNil(viewModel.paneSessions[.edit("existing")])
    }

    func testCachedDraftUsesLiveAgentAvailabilityAfterRefresh() async throws {
        let service = MCPMockService(servers: [], recommended: [], availableAgents: [])
        let viewModel = MCPViewModel(mcpService: service)
        await viewModel.load()
        viewModel.requestAddCustom()
        var draft = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.draft)
        draft.name = "keep-me"
        viewModel.updateActiveDraft(draft)

        service.setAvailableAgents([
            MCPAgentAvailability(agentId: "codex", name: "Codex", supportedTransports: [.stdio, .http])
        ])
        await viewModel.refreshProviders()

        XCTAssertEqual(viewModel.paneSessions[.addCustom]?.draft.name, "keep-me")
        XCTAssertEqual(viewModel.availableAgents.map(\.agentId), ["codex"])
    }

    func testDelayedSubmissionCannotMutateReopenedTargetGeneration() async throws {
        let service = MCPMockService(
            servers: [],
            recommended: [],
            availableAgents: [
                MCPAgentAvailability(agentId: "claude", name: "Claude", supportedTransports: [.stdio])
            ],
            addDelay: .milliseconds(200)
        )
        let viewModel = MCPViewModel(mcpService: service)
        await viewModel.load()
        viewModel.requestAddCustom()
        var originalDraft = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.draft)
        originalDraft.name = "original"
        originalDraft.command = "npx"
        viewModel.updateActiveDraft(originalDraft)

        let submission = Task { await viewModel.submitActivePane() }
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.dismissActivePane()
        viewModel.requestAddCustom()
        var reopenedDraft = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.draft)
        reopenedDraft.name = "reopened"
        viewModel.updateActiveDraft(reopenedDraft)
        let reopenedGeneration = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.generation)

        await submission.value

        XCTAssertEqual(viewModel.activePaneTarget, .addCustom)
        XCTAssertEqual(viewModel.paneSessions[.addCustom]?.generation, reopenedGeneration)
        XCTAssertEqual(viewModel.paneSessions[.addCustom]?.draft.name, "reopened")
        XCTAssertEqual(viewModel.paneDismissalGeneration, 1)
    }

    func testDismissingCapturedTargetDoesNotCloseNewActiveTarget() async throws {
        let recommended = RecommendedMCPServer(
            template: MCPServer(
                name: "playwright",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@anthropic/mcp-playwright"],
                url: nil,
                headers: nil,
                env: nil,
                providers: []
            ),
            description: "Browser automation",
            headerPrompts: []
        )
        let service = MCPMockService(servers: [], recommended: [recommended], availableAgents: [])
        let viewModel = MCPViewModel(mcpService: service)
        await viewModel.load()
        viewModel.requestAddCustom()
        let capturedGeneration = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.generation)
        viewModel.requestAddRecommended(recommended)

        viewModel.dismissPane(.addCustom, generation: capturedGeneration)

        XCTAssertNil(viewModel.paneSessions[.addCustom])
        XCTAssertEqual(viewModel.activePaneTarget, .addRecommended(recommended.id))
        XCTAssertNotNil(viewModel.paneSessions[.addRecommended(recommended.id)])
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testSuccessfulSaveRetainsSessionUntilAnimatedDismissalCompletes() async throws {
        let service = MCPMockService(
            servers: [],
            recommended: [],
            availableAgents: [
                MCPAgentAvailability(agentId: "claude", name: "Claude", supportedTransports: [.stdio])
            ]
        )
        let viewModel = MCPViewModel(mcpService: service)
        await viewModel.load()
        viewModel.requestAddCustom()
        var draft = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.draft)
        draft.name = "saved-server"
        draft.command = "npx"
        viewModel.updateActiveDraft(draft)
        let generation = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.generation)

        await viewModel.submitActivePane()

        let request = PaneSessionDismissalRequest(target: MCPPaneTarget.addCustom, generation: generation)
        XCTAssertTrue(viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(viewModel.activePaneTarget, .addCustom)
        XCTAssertEqual(viewModel.paneSessions[.addCustom]?.generation, generation)

        viewModel.deactivatePane(.addCustom, generation: generation)
        viewModel.dismissPane(.addCustom, generation: generation)
        XCTAssertNil(viewModel.paneSessions[.addCustom])
        XCTAssertFalse(viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(viewModel.paneDismissalGeneration, 1)
    }

    func testDismissalWithoutFocusRestorationDoesNotBumpGenerationWhenNoTargetIsActive() async throws {
        let service = MCPMockService(
            servers: [],
            recommended: [],
            availableAgents: [
                MCPAgentAvailability(agentId: "claude", name: "Claude", supportedTransports: [.stdio])
            ]
        )
        let viewModel = MCPViewModel(mcpService: service)
        await viewModel.load()
        viewModel.requestAddCustom()
        let generation = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.generation)

        viewModel.deactivatePane(.addCustom, generation: generation)
        viewModel.dismissPane(.addCustom, generation: generation, restoreFocus: false)

        XCTAssertNil(viewModel.activePaneTarget)
        XCTAssertNil(viewModel.paneSessions[.addCustom])
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testRequestingPendingSuccessfulSaveStartsFreshDraftWithoutFocusBump() async throws {
        let service = MCPMockService(
            servers: [],
            recommended: [],
            availableAgents: [
                MCPAgentAvailability(agentId: "claude", name: "Claude", supportedTransports: [.stdio])
            ]
        )
        let viewModel = MCPViewModel(mcpService: service)
        await viewModel.load()
        viewModel.requestAddCustom(focusRestorationID: "mcp-add-empty")
        var draft = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.draft)
        draft.name = "saved-server"
        draft.command = "npx"
        viewModel.updateActiveDraft(draft)
        let completedGeneration = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.generation)

        await viewModel.submitActivePane()
        let request = PaneSessionDismissalRequest(target: MCPPaneTarget.addCustom, generation: completedGeneration)
        XCTAssertTrue(viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-add")

        viewModel.requestAddCustom()

        XCTAssertNotEqual(viewModel.paneSessions[.addCustom]?.generation, completedGeneration)
        XCTAssertEqual(viewModel.paneSessions[.addCustom]?.draft, MCPServerDraft(availableAgents: viewModel.availableAgents))
        XCTAssertEqual(viewModel.activePaneTarget, .addCustom)
        XCTAssertFalse(viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testStaleDismissalCannotCloseReopenedSameTarget() async throws {
        let service = MCPMockService(servers: [], recommended: [], availableAgents: [])
        let viewModel = MCPViewModel(mcpService: service)
        await viewModel.load()
        viewModel.requestAddCustom()
        let staleGeneration = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.generation)
        viewModel.dismissActivePane()
        viewModel.requestAddCustom()
        let reopenedGeneration = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.generation)

        viewModel.dismissPane(.addCustom, generation: staleGeneration)

        XCTAssertNotEqual(reopenedGeneration, staleGeneration)
        XCTAssertEqual(viewModel.paneSessions[.addCustom]?.generation, reopenedGeneration)
        XCTAssertEqual(viewModel.activePaneTarget, .addCustom)
        XCTAssertEqual(viewModel.paneDismissalGeneration, 1)
    }
}

@MainActor
final class MCPMockService: MCPService {
    private var storedServers: [MCPServer]
    private var storedRecommended: [RecommendedMCPServer]
    private var storedAvailableAgents: [MCPAgentAvailability]
    private let addDelay: Duration

    private(set) var loadAllCallCount = 0
    private(set) var loadRecommendedCallCount = 0

    init(
        servers: [MCPServer],
        recommended: [RecommendedMCPServer],
        availableAgents: [MCPAgentAvailability],
        addDelay: Duration = .zero
    ) {
        storedServers = servers
        storedRecommended = recommended
        storedAvailableAgents = availableAgents
        self.addDelay = addDelay
    }

    func loadAll() async throws -> [MCPServer] {
        loadAllCallCount += 1
        return storedServers
    }

    func loadRecommended() async throws -> [RecommendedMCPServer] {
        loadRecommendedCallCount += 1
        return storedRecommended
    }

    func addServer(_ server: MCPServer, for agents: [String]) async throws {
        if addDelay != .zero {
            try await Task.sleep(for: addDelay)
        }
        var updatedServer = server
        updatedServer.providers = agents
        storedServers = [updatedServer]
        storedRecommended.removeAll { $0.template.name == server.name }
    }

    func removeServer(_ server: MCPServer) async throws {
        storedServers.removeAll { $0.name == server.name }
        storedRecommended = [RecommendedMCPServer(template: server, description: "Restored", headerPrompts: [])]
    }

    func availableAgents() async -> [MCPAgentAvailability] {
        storedAvailableAgents
    }

    func setAvailableAgents(_ agents: [MCPAgentAvailability]) {
        storedAvailableAgents = agents
    }
}
