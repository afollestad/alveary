import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class ComposerProviderStatusCacheTests: XCTestCase {
    func testSnapshotPreservesModelScopedEffortOptions() {
        defer { ComposerProviderStatusCache.removeAll() }
        let snapshot = ComposerProviderStatusSnapshot(
            ordering: [.claude, .codex],
            statuses: [
                .claude: AgentCLIKit.AgentProviderStatus(
                    providerId: .claude,
                    definition: AgentCLIKit.ClaudeProviderDefinition.definition,
                    installation: .installed,
                    availability: AgentCLIKit.AgentProviderAvailability(
                        providerId: .claude,
                        executablePath: "/usr/local/bin/claude",
                        versionDescription: "2.1.104"
                    ),
                    setup: .ready,
                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
                )
            ]
        )

        ComposerProviderStatusCache.store(snapshot, for: "project|claude")

        let cached = ComposerProviderStatusCache.snapshot(for: "project|claude")
        XCTAssertEqual(cached?.ordering, [.claude, .codex])
        let opus = cached?.statuses[.claude]?.modelOptions.first { $0.id == "opus" }
        XCTAssertEqual(opus?.supportedEffortOptions.map(\.value), ["low", "medium", "high", "xhigh", "max"])
    }
}
