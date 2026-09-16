import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

private typealias AppOneShotPromptError = Alveary.AgentOneShotPromptError

@MainActor
final class AgentOneShotPromptServiceTests: XCTestCase {
    func testOpenCodeDefaultModelFailsBeforeTrustOrLaunch() async {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        let fixture = await makeFixture(settings: settings)
        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected a concrete utility model")
        } catch AppOneShotPromptError.failed(let message) {
            XCTAssertTrue(message.contains("require a concrete model"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let requests = await fixture.runner.requests()
        let setup = await fixture.harnessSetup.calls()
        let detection = await fixture.harnessDetection.checkCalls()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(setup.isEmpty)
        XCTAssertTrue(detection.isEmpty)
    }

    func testOpenCodeUtilityPreservesExactModelAndNativeVariant() async throws {
        for variant in [nil, " native "] as [String?] {
            var settings = AppSettings()
            settings.utilityHarness = "opencode"
            settings.utilityModel = "provider/model"
            settings.utilityEffort = variant.map(AppSettings.openCodeStoredEffort)
            let fixture = await makeFixture(settings: settings)

            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")

            let requests = await fixture.runner.requests()
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.harnessId, .opencode)
            XCTAssertEqual(request.model, "provider/model")
            XCTAssertEqual(request.effort, variant)
            XCTAssertEqual(request.toolPolicy, .readOnly)
            await assertNoRuntimeCalls(fixture.agentsManager)
        }
    }

    func testDisabledUtilityPinFailsBeforeTrustOrLaunch() async {
        var settings = AppSettings()
        settings.utilityHarness = "codex"
        settings.setHarness("codex", enabled: false)
        let fixture = await makeFixture(settings: settings)
        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected disabled utility harness")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("disabled"))
        }
        let requests = await fixture.runner.requests()
        let setup = await fixture.harnessSetup.calls()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(setup.isEmpty)
    }

