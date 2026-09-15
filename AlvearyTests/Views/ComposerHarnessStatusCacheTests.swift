import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class ComposerHarnessStatusCacheTests: XCTestCase {
    func testCacheKeyIsStableAcrossActiveHarnessSelection() {
        let settings = AppSettings()
        let projectURL = URL(fileURLWithPath: "/tmp/project")

        let claudeKey = ConversationView.composerHarnessStatusCacheKey(
            projectURL: projectURL,
            activeHarnessID: "claude",
            settings: settings
        )
        let codexKey = ConversationView.composerHarnessStatusCacheKey(
            projectURL: projectURL,
            activeHarnessID: "codex",
            settings: settings
        )

        XCTAssertEqual(claudeKey, codexKey)
    }

    func testSnapshotPreservesModelScopedEffortOptions() {
        defer { ComposerHarnessStatusCache.removeAll() }
        let solEfforts = effortOptions(["low", "medium", "high", "xhigh", "max", "ultra"])
        let lunaEfforts = effortOptions(["low", "medium", "high", "xhigh", "max"])
        let snapshot = harnessSnapshot(codexModelOptions: [
            AgentCLIKit.AgentModelOption(
                harnessId: .codex,
                id: "gpt-5.6-sol",
                model: "gpt-5.6-sol",
                label: "GPT-5.6-Sol",
                supportedEffortOptions: solEfforts,
                defaultEffortOption: solEfforts.first
            ),
            AgentCLIKit.AgentModelOption(
                harnessId: .codex,
                id: "gpt-5.6-luna",
                model: "gpt-5.6-luna",
                label: "GPT-5.6-Luna",
                supportedEffortOptions: lunaEfforts,
                defaultEffortOption: lunaEfforts.first
            )
        ])

        ComposerHarnessStatusCache.store(snapshot, for: "project|claude")

        let cached = ComposerHarnessStatusCache.snapshot(for: "project|claude")
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

    private func harnessSnapshot(
        codexModelOptions: [AgentCLIKit.AgentModelOption]
    ) -> ComposerHarnessStatusSnapshot {
        ComposerHarnessStatusSnapshot(
            ordering: [.claude, .codex],
            statuses: [
                .claude: AgentCLIKit.AgentHarnessStatus(
                    harnessId: .claude,
                    definition: AgentCLIKit.ClaudeHarnessDefinition.definition,
                    installation: .installed,
                    availability: AgentCLIKit.AgentHarnessAvailability(
                        harnessId: .claude,
                        executablePath: "/usr/local/bin/claude",
                        versionDescription: "2.1.104"
                    ),
                    setup: .ready,
                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
                ),
                .codex: AgentCLIKit.AgentHarnessStatus(
                    harnessId: .codex,
                    definition: AgentCLIKit.CodexHarnessDefinition.definition,
                    installation: .installed,
                    availability: AgentCLIKit.AgentHarnessAvailability(
                        harnessId: .codex,
                        executablePath: "/usr/local/bin/codex",
                        versionDescription: "0.144.0"
                    ),
                    setup: .ready,
                    modelOptions: codexModelOptions
                )
            ]
        )
    }

    private func effortOptions(_ values: [String]) -> [AgentCLIKit.AgentHarnessOption] {
        values.map {
            AgentCLIKit.AgentHarnessOption(
                value: $0,
                label: $0.capitalized,
                description: "Use \($0) reasoning effort."
            )
        }
    }
}
