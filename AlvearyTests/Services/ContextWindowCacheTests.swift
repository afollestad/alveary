import XCTest

@testable import Alveary

final class ContextWindowCacheTests: XCTestCase {
    func testUpdateWritesSelectedAndReportedModelKeys() async throws {
        let fileURL = try temporaryCacheURL()
        let cache = JSONContextWindowCache(fileURL: fileURL)

        await cache.update(
            providerId: "claude",
            selectedModel: "sonnet",
            reportedModelId: "claude-sonnet-4-6",
            contextWindowSize: 200_000
        )

        let aliasSize = await cache.contextWindowSize(providerId: "claude", model: "sonnet")
        let reportedSize = await cache.contextWindowSize(providerId: "claude", model: "claude-sonnet-4-6")
        XCTAssertEqual(aliasSize, 200_000)
        XCTAssertEqual(reportedSize, 200_000)
    }

    func testUpdateReplacesStaleContextWindowSize() async throws {
        let fileURL = try temporaryCacheURL()
        let cache = JSONContextWindowCache(fileURL: fileURL)

        await cache.update(
            providerId: "claude",
            selectedModel: "opus",
            reportedModelId: ClaudeModelIDs.opus,
            contextWindowSize: 200_000
        )
        await cache.update(
            providerId: "claude",
            selectedModel: "opus",
            reportedModelId: ClaudeModelIDs.opus,
            contextWindowSize: 1_000_000
        )

        let aliasSize = await cache.contextWindowSize(providerId: "claude", model: "opus")
        let reportedSize = await cache.contextWindowSize(providerId: "claude", model: ClaudeModelIDs.opus)
        XCTAssertEqual(aliasSize, 1_000_000)
        XCTAssertEqual(reportedSize, 1_000_000)
    }

    private func temporaryCacheURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("context-window-sizes.json")
    }
}
