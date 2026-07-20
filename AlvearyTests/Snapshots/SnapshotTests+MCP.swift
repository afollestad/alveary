import XCTest

@testable import Alveary

extension SnapshotTests {
    func testMCPAddCustomPaneAtMinimumWidth() async {
        let viewModel = MCPViewModel(mcpService: SnapshotMCPService())
        await viewModel.load()
        viewModel.requestAddCustom()

        assertMacSnapshot(
            MCPServerPane(viewModel: viewModel),
            size: CGSize(width: 320, height: 780),
            named: "mcp_add_custom_pane_minimum_width"
        )
    }

    func testMCPAddRecommendedPaneAtMinimumWidth() async throws {
        let viewModel = MCPViewModel(mcpService: SnapshotMCPService())
        await viewModel.load()
        viewModel.requestAddRecommended(try XCTUnwrap(viewModel.recommended.first))

        assertMacSnapshot(
            MCPServerPane(viewModel: viewModel),
            size: CGSize(width: 320, height: 780),
            named: "mcp_add_recommended_pane_minimum_width"
        )
    }

    func testMCPEditPaneAtMinimumWidth() async throws {
        let viewModel = MCPViewModel(mcpService: SnapshotMCPService())
        await viewModel.load()
        viewModel.requestEdit(try XCTUnwrap(viewModel.servers.first))

        assertMacSnapshot(
            MCPServerPane(viewModel: viewModel),
            size: CGSize(width: 320, height: 780),
            named: "mcp_edit_pane_minimum_width"
        )
    }

    func testMCPScreenPopulatedDark() async {
        let viewModel = MCPViewModel(mcpService: SnapshotMCPService())
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 1_120, height: 900),
            named: "mcp_screen_populated_dark",
            colorScheme: .dark
        )
    }

    func testMCPScreenPopulatedNarrow() async {
        let viewModel = MCPViewModel(mcpService: SnapshotMCPService())
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 640, height: 900),
            named: "mcp_screen_populated_narrow"
        )
    }

    func testMCPScreenNoAddedServers() async {
        let viewModel = MCPViewModel(mcpService: SnapshotMCPService(servers: []))
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "mcp_screen_no_added_servers"
        )
    }
}
