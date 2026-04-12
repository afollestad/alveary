import XCTest

@testable import Alveary

@MainActor
final class MCPViewModelTests: XCTestCase {
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
}

@MainActor
private final class MCPMockService: MCPService {
    private var storedServers: [MCPServer]
    private var storedRecommended: [RecommendedMCPServer]
    private let storedAvailableAgents: [MCPAgentAvailability]

    private(set) var loadAllCallCount = 0
    private(set) var loadRecommendedCallCount = 0

    init(
        servers: [MCPServer],
        recommended: [RecommendedMCPServer],
        availableAgents: [MCPAgentAvailability]
    ) {
        storedServers = servers
        storedRecommended = recommended
        storedAvailableAgents = availableAgents
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
}
