import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testOpenCodeCompletionBeforeSubmissionReturnsPreservesIdleStatus() async throws {
        let gate = OpenCodeTerminalSubmissionGate()
        let fixture = makeAgentCLIKitFixture(
            adapter: OpenCodeTerminalSubmissionAdapter(gate: gate), detectedPath: "/bin/sleep", basePath: "/usr/bin:/bin"
        )
        let identifier = "opencode-inline-completion"
        try await fixture.manager.spawn(id: identifier, config: spawnConfig(harnessId: "opencode", workingDirectory: "/tmp"))
        do {
            let send = Task { try await fixture.manager.sendMessage("Quick prompt", conversationId: identifier) }
            await gate.waitUntilSubmitted()
            try await waitUntil("OpenCode terminal before submission response") {
                let status = await fixture.runtime.status(conversationId: .init(rawValue: identifier))
                return status?.isTurnActive == false && fixture.manager.status(for: identifier) == .idle
            }
            await gate.releaseResponse()
            try await send.value
            XCTAssertEqual(fixture.manager.status(for: identifier), .idle)
        } catch {
            await gate.releaseResponse()
            await fixture.manager.kill(conversationId: identifier)
            throw error
        }
        await fixture.manager.kill(conversationId: identifier)
    }

    func testOpenCodeLostSubmissionResponseDoesNotBecomeAutomaticallyRetryableStdinError() async throws {
        let gate = OpenCodeSubmissionGate()
        let fixture = makeAgentCLIKitFixture(
            adapter: OpenCodeSubmissionAdapter(gate: gate), detectedPath: "/bin/sleep", basePath: "/usr/bin:/bin"
        )
        let identifier = "opencode-ambiguous-submission"
        try await fixture.manager.spawn(id: identifier, config: spawnConfig(harnessId: "opencode", workingDirectory: "/tmp"))
        let task = Task {
            try await fixture.manager.sendMessage("Run once", conversationId: identifier)
        }
        await gate.waitUntilSubmitted()
        await fixture.runtime.kill(conversationId: .init(rawValue: identifier))
        await gate.loseResponse()
        do {
            try await task.value
            XCTFail("Expected original ambiguous-submission error")
        } catch {
            XCTAssertEqual(error as? OpenCodeSubmissionFailure, .responseLost)
        }
        await fixture.manager.kill(conversationId: identifier)
    }
}

private enum OpenCodeSubmissionFailure: Error, Equatable { case responseLost }

private actor OpenCodeSubmissionGate {
    private var submitted = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<Void, Never>?

    func submit() async throws {
        submitted = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { responseWaiter = $0 }
        throw OpenCodeSubmissionFailure.responseLost
    }

    func waitUntilSubmitted() async {
        if submitted { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func loseResponse() {
        responseWaiter?.resume()
        responseWaiter = nil
    }
}

private struct OpenCodeSubmissionAdapter: AgentCLIKit.AgentHarnessAdapter {
    let gate: OpenCodeSubmissionGate
    let definition = OpenCodeHarnessDefinition.definition

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig, resumedSession: AgentSessionRecord?
    ) async throws -> AgentLaunchConfiguration {
        AgentLaunchConfiguration(executable: "/bin/sleep", arguments: ["60"])
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] { [] }
    func encodeInput(_ input: AgentInput) async throws -> Data {
        try await gate.submit()
        return Data()
    }
}

private actor OpenCodeTerminalSubmissionGate {
    nonisolated let stream: AsyncStream<AgentHarnessRuntimeEvent>
    private let continuation: AsyncStream<AgentHarnessRuntimeEvent>.Continuation
    private var submitted = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<Void, Never>?

    init() {
        let pair = AsyncStream<AgentHarnessRuntimeEvent>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func submit() async {
        continuation.yield(.init(event: .usage(.init(
            model: nil, inputTokens: nil, outputTokens: nil, stopReason: "end_turn", isTerminal: true
        ))))
        continuation.yield(.init(event: .activity(.init(state: .idle))))
        submitted = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { responseWaiter = $0 }
    }

    func waitUntilSubmitted() async {
        if submitted { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func releaseResponse() {
        responseWaiter?.resume()
        responseWaiter = nil
    }
}

private struct OpenCodeTerminalSubmissionAdapter: AgentCLIKit.AgentHarnessAdapter {
    let gate: OpenCodeTerminalSubmissionGate
    let definition = OpenCodeHarnessDefinition.definition

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig, resumedSession: AgentSessionRecord?
    ) async throws -> AgentLaunchConfiguration {
        AgentLaunchConfiguration(executable: "/bin/sleep", arguments: ["60"])
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] { [] }
    func runtimeEvents(context: AgentHarnessRuntimeContext) async -> AsyncStream<AgentHarnessRuntimeEvent> { gate.stream }
    func encodeInput(_ input: AgentInput) async throws -> Data {
        await gate.submit()
        return Data()
    }
}
