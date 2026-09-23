import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension MCPViewModelTests {
    func testMCPServerRowEqualityIgnoresItsActionsAndComparesTheRenderedServer() throws {
        let server = makeServer()
        let row = try makeRow(server: server)

        XCTAssertEqual(row, try makeRow(server: server))
        XCTAssertNotEqual(row, try makeRow(server: makeServer(harnesses: ["codex"])))
        XCTAssertNotEqual(row, try makeRow(server: makeServer(name: "other")))
        XCTAssertNotEqual(row, try makeRow(server: server, isSelected: true))
        XCTAssertNotEqual(row, try makeRow(server: server, focusID: "mcp-edit-other"))
    }

    func testRecommendedMCPCardEqualityIgnoresItsActionAndComparesTheRenderedServer() throws {
        let recommended = makeRecommended()
        let card = try makeCard(server: recommended)

        XCTAssertEqual(card, try makeCard(server: recommended))
        XCTAssertNotEqual(card, try makeCard(server: makeRecommended(description: "Something else")))
        XCTAssertNotEqual(card, try makeCard(server: makeRecommended(name: "other")))
        XCTAssertNotEqual(card, try makeCard(server: recommended, isSelected: true))
        XCTAssertNotEqual(card, try makeCard(server: recommended, focusID: "mcp-recommended-other"))
    }

    func testBuiltInMCPToolGroupCardEqualityIgnoresItsActionAndComparesTheRenderedGroup() throws {
        let group = makeBuiltInToolGroup()
        let card = try makeBuiltInCard(group: group)

        XCTAssertEqual(card, try makeBuiltInCard(group: group))
        XCTAssertNotEqual(card, try makeBuiltInCard(group: makeBuiltInToolGroup(title: "Something else")))
        XCTAssertNotEqual(card, try makeBuiltInCard(group: makeBuiltInToolGroup(tools: [])))
        XCTAssertNotEqual(card, try makeBuiltInCard(group: group, isSelected: true))
        XCTAssertNotEqual(card, try makeBuiltInCard(group: group, focusID: "mcp-built-in-other"))
    }
}

private func makeServer(name: String = "context7", harnesses: [String] = ["claude"]) -> MCPServer {
    MCPServer(
        name: name,
        transport: .http,
        command: nil,
        args: nil,
        url: "https://mcp.context7.com/mcp",
        headers: nil,
        env: nil,
        harnesses: harnesses
    )
}

private func makeRecommended(
    name: String = "playwright",
    description: String = "Browser automation"
) -> RecommendedMCPServer {
    RecommendedMCPServer(
        template: MCPServer(
            name: name,
            transport: .stdio,
            command: "npx",
            args: nil,
            url: nil,
            headers: nil,
            env: nil,
            harnesses: []
        ),
        description: description,
        headerPrompts: []
    )
}

/// These types store a `FocusState` binding, which `hostedFocusStateBinding()` vends from a real
/// body pass; the binding is excluded from `==`, so any live one serves.
@MainActor
private func makeRow(
    server: MCPServer,
    isSelected: Bool = false,
    focusID: String = "mcp-edit-context7"
) throws -> MCPServerRow {
    MCPServerRow(
        server: server,
        isSelected: isSelected,
        onEdit: {},
        onRemove: {},
        editFocus: try hostedFocusStateBinding(String.self),
        editFocusID: focusID
    )
}

@MainActor
private func makeCard(
    server: RecommendedMCPServer,
    isSelected: Bool = false,
    focusID: String = "mcp-recommended-playwright"
) throws -> RecommendedMCPCard {
    RecommendedMCPCard(
        server: server,
        isSelected: isSelected,
        onAdd: {},
        addFocus: try hostedFocusStateBinding(String.self),
        addFocusID: focusID
    )
}

@MainActor
private func makeBuiltInCard(
    group: BuiltInMCPToolGroup,
    isSelected: Bool = false,
    focusID: String = "mcp-built-in-threads"
) throws -> BuiltInMCPToolGroupCard {
    BuiltInMCPToolGroupCard(
        group: group,
        isSelected: isSelected,
        onOpen: {},
        openFocus: try hostedFocusStateBinding(String.self),
        openFocusID: focusID
    )
}
