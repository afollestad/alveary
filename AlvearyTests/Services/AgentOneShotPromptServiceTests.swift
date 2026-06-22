import XCTest

@testable import Alveary

@MainActor
final class AgentOneShotPromptServiceTests: XCTestCase {
    func testGenerateUsesUniqueSyntheticIdsConfiguresRuntimeAndSendsHiddenPrompt() async throws {
        let fixture = await makeFixture()

        let first = Task { try await fixture.service.generate(prompt: "Generate first", workingDirectory: "/tmp/project") }
        try await waitForSentMessage(in: fixture.agentsManager)
        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: " First subject ", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(terminalTokens())
        let firstOutput = try await first.value

        let second = Task { try await fixture.service.generate(prompt: "Generate second", workingDirectory: "/tmp/project") }
        try await waitForSentMessage(in: fixture.agentsManager, count: 2)
        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Second subject", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(terminalTokens())
        let secondOutput = try await second.value

        XCTAssertEqual(firstOutput, "First subject")
        XCTAssertEqual(secondOutput, "Second subject")

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 2)
        XCTAssertTrue(spawnCalls.allSatisfy { $0.id.hasPrefix(DefaultAgentOneShotPromptService.syntheticConversationIDPrefix) })
        XCTAssertNotEqual(spawnCalls[0].id, spawnCalls[1].id)
        XCTAssertEqual(spawnCalls[0].config.providerId, "claude")
        XCTAssertEqual(spawnCalls[0].config.workingDirectory, "/tmp/project")
        XCTAssertEqual(spawnCalls[0].config.permissionMode, "default")
        XCTAssertEqual(spawnCalls[0].config.planModeEnabled, false)
        XCTAssertNil(spawnCalls[0].config.model)
        XCTAssertEqual(spawnCalls[0].config.effort, AppSettings.defaultEffortLevel)
        XCTAssertEqual(spawnCalls[0].config.speedMode, .standard)
        XCTAssertNil(spawnCalls[0].config.initialPrompt)
        XCTAssertFalse(spawnCalls[0].forkSession)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sendVisibilities = await fixture.agentsManager.sendVisibilities()
        let subscribeCalls = await fixture.agentsManager.subscribeCallsList()
        let destroyCalls = await fixture.agentsManager.destroyCalls()

