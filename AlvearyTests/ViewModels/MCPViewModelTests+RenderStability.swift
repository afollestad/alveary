import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension MCPViewModelTests {
    func testMCPServerRowEqualityIgnoresItsActionsAndComparesTheRenderedServer() {
        let server = makeServer()
        let row = makeRow(server: server)

        XCTAssertEqual(row, makeRow(server: server))
        XCTAssertNotEqual(row, makeRow(server: makeServer(providers: ["codex"])))
        XCTAssertNotEqual(row, makeRow(server: makeServer(name: "other")))
        XCTAssertNotEqual(row, makeRow(server: server, isSelected: true))
        XCTAssertNotEqual(row, makeRow(server: server, focusID: "mcp-edit-other"))
    }

    func testRecommendedMCPCardEqualityIgnoresItsActionAndComparesTheRenderedServer() {
        let recommended = makeRecommended()
        let card = makeCard(server: recommended)

        XCTAssertEqual(card, makeCard(server: recommended))
        XCTAssertNotEqual(card, makeCard(server: makeRecommended(description: "Something else")))
        XCTAssertNotEqual(card, makeCard(server: makeRecommended(name: "other")))
        XCTAssertNotEqual(card, makeCard(server: recommended, isSelected: true))
        XCTAssertNotEqual(card, makeCard(server: recommended, focusID: "mcp-recommended-other"))
    }
}

private func makeServer(name: String = "context7", providers: [String] = ["claude"]) -> MCPServer {
    MCPServer(
        name: name,
        transport: .http,
        command: nil,
        args: nil,
        url: "https://mcp.context7.com/mcp",
        headers: nil,
        env: nil,
        providers: providers
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
            providers: []
        ),
        description: description,
        headerPrompts: []
    )
}

/// Both row types store a `FocusState` binding, which only a `View` can vend, so equality
/// fixtures build one through a host rather than constructing the binding directly.
/// SwiftUI logs that the binding is read outside a `View` body and is therefore constant —
/// which is exactly what an `==` fixture wants, since the binding is excluded from `==`.
@MainActor
private func makeRow(
    server: MCPServer,
    isSelected: Bool = false,
    focusID: String = "mcp-edit-context7"
) -> MCPServerRow {
    MCPServerRowEqualityHost(server: server, isSelected: isSelected, focusID: focusID).row
}

@MainActor
private func makeCard(
    server: RecommendedMCPServer,
    isSelected: Bool = false,
    focusID: String = "mcp-recommended-playwright"
) -> RecommendedMCPCard {
    RecommendedMCPCardEqualityHost(server: server, isSelected: isSelected, focusID: focusID).card
}

private struct MCPServerRowEqualityHost: View {
    let server: MCPServer
    let isSelected: Bool
    let focusID: String

    @FocusState private var focus: String?

    var row: MCPServerRow {
        MCPServerRow(
            server: server,
            isSelected: isSelected,
            onEdit: {},
            onRemove: {},
            editFocus: $focus,
            editFocusID: focusID
        )
    }

    var body: some View {
        row
    }
}

private struct RecommendedMCPCardEqualityHost: View {
    let server: RecommendedMCPServer
    let isSelected: Bool
    let focusID: String

    @FocusState private var focus: String?

    var card: RecommendedMCPCard {
        RecommendedMCPCard(
            server: server,
            isSelected: isSelected,
            onAdd: {},
            addFocus: $focus,
            addFocusID: focusID
        )
    }

    var body: some View {
        card
    }
}
