import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testHarnessVersionTrimsAndRejectsEmptyValues() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        XCTAssertNil(viewModel.harnessVersion(for: nil))
        XCTAssertNil(viewModel.harnessVersion(for: Self.cardStatus(version: nil)))
        XCTAssertNil(viewModel.harnessVersion(for: Self.cardStatus(version: "   \n")))
        XCTAssertEqual(viewModel.harnessVersion(for: Self.cardStatus(version: " 2.1.0 \n")), "2.1.0")
    }

    func testHarnessExecutablePathReadsAvailability() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        XCTAssertNil(viewModel.harnessExecutablePath(for: nil))
        XCTAssertEqual(
            viewModel.harnessExecutablePath(for: Self.cardStatus(version: "1.0.0")),
            "/usr/local/bin/claude"
        )
    }

    func testShowsStatusDescriptionOnlyWhenItAddsInformation() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        // Unregistered and disabled harnesses have nothing else to show.
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
        installation: AgentCLIKit.AgentHarnessInstallationState = .installed,
        isEnabled: Bool = true,
        setup: AgentCLIKit.AgentHarnessReadinessState = .ready,
        version: String? = "1.0.0",
        diagnostics: [String] = []
    ) -> AgentCLIKit.AgentHarnessStatus {
        AgentCLIKit.AgentHarnessStatus(
            harnessId: .claude,
            definition: AgentCLIKit.ClaudeHarnessDefinition.definition,
            installation: installation,
            availability: AgentCLIKit.AgentHarnessAvailability(
                harnessId: .claude,
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
