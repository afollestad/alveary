import XCTest

@testable import Skep

final class MCPAdapterTests: XCTestCase {
    func testPassthroughAdapterRoundTripsUnchanged() {
        let servers: ServerMap = [
            "context7": [
                "url": "https://mcp.context7.com/mcp",
                "headers": ["X-API-KEY": "secret"]
            ]
        ]

        let forward = MCPAdapter.adaptForward(.passthrough, servers: servers)
        let reverse = MCPAdapter.adaptReverse(.passthrough, servers: forward)

        XCTAssertEqual(forward.keys.sorted(), ["context7"])
        XCTAssertEqual(reverse["context7"]?["url"] as? String, "https://mcp.context7.com/mcp")
        XCTAssertEqual((reverse["context7"]?["headers"] as? [String: String])?["X-API-KEY"], "secret")
    }
}
