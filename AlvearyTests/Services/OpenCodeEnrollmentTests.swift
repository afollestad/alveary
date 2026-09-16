import AgentCLIKit
import XCTest

@testable import Alveary

final class OpenCodeEnrollmentTests: XCTestCase {
    func testSettingsRoundTripPreservesProviderModelVariantAndPermissionSelection() throws {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "provider/family/model"
        settings.effort = "native-variant"
        settings.permissionMode = "configured"

        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).normalized()

        XCTAssertEqual(restored.defaultHarness, "opencode")
        XCTAssertEqual(restored.defaultModel, "provider/family/model")
        XCTAssertEqual(restored.effort, "native-variant")
        XCTAssertEqual(restored.permissionMode, "configured")
        settings.permissionMode = "on-request"
        XCTAssertEqual(settings.normalized().permissionMode, "ask")
        settings.disabledHarnessIDs.insert("opencode")
        XCTAssertEqual(settings.normalized().defaultHarness, "opencode")
    }

    func testUnavailableOpenCodeDefaultDoesNotSwitchToReadyClaudeOrDiscardModel() {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "private-provider/family/model"
        settings.effort = "native-variant"
        let statuses: [String: AgentHarnessStatus] = [
            "claude": AgentHarnessStatus(
                harnessId: .claude, definition: ClaudeHarnessDefinition.definition,
                installation: .installed, setup: .ready, modelOptions: []
            ),
            "opencode": AgentHarnessStatus(
                harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition,
                installation: .installed, setup: .failed, modelOptions: [], diagnostics: ["Upgrade required"]
            )
        ]

        let resolved = ThreadDefaultResolver.resolve(
            settings: settings, harnessOrdering: ["claude", "opencode"], harnessStatuses: statuses
        )

        XCTAssertEqual(resolved.harnessID, "opencode")
        XCTAssertEqual(resolved.storedThreadModel, "private-provider/family/model")
        XCTAssertEqual(resolved.effort, "native-variant")
        XCTAssertEqual(resolved.readyHarnessIDs, ["claude"])
        XCTAssertFalse(resolved.hasReadyHarness)
        let cold = ThreadDefaultResolver.resolve(
            settings: settings, harnessOrdering: ["opencode"], harnessStatuses: [:], allowStaticFallback: true
        )
        XCTAssertEqual(cold.harnessID, "opencode")
        XCTAssertFalse(cold.hasReadyHarness)
        settings.disabledHarnessIDs.insert("opencode")
        let disabled = ThreadDefaultResolver.resolve(
            settings: settings.normalized(), harnessOrdering: ["claude", "opencode"], harnessStatuses: statuses
        )
        XCTAssertEqual(disabled.harnessID, "opencode")
        XCTAssertFalse(disabled.hasReadyHarness)
    }

    func testOpenCodeFallbackDoesNotInheritAnotherHarnessModelOrEffort() {
        var settings = AppSettings()
        settings.defaultHarness = "claude"
        settings.defaultModel = "opus"
        settings.effort = "high"
        let status = AgentHarnessStatus(harnessId: .opencode, installation: .installed, setup: .ready)
        let resolved = ThreadDefaultResolver.resolve(
            settings: settings, harnessOrdering: ["claude", "opencode"], harnessStatuses: ["opencode": status]
        )
        XCTAssertEqual(resolved.harnessID, "opencode")
        XCTAssertNil(resolved.storedThreadModel)
        XCTAssertEqual(resolved.effort, AppSettings.openCodeDefaultEffort)
    }

    func testDiscoveredModelDoesNotSilentlyNormalizeSavedUnavailableVariant() {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "provider/model"
        settings.effort = "removed-variant"
        let status = AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition, installation: .installed, setup: .ready,
            modelOptions: [AgentModelOption(harnessId: .opencode, id: "provider/model", model: "provider/model", label: "Model")]
        )
        let resolved = ThreadDefaultResolver.resolve(
            settings: settings, harnessOrdering: ["opencode"], harnessStatuses: ["opencode": status]
        )
        XCTAssertEqual(resolved.effort, "removed-variant")
    }

    func testRegistryEnrollsOpenCodeInSharedSkillsInstructionsAndNativeMCP() throws {
        let registry = DefaultAgentRegistry(environment: [:])
        let agent = try XCTUnwrap(registry.agent(for: "opencode"))
        let harness = try XCTUnwrap(DefaultHarnessRegistry(agentRegistry: registry).harness(for: "opencode"))

        XCTAssertEqual(harness.commands, ["opencode"])
        XCTAssertEqual(harness.supportedPermissionModes?.map(\.value), OpenCodeHarnessDefinition.definition.supportedPermissionModes?.map(\.value))
        XCTAssertEqual(agent.signInCommand, "opencode auth login")
        XCTAssertEqual(agent.skillsDirectory, "~/.config/opencode/skills")
        XCTAssertEqual(agent.instructionsPath, "~/.config/opencode/AGENTS.md")
        XCTAssertEqual(agent.mcp?.serversKeyPath, ["mcp"])
        XCTAssertEqual(agent.mcp?.adapterId, MCPAdapterType.opencode.rawValue)
        XCTAssertFalse(OnboardingDependency.opencode.required)
    }

    func testOldOpenCodeDetectionReportsMinimumVersionWithoutRunningUpgrade() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(ShellResult(
            stdout: "/tmp/opencode\n", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false
        )))
        await shell.enqueue(.success(ShellResult(
            stdout: "1.18.21\n", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false
        )))
        let service = DefaultHarnessDetectionService(shell: shell, registry: DefaultHarnessRegistry(agentRegistry: DefaultAgentRegistry()))

        await service.checkHarness("opencode")

        let status = await service.status(for: "opencode")
        guard case .error(let message) = status else { return XCTFail("Old OpenCode must not report connected") }
        XCTAssertTrue(message.contains("1.18.31"))
        let path = await service.resolvedPath(for: "opencode")
        XCTAssertEqual(path, "/tmp/opencode")
        let calls = await shell.invocations
        XCTAssertEqual(calls.map(\.args), [["opencode"], ["--version"]])
    }

    func testRegistryUsesNativeXDGLocationAndExistingJSONConfig() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nativeDirectory = root.appendingPathComponent("xdg/opencode")
        try FileManager.default.createDirectory(at: nativeDirectory, withIntermediateDirectories: true)
        let nativeConfig = nativeDirectory.appendingPathComponent("opencode.json")
        try "{}".write(to: nativeConfig, atomically: true, encoding: .utf8)
        let registry = DefaultAgentRegistry(
            environment: ["XDG_CONFIG_HOME": root.appendingPathComponent("xdg").path],
            homeDirectory: root.appendingPathComponent("home")
        )
        let agent = try XCTUnwrap(registry.agent(for: "opencode"))
        XCTAssertEqual(agent.skillsDirectory, nativeDirectory.appendingPathComponent("skills").path)
        XCTAssertEqual(agent.instructionsPath, nativeDirectory.appendingPathComponent("AGENTS.md").path)
        XCTAssertEqual(agent.mcp?.configPath, nativeConfig.path)
    }

    func testNativeModelVariantsHaveAnExplicitDefaultAndNeverInheritForeignEffort() {
        let model = AgentModelOption(
            harnessId: .opencode, id: "provider/model", model: "provider/model", label: "Native model",
            supportedEffortOptions: [
                AgentHarnessOption(value: "deep", label: "Deep", description: "Native variant"),
                AgentHarnessOption(value: "default", label: "Native default", description: "An explicit native variant")
            ]
        )
        let options = [model]
        XCTAssertEqual(
            AgentModelOptionSelection.effortOptions(in: options, selectedModel: model.id).map(\.value),
            [AppSettings.openCodeDefaultEffort, "deep", "default"]
        )
        XCTAssertEqual(
            AgentModelOptionSelection.normalizedEffort("max", options: options, selectedModel: model.id), AppSettings.openCodeDefaultEffort
        )
        XCTAssertEqual(AgentModelOptionSelection.normalizedEffort("deep", options: options, selectedModel: model.id), "deep")
        XCTAssertEqual(AgentModelOptionSelection.normalizedEffort("default", options: options, selectedModel: model.id), "default")
        XCTAssertEqual(AgentModelOptionSelection.defaultEffortValue(in: options, selectedModel: model.id), AppSettings.openCodeDefaultEffort)
        let plain = AgentModelOption(harnessId: .opencode, id: "provider/plain", model: "provider/plain", label: "Plain")
        XCTAssertEqual(
            AgentModelOptionSelection.normalizedEffort("max", options: [plain], selectedModel: plain.id), AppSettings.openCodeDefaultEffort
        )
        XCTAssertEqual(AgentModelOptionSelection.normalizedEffort("deep", options: options, selectedModel: "offline/model"), "deep")
    }

    func testEveryNativeVariantIncludingReservedNamesRoundTripsWithoutBecomingConfiguredDefault() {
        let nativeVariants = [
            "default", "unknown-variant", "", " ", " deep ", "deep\n", AppSettings.openCodeDefaultEffort, AppSettings.inheritedSelectionValue,
            "alveary.opencode.variant:custom", "alveary.opencode.variant:alveary.opencode.variant:nested"
        ]
        let option = AgentModelOption(
            harnessId: .opencode, id: "provider/model", model: "provider/model", label: "Model",
            supportedEffortOptions: nativeVariants.map { AgentHarnessOption(value: $0, label: $0, description: "Native") }
        )
        let choices = AgentModelOptionSelection.effortOptions(in: [option], selectedModel: option.id)
        XCTAssertEqual(Set(choices.map(\.value)).count, nativeVariants.count + 1)
        XCTAssertNil(AppSettings.openCodeNativeEffort(stored: AppSettings.openCodeDefaultEffort))
        for variant in nativeVariants {
            let stored = AppSettings.openCodeStoredEffort(nativeVariant: variant)
            XCTAssertNotEqual(stored, AppSettings.inheritedSelectionValue)
            XCTAssertEqual(AppSettings.openCodeNativeEffort(stored: stored), variant)
            var settings = AppSettings()
            settings.defaultHarness = "opencode"
            settings.effort = stored
            XCTAssertEqual(AppSettings.openCodeNativeEffort(stored: settings.normalized().effort), variant)
            XCTAssertEqual(AgentModelOptionSelection.normalizedEffort(stored, options: [option], selectedModel: option.id), stored)
        }
        XCTAssertEqual(AppSettings.openCodeNativeEffort(stored: "unavailable"), "unavailable")
    }

    func testInstructionEnrollmentDoesNotWriteUntilUserLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DefaultGlobalAgentInstructionsService(agentRegistry: DefaultAgentRegistry(environment: [:]), homeDirectory: root)
        let nativeURL = root.appendingPathComponent(".config/opencode/AGENTS.md")
        let states = await service.linkStates()
        XCTAssertEqual(states["opencode"], .absent(path: nativeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))

        try await service.saveShared("Shared instructions\n")
        try await service.link(agentID: "opencode", copyingContents: false)

        XCTAssertEqual(try String(contentsOf: nativeURL, encoding: .utf8), "Shared instructions\n")
        let linked = await service.linkStates()
        XCTAssertEqual(linked["opencode"], .linked)
    }
}
