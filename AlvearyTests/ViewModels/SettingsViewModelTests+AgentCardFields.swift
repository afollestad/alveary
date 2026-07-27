import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testProviderVersionTrimsAndRejectsEmptyValues() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        XCTAssertNil(viewModel.providerVersion(for: nil))
        XCTAssertNil(viewModel.providerVersion(for: Self.cardStatus(version: nil)))
        XCTAssertNil(viewModel.providerVersion(for: Self.cardStatus(version: "   \n")))
        XCTAssertEqual(viewModel.providerVersion(for: Self.cardStatus(version: " 2.1.0 \n")), "2.1.0")
    }

    func testProviderExecutablePathReadsAvailability() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        XCTAssertNil(viewModel.providerExecutablePath(for: nil))
        XCTAssertEqual(
            viewModel.providerExecutablePath(for: Self.cardStatus(version: "1.0.0")),
            "/usr/local/bin/claude"
        )
    }

    func testShowsStatusDescriptionOnlyWhenItAddsInformation() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        // Unregistered and disabled providers have nothing else to show.
        XCTAssertTrue(viewModel.showsStatusDescription(for: nil))
        XCTAssertTrue(viewModel.showsStatusDescription(for: Self.cardStatus(isEnabled: false)))

        // Installed and ready repeats the version and path fields.
        XCTAssertFalse(viewModel.showsStatusDescription(for: Self.cardStatus()))

        // Diagnostics rows already render the same text the description would show.
        XCTAssertFalse(
            viewModel.showsStatusDescription(
                for: Self.cardStatus(setup: .needsSetup, diagnostics: ["login required"])
            )
        )

        // Not-yet-ready states still explain themselves through the description.
        XCTAssertTrue(viewModel.showsStatusDescription(for: Self.cardStatus(installation: .missing)))
        XCTAssertTrue(viewModel.showsStatusDescription(for: Self.cardStatus(setup: .needsSetup)))
    }

    private static func cardStatus(
        installation: AgentCLIKit.AgentProviderInstallationState = .installed,
        isEnabled: Bool = true,
        setup: AgentCLIKit.AgentProviderReadinessState = .ready,
        version: String? = "1.0.0",
        diagnostics: [String] = []
    ) -> AgentCLIKit.AgentProviderStatus {
        AgentCLIKit.AgentProviderStatus(
            providerId: .claude,
            definition: AgentCLIKit.ClaudeProviderDefinition.definition,
            installation: installation,
            availability: AgentCLIKit.AgentProviderAvailability(
                providerId: .claude,
                executablePath: "/usr/local/bin/claude",
                versionDescription: version
            ),
            isEnabled: isEnabled,
            setup: setup,
            modelOptions: [],
            diagnostics: diagnostics
        )
    }
}