    func testExplicitUtilityPinWorksWithOpenCodeThreadDefault() async throws {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "provider/text"
        settings.effort = "native-variant"
        settings.utilityHarness = "claude"
        settings.utilityModel = "sonnet"
        settings.utilityEffort = "high"
        let fixture = await makeFixture(settings: settings)
        _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
        let requests = await fixture.runner.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.harnessId, .claude)
        XCTAssertEqual(request.model, "sonnet")
        XCTAssertEqual(request.effort, "high")
    }

    func testGenerateRunsHarnessSpecificOneShotWithoutRuntimeCalls() async throws {
        var settings = AppSettings()
        settings.harnessConfigs["claude"] = HarnessCustomConfig(extraArgs: "--append-system-prompt 'Use terse output'")
        let fixture = await makeFixture(settings: settings, timeout: .seconds(7))

        let output = try await fixture.service.generate(prompt: "Generate subject", workingDirectory: "/tmp/project")

        XCTAssertEqual(output, "Generated subject")

        let requests = await fixture.runner.requests()
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.harnessId, .claude)
        XCTAssertEqual(request.workingDirectory.path, "/tmp/project")
        XCTAssertTrue(request.prompt.hasPrefix("Generate subject"))
        XCTAssertTrue(request.prompt.contains("AGENTS.md"))
        XCTAssertTrue(request.prompt.contains("CLAUDE.md"))
        XCTAssertEqual(
            request.arguments,
            ["--append-system-prompt", "Use terse output", "--disallowedTools", "RemoteTrigger"]
        )
        XCTAssertEqual(request.environment["PATH"], "/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(request.environment["ALVEARY_TEST"], "1")
        XCTAssertEqual(request.environment["CLAUDE_CODE_DISABLE_CRON"], "1")
        XCTAssertNil(request.model)
        XCTAssertEqual(request.effort, AppSettings.defaultEffortLevel)
        XCTAssertEqual(try XCTUnwrap(request.timeout), 7, accuracy: 0.001)
        XCTAssertEqual(request.toolPolicy, .readOnly)

        let harnessSetupCalls = await fixture.harnessSetup.calls()
        XCTAssertEqual(harnessSetupCalls, [
            MockHarnessSetupService.Call(harnessId: "claude", workingDirectory: "/tmp/project", autoTrust: false)
        ])
        let checkCalls = await fixture.harnessDetection.checkCalls()
        XCTAssertTrue(checkCalls.isEmpty)
        await assertNoRuntimeCalls(fixture.agentsManager)
    }

    func testGenerateMapsDefaultAndEmptyModelToNilAndKeepsCustomModel() async throws {
        var settings = AppSettings()
        settings.defaultModel = "  "
        var fixture = await makeFixture(settings: settings)
        _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
        let emptyModelRequests = await fixture.runner.requests()
        XCTAssertEqual(emptyModelRequests.count, 1)
        let emptyModelRequest = try XCTUnwrap(emptyModelRequests.first)
        XCTAssertNil(emptyModelRequest.model)

        settings.defaultModel = "claude-opus"
        fixture = await makeFixture(settings: settings)
        _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
        let customModelRequests = await fixture.runner.requests()
        let customModelRequest = customModelRequests.first
        XCTAssertEqual(customModelRequest?.model, "claude-opus")
    }

    func testGeneratePreparesProjectAndFailsWhenProjectIsNotTrusted() async {
        let fixture = await makeFixture(trusted: false)

        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected generation to fail")
        } catch AppOneShotPromptError.untrustedProject(let harnessId, let workingDirectory) {
            XCTAssertEqual(harnessId, "claude")
            XCTAssertEqual(workingDirectory, "/tmp/project")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let harnessSetupCalls = await fixture.harnessSetup.calls()
        XCTAssertEqual(harnessSetupCalls, [
            MockHarnessSetupService.Call(harnessId: "claude", workingDirectory: "/tmp/project", autoTrust: false)
        ])
        let requests = await fixture.runner.requests()
        let checkCalls = await fixture.harnessDetection.checkCalls()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(checkCalls.isEmpty)
        await assertNoRuntimeCalls(fixture.agentsManager)
    }

    func testGenerateUsesAutoTrustSettingDuringPrepare() async throws {
        var settings = AppSettings()
        settings.autoTrustProjects = true
        let fixture = await makeFixture(settings: settings, trusted: false)

        let output = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")

        XCTAssertEqual(output, "Generated subject")
        let harnessSetupCalls = await fixture.harnessSetup.calls()
        XCTAssertEqual(harnessSetupCalls, [
            MockHarnessSetupService.Call(harnessId: "claude", workingDirectory: "/tmp/project", autoTrust: true)
        ])
        let requests = await fixture.runner.requests()
        XCTAssertEqual(requests.count, 1)
        await assertNoRuntimeCalls(fixture.agentsManager)
    }

    func testGenerateFailsBeforeLaunchWhenHarnessExecutableIsMissing() async {
        let fixture = await makeFixture(detectedPath: nil, detectedPathAfterCheck: nil)

        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected generation to fail")
        } catch AppOneShotPromptError.failed(let message) {
            XCTAssertEqual(message, "claude CLI is not installed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let checkCalls = await fixture.harnessDetection.checkCalls()
        XCTAssertEqual(checkCalls, ["claude"])
        let requests = await fixture.runner.requests()
        XCTAssertTrue(requests.isEmpty)
        await assertNoRuntimeCalls(fixture.agentsManager)
    }

    func testGenerateFailsForInvalidHarnessExtraArgsBeforeLaunch() async {
        var settings = AppSettings()
        settings.harnessConfigs["claude"] = HarnessCustomConfig(extraArgs: "--bad 'unterminated")
        let fixture = await makeFixture(settings: settings)

        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected generation to fail")
        } catch AppOneShotPromptError.failed(let message) {
            XCTAssertTrue(message.contains("Invalid harness extra args"), message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await fixture.runner.requests()
        XCTAssertTrue(requests.isEmpty)
        await assertNoRuntimeCalls(fixture.agentsManager)
    }

    func testGenerateMapsRunnerErrors() async throws {
        try await assertRunnerFailure(
            .failure(.approvalRequired(harnessId: .claude, message: "approval")),
            expected: .approvalRequested
        )
        try await assertRunnerFailure(
            .failure(.promptRequired(harnessId: .claude, message: "question")),
            expected: .promptRequired
        )
        try await assertRunnerFailure(
            .failure(.emptyOutput(harnessId: .claude, stdout: "", stderr: "")),
            expected: .emptyOutput
        )
        try await assertRunnerFailure(
            .failure(.timedOut(harnessId: .claude, timeout: 1)),
            expected: .timedOut
        )
        try await assertRunnerFailure(
            .failure(.cancelled(harnessId: .claude)),
            expected: .cancelled
        )
        try await assertRunnerFailure(
            .cancellation,
            expected: .cancelled
        )
        try await assertRunnerFailure(
            .failure(.commandFailed(harnessId: .claude, exitCode: 42, stdout: "", stderr: "stderr diagnostic")),
            expectedMessageContaining: "stderr diagnostic"
        )
        try await assertRunnerFailure(
            .failure(.unavailableModel(harnessId: .claude, message: "not available")),
            expectedMessageContaining: "model is unavailable"
        )
    }
}

private extension AgentOneShotPromptServiceTests {
    struct Fixture {
        let service: DefaultAgentOneShotPromptService
        let runner: MockAgentOneShotPromptRunner
        let agentsManager: MockAgentsManager
        let harnessSetup: MockHarnessSetupService
        let harnessDetection: RecordingHarnessDetectionService
    }

    func makeFixture(
        settings: AppSettings = AppSettings(),
        trusted: Bool = true,
        timeout: Duration = .seconds(1),
        detectedPath: String? = "/opt/homebrew/bin/claude",
        detectedPathAfterCheck: String? = nil,
        runnerOutcome: MockAgentOneShotPromptRunner.Outcome = .success(.init(
            harnessId: .claude,
            text: " Generated subject ",
            stdout: "{}\n",
            stderr: ""
        ))
    ) async -> Fixture {
        let agentsManager = MockAgentsManager(
            isRunning: false,
            sendError: nil,
            reconfigureError: nil,
            approvalError: nil
        )
        let harnessSetup = MockHarnessSetupService()
        await harnessSetup.setTrustedProject("/tmp/project", isTrusted: trusted)
        let harnessDetection = RecordingHarnessDetectionService(
            resolvedPath: detectedPath,
            resolvedPathAfterCheck: detectedPathAfterCheck
        )
        let runner = MockAgentOneShotPromptRunner(outcome: runnerOutcome)
        let service = DefaultAgentOneShotPromptService(
            promptRunner: runner,
            settingsService: InMemorySettingsService(current: settings),
            harnessSetup: harnessSetup,
            harnessDetection: harnessDetection,
            environmentBuilder: FixedEnvironmentBuilder(environment: [
                "PATH": "/usr/bin",
                "ALVEARY_TEST": "1"
            ]),
            timeout: timeout
        )

        return Fixture(
            service: service,
            runner: runner,
            agentsManager: agentsManager,
            harnessSetup: harnessSetup,
            harnessDetection: harnessDetection
        )
    }

    func assertRunnerFailure(
        _ outcome: MockAgentOneShotPromptRunner.Outcome,
        expected: AppOneShotPromptError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = await makeFixture(runnerOutcome: outcome)

        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected generation to fail", file: file, line: line)
        } catch let error as AppOneShotPromptError {
            XCTAssertEqual(error, expected, file: file, line: line)
            let requests = await fixture.runner.requests()
            XCTAssertEqual(requests.count, 1, file: file, line: line)
            await assertNoRuntimeCalls(fixture.agentsManager, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func assertRunnerFailure(
        _ outcome: MockAgentOneShotPromptRunner.Outcome,
        expectedMessageContaining message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = await makeFixture(runnerOutcome: outcome)

        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected generation to fail", file: file, line: line)
        } catch AppOneShotPromptError.failed(let failureMessage) {
            XCTAssertTrue(failureMessage.contains(message), failureMessage, file: file, line: line)
            let requests = await fixture.runner.requests()
            XCTAssertEqual(requests.count, 1, file: file, line: line)
            await assertNoRuntimeCalls(fixture.agentsManager, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func assertNoRuntimeCalls(
        _ agentsManager: MockAgentsManager,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let spawnCalls = await agentsManager.spawnCalls()
        let subscribeCalls = await agentsManager.subscribeCallsList()
        let sentMessages = await agentsManager.sentMessages()
        let destroyCalls = await agentsManager.destroyCalls()
        XCTAssertTrue(spawnCalls.isEmpty, file: file, line: line)
        XCTAssertTrue(subscribeCalls.isEmpty, file: file, line: line)
        XCTAssertTrue(sentMessages.isEmpty, file: file, line: line)
        XCTAssertTrue(destroyCalls.isEmpty, file: file, line: line)
    }
}

private actor MockAgentOneShotPromptRunner: AgentCLIKit.AgentOneShotPromptRunning {
    enum Outcome: Sendable {
        case success(AgentCLIKit.AgentOneShotPromptResult)
        case failure(AgentCLIKit.AgentOneShotPromptError)
        case cancellation
    }

    private let outcome: Outcome
    private var recordedRequests: [AgentCLIKit.AgentOneShotPromptRequest] = []

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func generate(_ request: AgentCLIKit.AgentOneShotPromptRequest) async throws -> AgentCLIKit.AgentOneShotPromptResult {
        recordedRequests.append(request)
        switch outcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        case .cancellation:
            throw CancellationError()
        }
    }

    func requests() -> [AgentCLIKit.AgentOneShotPromptRequest] {
        recordedRequests
    }
}

private actor RecordingHarnessDetectionService: HarnessDetectionService {
    private var resolvedPath: String?
    private let resolvedPathAfterCheck: String?
    private var recordedCheckCalls: [String] = []

    init(resolvedPath: String?, resolvedPathAfterCheck: String?) {
        self.resolvedPath = resolvedPath
        self.resolvedPathAfterCheck = resolvedPathAfterCheck
    }

    func resolvedPath(for harnessId: String) -> String? {
        resolvedPath
    }

    func status(for harnessId: String) -> HarnessStatus {
        if let resolvedPath {
            return .connected(path: resolvedPath, version: "test")
        }
        return .missing
    }

    func checkAllHarnesses() async {}

    func checkHarness(_ harnessId: String) async {
        recordedCheckCalls.append(harnessId)
        if resolvedPath == nil {
            resolvedPath = resolvedPathAfterCheck
        }
    }

    func checkCalls() -> [String] {
        recordedCheckCalls
    }
}

private struct FixedEnvironmentBuilder: AgentEnvironmentBuilder {
    let environment: [String: String]

    func buildEnvironment(harnessEnv: [String: String]?) -> [String: String] {
        var values = environment
        for (key, value) in harnessEnv ?? [:] {
            values[key] = value
        }
        return values
    }
}
