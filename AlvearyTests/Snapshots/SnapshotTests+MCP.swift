import XCTest

@testable import Alveary

extension SnapshotTests {
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
