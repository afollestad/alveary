import XCTest

@testable import Alveary

extension SnapshotTests {
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
