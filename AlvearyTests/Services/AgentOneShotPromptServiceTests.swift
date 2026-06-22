import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

private typealias AppOneShotPromptError = Alveary.AgentOneShotPromptError

@MainActor
final class AgentOneShotPromptServiceTests: XCTestCase {
    func testGenerateRunsProviderSpecificOneShotWithoutRuntimeCalls() async throws {
        var settings = AppSettings()
        settings.providerConfigs["claude"] = ProviderCustomConfig(extraArgs: "--append-system-prompt 'Use terse output'")
        let fixture = await makeFixture(settings: settings, timeout: .seconds(7))

        let output = try await fixture.service.generate(prompt: "Generate subject", workingDirectory: "/tmp/project")

        XCTAssertEqual(output, "Generated subject")

        let requests = await fixture.runner.requests()
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.providerId, .claude)
        XCTAssertEqual(request.workingDirectory.path, "/tmp/project")
        XCTAssertTrue(request.prompt.hasPrefix("Generate subject"))
        XCTAssertTrue(request.prompt.contains("AGENTS.md"))
        XCTAssertTrue(request.prompt.contains("CLAUDE.md"))
        XCTAssertEqual(request.arguments, ["--append-system-prompt", "Use terse output"])
        XCTAssertEqual(request.environment["PATH"], "/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(request.environment["ALVEARY_TEST"], "1")
        XCTAssertNil(request.model)
        XCTAssertEqual(request.effort, AppSettings.defaultEffortLevel)
        XCTAssertEqual(try XCTUnwrap(request.timeout), 7, accuracy: 0.001)
        XCTAssertEqual(request.toolPolicy, .readOnly)

        let providerSetupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(providerSetupCalls, [
            MockProviderSetupService.Call(providerId: "claude", workingDirectory: "/tmp/project", autoTrust: false)
        ])
        let checkCalls = await fixture.providerDetection.checkCalls()
        XCTAssertTrue(checkCalls.isEmpty)
        await assertNoRuntimeCalls(fixture.agentsManager)
    }

    func testGenerateMapsDefaultAndEmptyModelToNilAndKeepsCustomModel() async throws {
        var settings = AppSettings()
        settings.defaultModel = "  "
        var fixture = await makeFixture(settings: settings)
        _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
        let emptyModelRequests = await fixture.runner.requests()
        let emptyModelRequest = emptyModelRequests.first
        XCTAssertNil(emptyModelRequest?.model)

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
        } catch AppOneShotPromptError.untrustedProject(let providerId, let workingDirectory) {
            XCTAssertEqual(providerId, "claude")
            XCTAssertEqual(workingDirectory, "/tmp/project")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let providerSetupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(providerSetupCalls, [
            MockProviderSetupService.Call(providerId: "claude", workingDirectory: "/tmp/project", autoTrust: false)
        ])
        let requests = await fixture.runner.requests()
        let checkCalls = await fixture.providerDetection.checkCalls()
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
        let providerSetupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(providerSetupCalls, [
            MockProviderSetupService.Call(providerId: "claude", workingDirectory: "/tmp/project", autoTrust: true)
        ])
        let requests = await fixture.runner.requests()
        XCTAssertEqual(requests.count, 1)
        await assertNoRuntimeCalls(fixture.agentsManager)
    }

