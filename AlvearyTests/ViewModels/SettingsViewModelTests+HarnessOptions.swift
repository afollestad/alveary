import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testOptionSourcesAreStableAndPickerSafe() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.harnessStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ])
        )

        await viewModel.refreshHarnessStatuses()

        XCTAssertEqual(viewModel.availableHarnessIDs, ["claude", "codex", "opencode"])
        XCTAssertEqual(viewModel.threadDefaultAgentPresentation.modelGroups.first?.options.map(\.value), ["sonnet", "fable", "opus", "haiku"])
        XCTAssertEqual(viewModel.permissionModeOptions(for: "claude"), AppSettings.supportedPermissionModes(forHarness: "claude"))
        XCTAssertEqual(viewModel.permissionModeOptions(for: "codex"), AppSettings.supportedPermissionModes(forHarness: "codex"))
        let claudePermissionLabels = ["default", "acceptEdits", "auto", "bypassPermissions"].map {
            viewModel.permissionModeLabel(for: $0, harnessId: "claude")
        }
        let codexPermissionLabels = ["untrusted", "on-request", "never"].map { viewModel.permissionModeLabel(for: $0, harnessId: "codex") }
        XCTAssertEqual(claudePermissionLabels, ["Default", "Accept edits", "Automatic", "Bypass permissions"])
        XCTAssertEqual(codexPermissionLabels, ["Ask for approval", "Approve for me", "Full access"])
        // The stored `default` alias resolves to the catalog default's effort levels.
        XCTAssertEqual(viewModel.threadDefaultAgentPresentation.selection.effortOptions.map(\.value), ["low", "medium", "high", "max"])
        XCTAssertEqual(viewModel.themeOptions, ["system", "light", "dark"])
        XCTAssertEqual(viewModel.availableSoundNames, ["Glass", "Pop", "Tink", "Purr"])
        XCTAssertEqual(viewModel.codeFontFamilyOptions, [AppSettings.defaultCodeFontFamily])
        XCTAssertTrue(viewModel.permissionModeOptions(for: "unknown").isEmpty)
        XCTAssertEqual(viewModel.permissionModeLabel(for: "unknown", harnessId: "unknown"), "unknown")
        XCTAssertEqual(viewModel.threadDefaultAgentPresentation.modelGroups.last?.options.map(\.title), ["GPT-5.5", "GPT-5.4-Mini"])
    }
}
