import AgentCLIKit
import XCTest

@testable import Alveary

/// Claude now reports pinned model versions and carries each family alias only as the newest version's short name, so
/// every value persisted before that change reaches the app as an alias with no matching option id.
final class AgentModelOptionSelectionTests: XCTestCase {
    func testStoredFamilyAliasResolvesToTheNewestPinnedVersion() {
        let option = AgentModelOptionSelection.option(in: Self.claudeOptions, matching: "opus")

        XCTAssertEqual(option?.id, "claude-opus-5-5")
    }

    func testStoredFamilyAliasIsRewrittenToTheFullModelIDOnTheNextWrite() {
        let stored = AgentModelOptionSelection.storedModelValue(in: Self.claudeOptions, matching: "opus")

        XCTAssertEqual(stored, "claude-opus-5-5")
    }

    /// A short name must never win over an option that owns the value as its id.
    func testExactModelIDWinsOverAnotherOptionsShortName() {
        let options = Self.claudeOptions + [
            AgentCLIKit.AgentModelOption(harnessId: .claude, id: "opus", model: "opus", label: "Legacy Opus")
        ]

        XCTAssertEqual(AgentModelOptionSelection.option(in: options, matching: "opus")?.label, "Legacy Opus")
    }

    func testStoredFamilyAliasKeepsItsEffortLadderAndMenuSelection() {
        let efforts = AgentModelOptionSelection.effortOptions(in: Self.claudeOptions, selectedModel: "opus")
        let menuItems = AgentModelOptionSelection.menuItems(
            in: Self.claudeOptions,
            selectedModel: "opus",
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        )

        XCTAssertEqual(efforts.map(\.value), ["low", "medium", "high", "xhigh", "max"])
        // No synthesized fallback row: the alias already belongs to a listed option.
        XCTAssertEqual(menuItems.map(\.value), Self.claudeOptions.map(\.id))
    }

    /// Thread defaults reset any model they cannot resolve, so a dropped alias would silently discard the user's choice.
    func testThreadDefaultsKeepAStoredFamilyAliasInsteadOfResettingIt() {
        var settings = AppSettings()
        settings.defaultHarness = "claude"
        settings.defaultModel = "opus"

        let resolution = ThreadDefaultResolver.resolve(
            settings: settings,
            harnessOrdering: ["claude"],
            harnessStatuses: ["claude": Self.claudeStatus]
        )

        XCTAssertEqual(resolution.storedThreadModel, "claude-opus-5-5")
    }

    /// Anything falling back to "the default model" must resolve `isDefault`, never row zero: Claude lists its
    /// strongest model first, so taking the first row would silently upgrade what the user pays for.
    func testDefaultModelValueResolvesToTheDefaultOptionNotTheFirstRow() {
        let pickerValue = AgentModelOptionSelection.pickerValue(
            in: Self.claudeOptions,
            matching: AppSettings.defaultModelValue
        )

        XCTAssertEqual(Self.claudeOptions.first?.id, "claude-opus-5-5")
        XCTAssertEqual(pickerValue, "claude-sonnet-5")
    }

    /// The composer paints before discovery's first probe lands, so the cold-path catalog must resolve a persisted
    /// pinned id to its real label instead of synthesizing a raw-id row.
    func testStaticCatalogResolvesAPersistedPinnedIDBeforeDiscovery() {
        let options = AgentCLIKit.AgentDefaultModelOptions.staticOptions(for: .claude)
        for (model, label) in [("claude-opus-5-5", "Opus 5.5"), ("claude-opus-5", "Opus 5")] {
            let menuItems = AgentModelOptionSelection.menuItems(
                in: options,
                selectedModel: model,
                fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
            )

            XCTAssertEqual(menuItems.first { $0.value == model }?.title, label)
            XCTAssertEqual(AgentModelOptionSelection.storedModelValue(in: options, matching: model), model)
            // No synthesized fallback row: each pinned id belongs to a listed option.
            XCTAssertEqual(menuItems.map(\.value), options.map(\.id))
        }
    }

    func testStaticCatalogNormalizesEffortForTheSelectedOpusVersion() {
        let options = AgentCLIKit.AgentDefaultModelOptions.staticOptions(for: .claude)

        for model in ["opus", "claude-opus-5-5"] {
            XCTAssertEqual(AgentModelOptionSelection.normalizedEffort("ultra", options: options, selectedModel: model), "medium")
            XCTAssertEqual(AgentModelOptionSelection.normalizedEffort("high", options: options, selectedModel: model), "high")
        }
        XCTAssertEqual(AgentModelOptionSelection.normalizedEffort("ultra", options: options, selectedModel: "claude-opus-5"), "high")
    }

    func testStaticCatalogResolvesTheDefaultSentinelToTheDefaultOption() {
        let pickerValue = AgentModelOptionSelection.pickerValue(
            in: AgentCLIKit.AgentDefaultModelOptions.staticOptions(for: .claude),
            matching: AppSettings.defaultModelValue
        )

        XCTAssertEqual(pickerValue, "claude-sonnet-5")
    }

    /// Mirrors the real catalog's shape: the strongest model leads and the default sits further down.
    private static let claudeOptions: [AgentCLIKit.AgentModelOption] = [
        AgentCLIKit.AgentModelOption(
            harnessId: .claude,
            id: "claude-opus-5-5",
            model: "claude-opus-5-5",
            label: "Opus 5.5",
            shortName: "opus",
            supportedEffortOptions: AgentModelOptionTestFixtures.claudeOpusEfforts,
            defaultEffortOption: AgentModelOptionTestFixtures.medium
        ),
        AgentCLIKit.AgentModelOption(
            harnessId: .claude,
            id: "claude-opus-5",
            model: "claude-opus-5",
            label: "Opus 5",
            supportedEffortOptions: AgentModelOptionTestFixtures.claudeOpusEfforts,
            defaultEffortOption: AgentModelOptionTestFixtures.high
        ),
        AgentCLIKit.AgentModelOption(
            harnessId: .claude,
            id: "claude-sonnet-5",
            model: "claude-sonnet-5",
            label: "Sonnet 5",
            shortName: "sonnet",
            isDefault: true,
            supportedEffortOptions: AgentModelOptionTestFixtures.claudeSonnetEfforts,
            defaultEffortOption: AgentModelOptionTestFixtures.high
        )
    ]

    private static var claudeStatus: AgentCLIKit.AgentHarnessStatus {
        AgentCLIKit.AgentHarnessStatus(
            harnessId: .claude,
            definition: AgentCLIKit.ClaudeHarnessDefinition.definition,
            installation: .installed,
            availability: AgentCLIKit.AgentHarnessAvailability(
                harnessId: .claude,
                executablePath: "/usr/local/bin/claude"
            ),
            setup: .ready,
            modelOptions: claudeOptions
        )
    }
}
