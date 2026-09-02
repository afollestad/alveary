import XCTest

@testable import Alveary

extension SnapshotTests {
    func testMCPAddCustomPaneAtMinimumWidth() async {
        let viewModel = makeSnapshotMCPViewModel()
        await viewModel.load()
        viewModel.requestAddCustom()

        assertMacSnapshot(
            MCPServerPane(viewModel: viewModel, target: .addCustom, onDismiss: {}),
            size: CGSize(width: 320, height: 780),
            named: "mcp_add_custom_pane_minimum_width"
        )
    }

    func testMCPAddRecommendedPaneAtMinimumWidth() async throws {
        let viewModel = makeSnapshotMCPViewModel()
        await viewModel.load()
        let recommended = try XCTUnwrap(viewModel.recommended.first)
        viewModel.requestAddRecommended(recommended)

        assertMacSnapshot(
            MCPServerPane(viewModel: viewModel, target: .addRecommended(recommended.id), onDismiss: {}),
            size: CGSize(width: 320, height: 780),
            named: "mcp_add_recommended_pane_minimum_width"
        )
    }

    func testMCPEditPaneAtMinimumWidth() async throws {
        let viewModel = makeSnapshotMCPViewModel()
        await viewModel.load()
        let server = try XCTUnwrap(viewModel.servers.first)
        viewModel.requestEdit(server)

        assertMacSnapshot(
            MCPServerPane(viewModel: viewModel, target: .edit(server.name), onDismiss: {}),
            size: CGSize(width: 320, height: 780),
            named: "mcp_edit_pane_minimum_width"
        )
    }

    /// Both row types are `private`, so this baseline is the only thing holding
    /// `isSelected` to the right pane target — comparing a server's id against an
    /// `.edit` target's name is the shape of bug it catches.
    func testMCPScreenSelectedRow() async throws {
        let viewModel = makeSnapshotMCPViewModel()
        await viewModel.load()
        let server = try XCTUnwrap(viewModel.servers.first)
        viewModel.requestEdit(server)

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "mcp_screen_selected_row"
        )
    }

    func testMCPScreenPopulatedDark() async {
        let viewModel = makeSnapshotMCPViewModel()
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 1_120, height: 900),
            named: "mcp_screen_populated_dark",
            colorScheme: .dark
        )
    }

    func testMCPScreenPopulatedNarrow() async {
        let viewModel = makeSnapshotMCPViewModel()
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 640, height: 900),
            named: "mcp_screen_populated_narrow"
        )
    }

    func testMCPScreenPopulatedSqueezed() async {
        let viewModel = makeSnapshotMCPViewModel()
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 420, height: 900),
            named: "mcp_screen_populated_squeezed"
        )
    }

    /// This header carries no filter chips, so a usable search field still fits at a width
    /// where Pull Requests has long traded its own for a button. The header must measure
    /// the parts it actually has rather than follow a shared threshold.
    func testMCPHeaderKeepsSearchFieldWhileItFits() async {
        let viewModel = makeSnapshotMCPViewModel()
        await viewModel.load()

        assertMacSnapshot(
            MCPScreenHeader(searchQuery: .constant(""), isRefreshing: false, onRefresh: {}, onAddServer: {}),
            size: CGSize(width: 290, height: 72),
            named: "mcp_header_search_field_at_narrow_width"
        )
    }

    func testMCPHeaderCollapsesSearchOnceItDoesNotFit() async {
        assertMacSnapshot(
            MCPScreenHeader(searchQuery: .constant(""), isRefreshing: false, onRefresh: {}, onAddServer: {}),
            size: CGSize(width: 230, height: 72),
            named: "mcp_header_search_collapsed"
        )
    }

    func testMCPScreenNoAddedServers() async {
        let viewModel = makeSnapshotMCPViewModel(servers: [])
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "mcp_screen_no_added_servers"
        )
    }

    /// Like `testMCPScreenSelectedRow`: the built-in card's fill follows the
    /// `.builtInToolGroup` target's id, and this baseline is what holds it there.
    func testMCPScreenSelectedBuiltInToolGroup() async throws {
        let viewModel = makeSnapshotMCPViewModel()
        await viewModel.load()
        let group = try XCTUnwrap(viewModel.builtInToolGroups.first)
        viewModel.requestBuiltInToolGroupDetails(group)

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "mcp_screen_selected_built_in_tool_group"
        )
    }

    /// Mounted through `MCPPane` so the lane's target routing is what renders it.
    func testMCPBuiltInToolGroupPaneAtMinimumWidth() async throws {
        let viewModel = makeSnapshotMCPViewModel()
        let group = try XCTUnwrap(viewModel.builtInToolGroups.first)

        assertMacSnapshot(
            MCPPane(viewModel: viewModel, target: .builtInToolGroup(group.id), onDismiss: {}),
            size: CGSize(width: 320, height: 780),
            named: "mcp_built_in_tool_group_pane_minimum_width"
        )
    }
}