        XCTAssertEqual(sentMessages, ["Generate first", "Generate second"])
        XCTAssertEqual(sendVisibilities, [.hidden, .hidden])
        XCTAssertEqual(
            subscribeCalls,
            spawnCalls.map { MockAgentsManager.SubscribeCall(conversationId: $0.id, afterIndex: 0) }
        )
        XCTAssertEqual(destroyCalls, spawnCalls.map(\.id))
    }

    func testGenerateMapsDefaultAndEmptyModelToNilAndKeepsCustomModel() async throws {
        var settings = AppSettings()
        settings.defaultModel = "  "
        var fixture = await makeFixture(settings: settings)
        _ = try await completeSuccessfulGeneration(fixture: fixture)
        let emptyModelSpawn = await fixture.agentsManager.spawnCalls().first
        XCTAssertNil(emptyModelSpawn?.config.model)

        settings.defaultModel = "claude-opus"
        fixture = await makeFixture(settings: settings)
        _ = try await completeSuccessfulGeneration(fixture: fixture)
        let customModelSpawn = await fixture.agentsManager.spawnCalls().first
        XCTAssertEqual(customModelSpawn?.config.model, "claude-opus")
    }

    func testGeneratePreparesProjectAndFailsWhenProjectIsNotTrusted() async {
        let fixture = await makeFixture(trusted: false)

        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected generation to fail")
        } catch AgentOneShotPromptError.untrustedProject(let providerId, let workingDirectory) {
            XCTAssertEqual(providerId, "claude")
            XCTAssertEqual(workingDirectory, "/tmp/project")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let providerSetupCalls = await fixture.providerSetup.calls()
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let destroyCalls = await fixture.agentsManager.destroyCalls()

        XCTAssertEqual(providerSetupCalls, [
            MockProviderSetupService.Call(providerId: "claude", workingDirectory: "/tmp/project", autoTrust: false)
        ])
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertEqual(destroyCalls.count, 1)
    }

    func testGenerateUsesAutoTrustSettingDuringPrepare() async throws {
        var settings = AppSettings()
        settings.autoTrustProjects = true
        let fixture = await makeFixture(settings: settings, trusted: false)

        let output = try await completeSuccessfulGeneration(fixture: fixture)

        XCTAssertEqual(output, "Generated subject")
        let providerSetupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(providerSetupCalls, [
            MockProviderSetupService.Call(providerId: "claude", workingDirectory: "/tmp/project", autoTrust: true)
        ])
    }

    func testGenerateIgnoresReplayedSetupEventsBeforeTurnOutput() async throws {
        let fixture = await makeFixture()
        let task = Task { try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project") }

        try await waitForSentMessage(in: fixture.agentsManager)
        await fixture.agentsManager.yieldSubscriptionEvent(.sessionInit(sessionId: "session"))
        await fixture.agentsManager.yieldSubscriptionEvent(.permissionModeChanged("default"))
        await fixture.agentsManager.yieldSubscriptionEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .unknown))
        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Generated subject", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(terminalTokens())

        let output = try await task.value
        XCTAssertEqual(output, "Generated subject")
    }

    func testGenerateAcceptsFullAssistantMessageOutput() async throws {
        let fixture = await makeFixture()
        let task = Task { try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project") }

        try await waitForSentMessage(in: fixture.agentsManager)
        await fixture.agentsManager.yieldSubscriptionEvent(.message(role: "assistant", content: "Generated from message", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))

        let output = try await task.value
        XCTAssertEqual(output, "Generated from message")
    }

    func testGenerateFailsOnProviderErrorApprovalAndInterruptedRuntime() async throws {
        try await assertGenerationFails(
            events: [.error(message: "Provider failed")],
            expected: .failed("Provider failed")
        )
        try await assertGenerationFails(
            events: [.toolApprovalRequested(ToolApprovalRequest(
                sessionId: "session",
                toolUseId: "approval",
                toolName: "Edit",
                toolInput: ""
            ))],
            expected: .approvalRequested
        )
        try await assertGenerationFails(
            events: [
                .runtimeActivity(state: .active, turnId: "turn", outcome: .unknown),
                .runtimeActivity(state: .idle, turnId: "turn", outcome: .interrupted)
            ],
            expected: .interrupted
        )
    }

    func testGenerateFailsOnInterruptedTerminalTokens() async throws {
        try await assertGenerationFails(
            events: [
                .messageChunk(text: "Partial subject", parentToolUseId: nil),
                interruptedTokens()
            ],
            expected: .interrupted
        )
    }

    func testGenerateFailsOnInterruptedStopEvent() async throws {
        try await assertGenerationFails(
            events: [
                .messageChunk(text: "Partial subject", parentToolUseId: nil),
                .stop(message: ConversationInterruption.displayMessage)
            ],
            expected: .interrupted
        )
    }

    func testGenerateFailsOnEmptyOutput() async throws {
        try await assertGenerationFails(
            events: [.runtimeActivity(state: .active, turnId: "turn", outcome: .unknown),
                     .runtimeActivity(state: .idle, turnId: "turn", outcome: .completed)],
            expected: .emptyOutput
        )
    }

    func testGenerateTimesOutAndCleansRuntime() async {
        let fixture = await makeFixture(timeout: .milliseconds(10))

        do {
            _ = try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project")
            XCTFail("Expected generation to time out")
        } catch AgentOneShotPromptError.timedOut {
            let destroyCalls = await fixture.agentsManager.destroyCalls()
            XCTAssertEqual(destroyCalls.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateCancellationCleansRuntime() async throws {
        let fixture = await makeFixture()
        let task = Task { try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project") }

        try await waitForSentMessage(in: fixture.agentsManager)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected generation to be cancelled")
        } catch AgentOneShotPromptError.cancelled {
            let destroyCalls = await fixture.agentsManager.destroyCalls()
            XCTAssertEqual(destroyCalls.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCleanupErrorPreservesPrimaryGenerationError() async throws {
        let fixture = await makeFixture()
        await fixture.agentsManager.enqueueDestroyError(MockAgentsManager.MockError.stdinClosed)
        let task = Task { try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project") }

        try await waitForSentMessage(in: fixture.agentsManager)
        await fixture.agentsManager.yieldSubscriptionEvent(.error(message: "Provider failed"))

        do {
            _ = try await task.value
            XCTFail("Expected provider error")
        } catch AgentOneShotPromptError.failed(let message) {
            XCTAssertEqual(message, "Provider failed")
            let destroyCalls = await fixture.agentsManager.destroyCalls()
            XCTAssertEqual(destroyCalls.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private extension AgentOneShotPromptServiceTests {
    struct Fixture {
        let service: DefaultAgentOneShotPromptService
        let agentsManager: MockAgentsManager
        let providerSetup: MockProviderSetupService
    }

    func makeFixture(
        settings: AppSettings = AppSettings(),
        trusted: Bool = true,
        timeout: Duration = .seconds(1)
    ) async -> Fixture {
        let agentsManager = MockAgentsManager(
            isRunning: false,
            sendError: nil,
            reconfigureError: nil,
            approvalError: nil
        )
        let providerSetup = MockProviderSetupService()
        await providerSetup.setTrustedProject("/tmp/project", isTrusted: trusted)
        await agentsManager.enableSubscription()

        let service = DefaultAgentOneShotPromptService(
            agentsManager: agentsManager,
            settingsService: InMemorySettingsService(current: settings),
            providerSetup: providerSetup,
            timeout: timeout
        )

        return Fixture(service: service, agentsManager: agentsManager, providerSetup: providerSetup)
    }

    func completeSuccessfulGeneration(fixture: Fixture) async throws -> String {
        let task = Task { try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project") }
        try await waitForSentMessage(in: fixture.agentsManager)
        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Generated subject", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(terminalTokens())
        return try await task.value
    }

    func assertGenerationFails(
        events: [ConversationEvent],
        expected: AgentOneShotPromptError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = await makeFixture()
        let task = Task { try await fixture.service.generate(prompt: "Generate", workingDirectory: "/tmp/project") }

        try await waitForSentMessage(in: fixture.agentsManager)
        for event in events {
            await fixture.agentsManager.yieldSubscriptionEvent(event)
        }

        do {
            _ = try await task.value
            XCTFail("Expected generation to fail", file: file, line: line)
        } catch let error as AgentOneShotPromptError {
            let destroyCalls = await fixture.agentsManager.destroyCalls()
            XCTAssertEqual(error, expected, file: file, line: line)
            XCTAssertEqual(destroyCalls.count, 1, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func waitForSentMessage(in agentsManager: MockAgentsManager, count: Int = 1) async throws {
        for _ in 0..<100 {
            if await agentsManager.sentMessages().count >= count {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for hidden send")
    }

    func terminalTokens() -> ConversationEvent {
        .tokens(
            input: 0,
            output: 0,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 0,
            costUsd: nil,
            permissionDenials: [],
            isTerminal: true
        )
    }

    func interruptedTokens() -> ConversationEvent {
        .tokens(
            input: 0,
            output: 0,
            cacheRead: 0,
            isError: true,
            stopReason: ConversationInterruption.requestInterruptedByUserReason,
            durationMs: 0,
            costUsd: nil,
            permissionDenials: [],
            isTerminal: true
        )
    }
}
