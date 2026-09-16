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
        XCTAssertEqual(viewModel.supportedModels, ["sonnet", "fable", "opus", "haiku"])
        XCTAssertEqual(viewModel.permissionModeOptions(for: "claude"), AppSettings.supportedPermissionModes(forHarness: "claude"))
        XCTAssertEqual(viewModel.permissionModeOptions(for: "codex"), AppSettings.supportedPermissionModes(forHarness: "codex"))
        let claudePermissionLabels = ["default", "acceptEdits", "auto", "bypassPermissions"].map {
            viewModel.permissionModeLabel(for: $0, harnessId: "claude")
        }
        let codexPermissionLabels = ["untrusted", "on-request", "never"].map { viewModel.permissionModeLabel(for: $0, harnessId: "codex") }
        XCTAssertEqual(claudePermissionLabels, ["Default", "Accept edits", "Automatic", "Bypass permissions"])
        XCTAssertEqual(codexPermissionLabels, ["Ask for approval", "Approve for me", "Full access"])
        XCTAssertEqual(
            viewModel.effortOptions(for: "claude", model: "opus").map(\.value),
            ["low", "medium", "high", "xhigh", "max"]
        )
        XCTAssertEqual(
            viewModel.effortOptions(for: "claude", model: "sonnet").map(\.value),
            ["low", "medium", "high", "max"]
        )
        XCTAssertEqual(
            viewModel.effortOptions(for: "claude", model: "default").map(\.value),
            ["low", "medium", "high", "max"]
        )
        XCTAssertEqual(
            viewModel.effortOptions(for: "claude", model: "fable").map(\.value),
            ["low", "medium", "high", "xhigh", "max"]
        )
        XCTAssertEqual(
            viewModel.effortOptions(for: "claude", model: "haiku").map(\.value),
            ["low", "medium", "high"]
        )
        XCTAssertEqual(viewModel.themeOptions, ["system", "light", "dark"])
        XCTAssertEqual(viewModel.availableSoundNames, ["Glass", "Pop", "Tink", "Purr"])
        XCTAssertEqual(viewModel.codeFontFamilyOptions, [AppSettings.defaultCodeFontFamily])
        XCTAssertTrue(viewModel.permissionModeOptions(for: "unknown").isEmpty)
        XCTAssertEqual(viewModel.permissionModeLabel(for: "unknown", harnessId: "unknown"), "unknown")
        XCTAssertTrue(viewModel.effortOptions(for: "unknown", model: "opus").isEmpty)
        XCTAssertEqual(viewModel.modelOptionValues(for: "codex"), ["gpt-5.5", "gpt-5.4-mini"])
        XCTAssertEqual(viewModel.modelLabel(for: "gpt-5.4-mini", harnessId: "codex"), "GPT-5.4-Mini")
        XCTAssertEqual(viewModel.effortOptions(for: "codex", model: "gpt-5.5").map(\.value), ["low", "medium", "high", "xhigh"])
        XCTAssertEqual(viewModel.effortOptions(for: "codex", model: "gpt-5.4-mini").map(\.value), ["low", "medium"])
    }
}