    func testGenerateFailsBeforeLaunchWhenProviderExecutableIsMissing() async {
        let fixture = await makeFixture(detectedPath: nil, detectedPathAfterCheck: nil)

        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected generation to fail")
        } catch AppOneShotPromptError.failed(let message) {
            XCTAssertEqual(message, "claude CLI is not installed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let checkCalls = await fixture.providerDetection.checkCalls()
        XCTAssertEqual(checkCalls, ["claude"])
        let requests = await fixture.runner.requests()
        XCTAssertTrue(requests.isEmpty)
        await assertNoRuntimeCalls(fixture.agentsManager)
    }

    func testGenerateFailsForInvalidProviderExtraArgsBeforeLaunch() async {
        var settings = AppSettings()
        settings.providerConfigs["claude"] = ProviderCustomConfig(extraArgs: "--bad 'unterminated")
        let fixture = await makeFixture(settings: settings)

        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected generation to fail")
        } catch AppOneShotPromptError.failed(let message) {
            XCTAssertTrue(message.contains("Invalid provider extra args"), message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await fixture.runner.requests()
        XCTAssertTrue(requests.isEmpty)
        await assertNoRuntimeCalls(fixture.agentsManager)
    }

    func testGenerateMapsRunnerErrors() async throws {
        try await assertRunnerFailure(
            .failure(.approvalRequired(providerId: .claude, message: "approval")),
            expected: .approvalRequested
        )
        try await assertRunnerFailure(
            .failure(.promptRequired(providerId: .claude, message: "question")),
            expected: .promptRequired
        )
        try await assertRunnerFailure(
            .failure(.emptyOutput(providerId: .claude, stdout: "", stderr: "")),
            expected: .emptyOutput
        )
        try await assertRunnerFailure(
            .failure(.timedOut(providerId: .claude, timeout: 1)),
            expected: .timedOut
        )
        try await assertRunnerFailure(
            .failure(.cancelled(providerId: .claude)),
            expected: .cancelled
        )
        try await assertRunnerFailure(
            .cancellation,
            expected: .cancelled
        )
        try await assertRunnerFailure(
            .failure(.commandFailed(providerId: .claude, exitCode: 42, stdout: "", stderr: "stderr diagnostic")),
            expectedMessageContaining: "stderr diagnostic"
        )
        try await assertRunnerFailure(
            .failure(.unavailableModel(providerId: .claude, message: "not available")),
            expectedMessageContaining: "model is unavailable"
        )
    }
}

private extension AgentOneShotPromptServiceTests {
    struct Fixture {
        let service: DefaultAgentOneShotPromptService
        let runner: MockAgentOneShotPromptRunner
        let agentsManager: MockAgentsManager
        let providerSetup: MockProviderSetupService
        let providerDetection: RecordingProviderDetectionService
    }

    func makeFixture(
        settings: AppSettings = AppSettings(),
        trusted: Bool = true,
        timeout: Duration = .seconds(1),
        detectedPath: String? = "/opt/homebrew/bin/claude",
        detectedPathAfterCheck: String? = nil,
        runnerOutcome: MockAgentOneShotPromptRunner.Outcome = .success(.init(
            providerId: .claude,
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
        let providerSetup = MockProviderSetupService()
        await providerSetup.setTrustedProject("/tmp/project", isTrusted: trusted)
        let providerDetection = RecordingProviderDetectionService(
            resolvedPath: detectedPath,
            resolvedPathAfterCheck: detectedPathAfterCheck
        )
        let runner = MockAgentOneShotPromptRunner(outcome: runnerOutcome)
        let service = DefaultAgentOneShotPromptService(
            promptRunner: runner,
            settingsService: InMemorySettingsService(current: settings),
            providerSetup: providerSetup,
            providerDetection: providerDetection,
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
            providerSetup: providerSetup,
            providerDetection: providerDetection
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

private actor RecordingProviderDetectionService: ProviderDetectionService {
    private var resolvedPath: String?
    private let resolvedPathAfterCheck: String?
    private var recordedCheckCalls: [String] = []

    init(resolvedPath: String?, resolvedPathAfterCheck: String?) {
        self.resolvedPath = resolvedPath
        self.resolvedPathAfterCheck = resolvedPathAfterCheck
    }

    func resolvedPath(for providerId: String) -> String? {
        resolvedPath
    }

    func status(for providerId: String) -> ProviderStatus {
        if let resolvedPath {
            return .connected(path: resolvedPath, version: "test")
        }
        return .missing
    }

    func checkAllProviders() async {}

    func checkProvider(_ providerId: String) async {
        recordedCheckCalls.append(providerId)
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

    func buildEnvironment(providerEnv: [String: String]?) -> [String: String] {
        var values = environment
        for (key, value) in providerEnv ?? [:] {
            values[key] = value
        }
        return values
    }
}
