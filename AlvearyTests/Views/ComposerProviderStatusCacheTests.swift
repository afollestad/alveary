import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class ComposerProviderStatusCacheTests: XCTestCase {
    func testCacheKeyIsStableAcrossActiveProviderSelection() {
        let settings = AppSettings()
        let projectURL = URL(fileURLWithPath: "/tmp/project")

        let claudeKey = ConversationView.composerProviderStatusCacheKey(
            projectURL: projectURL,
            activeProviderID: "claude",
            settings: settings
        )
        let codexKey = ConversationView.composerProviderStatusCacheKey(
            projectURL: projectURL,
            activeProviderID: "codex",
            settings: settings
        )

        XCTAssertEqual(claudeKey, codexKey)
    }

    func testSnapshotPreservesModelScopedEffortOptions() {
        defer { ComposerProviderStatusCache.removeAll() }
        let solEfforts = effortOptions(["low", "medium", "high", "xhigh", "max", "ultra"])
        let lunaEfforts = effortOptions(["low", "medium", "high", "xhigh", "max"])
        let snapshot = providerSnapshot(codexModelOptions: [
            AgentCLIKit.AgentModelOption(
                providerId: .codex,
                id: "gpt-5.6-sol",
                model: "gpt-5.6-sol",
                label: "GPT-5.6-Sol",
                supportedEffortOptions: solEfforts,
                defaultEffortOption: solEfforts.first
            ),
            AgentCLIKit.AgentModelOption(
                providerId: .codex,
                id: "gpt-5.6-luna",
                model: "gpt-5.6-luna",
                label: "GPT-5.6-Luna",
                supportedEffortOptions: lunaEfforts,
                defaultEffortOption: lunaEfforts.first
            )
        ])

        ComposerProviderStatusCache.store(snapshot, for: "project|claude")

        let cached = ComposerProviderStatusCache.snapshot(for: "project|claude")
        XCTAssertEqual(cached?.ordering, [.claude, .codex])
        let opus = cached?.statuses[.claude]?.modelOptions.first { $0.id == "opus" }
        XCTAssertEqual(opus?.supportedEffortOptions.map(\.value), ["low", "medium", "high", "xhigh", "max"])

        let cachedCodexOptions = cached?.statuses[.codex]?.modelOptions ?? []
        XCTAssertEqual(
            AgentModelOptionSelection.effortOptions(in: cachedCodexOptions, selectedModel: "gpt-5.6-sol").map(\.value),
            ["low", "medium", "high", "xhigh", "max", "ultra"]
        )
        XCTAssertEqual(
            AgentModelOptionSelection.effortOptions(in: cachedCodexOptions, selectedModel: "gpt-5.6-luna").map(\.value),
            ["low", "medium", "high", "xhigh", "max"]
        )
    }

    private func providerSnapshot(
        codexModelOptions: [AgentCLIKit.AgentModelOption]
    ) -> ComposerProviderStatusSnapshot {
        ComposerProviderStatusSnapshot(
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
                ),
                .codex: AgentCLIKit.AgentProviderStatus(
                    providerId: .codex,
                    definition: AgentCLIKit.CodexProviderDefinition.definition,
                    installation: .installed,
                    availability: AgentCLIKit.AgentProviderAvailability(
                        providerId: .codex,
                        executablePath: "/usr/local/bin/codex",
                        versionDescription: "0.144.0"
                    ),
                    setup: .ready,
                    modelOptions: codexModelOptions
                )
            ]
        )
    }

    private func effortOptions(_ values: [String]) -> [AgentCLIKit.AgentProviderOption] {
        values.map {
            AgentCLIKit.AgentProviderOption(
                value: $0,
                label: $0.capitalized,
                description: "Use \($0) reasoning effort."
            )
        }
    }
}
