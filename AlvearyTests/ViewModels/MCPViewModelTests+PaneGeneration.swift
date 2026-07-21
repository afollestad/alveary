import XCTest

@testable import Alveary

@MainActor
extension MCPViewModelTests {
    func testRequestingDeactivatedSameTargetCreatesFreshDefaultGenerationBeforeCompletion() async throws {
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
        var staleDraft = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.draft)
        staleDraft.name = "stale-server"
        staleDraft.command = "stale-command"
        viewModel.updateActiveDraft(staleDraft)
        let staleGeneration = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.generation)

        viewModel.deactivatePane(.addCustom, generation: staleGeneration)
        viewModel.requestAddCustom()
        let reopenedGeneration = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.generation)

        XCTAssertNotEqual(reopenedGeneration, staleGeneration)
        XCTAssertEqual(viewModel.paneSessions[.addCustom]?.draft, MCPServerDraft(availableAgents: viewModel.availableAgents))
        XCTAssertEqual(viewModel.activePaneTarget, .addCustom)
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)

        viewModel.dismissPane(.addCustom, generation: staleGeneration)

        XCTAssertEqual(viewModel.paneSessions[.addCustom]?.generation, reopenedGeneration)
        XCTAssertEqual(viewModel.activePaneTarget, .addCustom)
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testCompletingDeactivatedDismissalDoesNotRestoreFocusOverNewActiveTarget() async throws {
        let recommended = makeRecommendedServer()
        let viewModel = MCPViewModel(
            mcpService: MCPMockService(servers: [], recommended: [recommended], availableAgents: [])
        )
        await viewModel.load()
        viewModel.requestAddCustom()
        let generation = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.generation)
        viewModel.deactivatePane(.addCustom, generation: generation)
        viewModel.requestAddRecommended(recommended)

        viewModel.dismissPane(.addCustom, generation: generation)

        XCTAssertEqual(viewModel.activePaneTarget, .addRecommended(recommended.id))
        XCTAssertNotNil(viewModel.paneSessions[.addRecommended(recommended.id)])
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testDelayedSubmissionDoesNotReplaceNewTargetFocusRestorationID() async throws {
        let recommended = makeRecommendedServer()
        let service = MCPMockService(
            servers: [],
            recommended: [recommended],
            availableAgents: [
                MCPAgentAvailability(agentId: "claude", name: "Claude", supportedTransports: [.stdio])
            ],
            addDelay: .milliseconds(200)
        )
        let viewModel = MCPViewModel(mcpService: service)
        await viewModel.load()
        viewModel.requestAddCustom(focusRestorationID: "mcp-add-empty")
        var draft = try XCTUnwrap(viewModel.paneSessions[.addCustom]?.draft)
        draft.name = "custom-server"
        draft.command = "npx"
        viewModel.updateActiveDraft(draft)

        let submission = Task { await viewModel.submitActivePane() }
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.requestAddRecommended(recommended)
        await submission.value

        XCTAssertEqual(viewModel.activePaneTarget, .addRecommended(recommended.id))
        XCTAssertEqual(viewModel.paneFocusRestorationID, "mcp-recommended-playwright")
    }

    private func makeRecommendedServer() -> RecommendedMCPServer {
        RecommendedMCPServer(
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
    }
}
