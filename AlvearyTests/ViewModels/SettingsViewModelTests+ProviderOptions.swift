import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testOptionSourcesAreStableAndPickerSafe() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.providerStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ])
        )

        await viewModel.refreshProviderStatuses()

        XCTAssertEqual(viewModel.availableProviderIDs, ["claude", "codex"])
        XCTAssertEqual(viewModel.supportedModels, ["sonnet", "fable", "opus", "haiku"])
        XCTAssertEqual(viewModel.permissionModeOptions(for: "claude"), AppSettings.supportedPermissionModes(forProvider: "claude"))
        XCTAssertEqual(viewModel.permissionModeOptions(for: "codex"), AppSettings.supportedPermissionModes(forProvider: "codex"))
        let claudePermissionLabels = ["default", "acceptEdits", "auto"].map { viewModel.permissionModeLabel(for: $0, providerId: "claude") }
        let codexPermissionLabels = ["untrusted", "on-request", "never"].map { viewModel.permissionModeLabel(for: $0, providerId: "codex") }
        XCTAssertEqual(claudePermissionLabels, ["Default", "Accept edits", "Automatic"])
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
        XCTAssertEqual(viewModel.permissionModeLabel(for: "unknown", providerId: "unknown"), "unknown")
        XCTAssertTrue(viewModel.effortOptions(for: "unknown", model: "opus").isEmpty)
        XCTAssertEqual(viewModel.modelOptionValues(for: "codex"), ["gpt-5.5", "gpt-5.4-mini"])
        XCTAssertEqual(viewModel.modelLabel(for: "gpt-5.4-mini", providerId: "codex"), "GPT-5.4-Mini")
        XCTAssertEqual(viewModel.effortOptions(for: "codex", model: "gpt-5.5").map(\.value), ["low", "medium", "high", "xhigh"])
        XCTAssertEqual(viewModel.effortOptions(for: "codex", model: "gpt-5.4-mini").map(\.value), ["low", "medium"])
    }
}
