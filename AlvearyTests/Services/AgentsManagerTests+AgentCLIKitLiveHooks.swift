import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitLiveHookDecisionProviderPublishesAndResolvesRequest() async throws {
        let provider = AgentCLIKitLiveHookDecisionProvider(sleep: { _ in })
        let recorder = LiveHookRequestRecorder()
        await provider.setDeferredToolRequestHandler { request in
            await recorder.append(request)
        }
        let hookRequest = AgentCLIKit.ClaudeHookRequest(
            bearerToken: "token",
            hookName: "PreToolUse",
            conversationId: "conversation",
            payload: .object([
                "session_id": .string("session-1"),
                "tool_name": .string("ExitPlanMode"),
                "tool_input": .object(["plan": .string("Ship it")])
            ])
        )

        let decisionTask = Task {
            await provider.decision(for: hookRequest, interactionId: "tool-1")
        }
        try await waitUntil("expected live hook request to publish") {
            (await recorder.requests()).isEmpty == false
        }

        let publishedRequests = await recorder.requests()
        let published = try XCTUnwrap(publishedRequests.first)
        let didResolve = await provider.resolve(
            ClaudeToolApprovalResolution(decision: .allow),
            for: ClaudeToolApprovalKey(sessionId: "session-1", toolUseId: "tool-1")
        )
        let decision = await decisionTask.value

        XCTAssertEqual(published.conversationId, "conversation")
        XCTAssertEqual(published.request.toolName, "ExitPlanMode")
        XCTAssertEqual(published.request.planMarkdownFallback, "Ship it")
        XCTAssertTrue(didResolve)
        XCTAssertEqual(decision.approval, .allow)
        XCTAssertEqual(decision.updatedInput, .object(["plan": .string("Ship it")]))
    }

    func testAgentCLIKitLiveHookDecisionProviderDelaysPublishForToolCallOrdering() async throws {
        let sleepRecorder = LiveHookSleepRecorder()
        let provider = AgentCLIKitLiveHookDecisionProvider(
            publishDelay: .milliseconds(50),
            sleep: { duration in
                await sleepRecorder.record(duration)
            }
        )
        let recorder = LiveHookRequestRecorder()
        await provider.setDeferredToolRequestHandler { request in
            await recorder.append(request)
        }
        let hookRequest = AgentCLIKit.ClaudeHookRequest(
            bearerToken: "token",
            hookName: "PreToolUse",
            conversationId: "conversation",
            payload: .object([
                "session_id": .string("session-1"),
                "tool_name": .string("Bash"),
                "tool_input": .object(["command": .string("pwd")])
            ])
        )

        let decisionTask = Task {
            await provider.decision(for: hookRequest, interactionId: "tool-1")
        }
        try await waitUntil("expected live hook publish delay to be used") {
            !(await sleepRecorder.durations()).isEmpty
        }
        try await waitUntil("expected delayed live hook request to publish") {
            (await recorder.requests()).isEmpty == false
        }

        let durations = await sleepRecorder.durations()
        let didResolve = await provider.resolve(
            ClaudeToolApprovalResolution(decision: .allow),
            for: ClaudeToolApprovalKey(sessionId: "session-1", toolUseId: "tool-1")
        )
        let decision = await decisionTask.value

        XCTAssertEqual(durations.first, .milliseconds(50))
        XCTAssertTrue(didResolve)
        XCTAssertEqual(decision.approval, .allow)
    }

    func testAgentCLIKitLiveHookDecisionProviderResolvesFutureSiblingWithoutPublishing() async throws {
        let provider = AgentCLIKitLiveHookDecisionProvider(sleep: { _ in })
        let recorder = LiveHookRequestRecorder()
        await provider.setDeferredToolRequestHandler { request in
            await recorder.append(request)
        }
        let key = ClaudeToolApprovalKey(sessionId: "session-1", toolUseId: "tool-2")
        await provider.recordFutureResolution(
            ClaudeToolApprovalResolution(decision: .allow),
            for: key
        )
        let hookRequest = AgentCLIKit.ClaudeHookRequest(
            bearerToken: "token",
            hookName: "PreToolUse",
            conversationId: "conversation",
            payload: .object([
                "session_id": .string("session-1"),
                "tool_name": .string("Bash"),
                "tool_input": .object(["command": .string("pwd")])
            ])
        )

        let decision = await provider.decision(for: hookRequest, interactionId: "tool-2")
        let publishedRequests = await recorder.requests()

        XCTAssertEqual(decision.approval, .allow)
        XCTAssertTrue(publishedRequests.isEmpty)
    }

    func testAgentCLIKitLiveHookDecisionProviderDiscardsFutureSiblingForConversation() async throws {
        let provider = AgentCLIKitLiveHookDecisionProvider(sleep: { _ in })
        let recorder = LiveHookRequestRecorder()
        await provider.setDeferredToolRequestHandler { request in
            await recorder.append(request)
        }
        let key = ClaudeToolApprovalKey(sessionId: "session-1", toolUseId: "tool-2")
        await provider.recordFutureResolution(
            ClaudeToolApprovalResolution(decision: .allow),
            for: key,
            conversationId: "conversation"
        )
        await provider.discardDecisions(conversationId: "conversation")

        let decisionTask = Task {
            await provider.decision(
                for: liveHookRequest(conversationId: "conversation", toolUseId: "tool-2"),
                interactionId: "tool-2"
            )
        }
        defer { decisionTask.cancel() }
        try await waitUntil("expected discarded future hook to publish") {
            (await recorder.requests()).isEmpty == false
        }
        let didResolve = await provider.resolve(
            ClaudeToolApprovalResolution(decision: .deny),
            for: key
        )
        let decision = await decisionTask.value

        XCTAssertTrue(didResolve)
        XCTAssertEqual(decision.approval, .deny)
    }

    func testAgentCLIKitLiveHookDecisionProviderResolvesPendingFutureSiblingWithoutPublishing() async throws {
        let sleepGate = LiveHookSleepGate()
        let provider = AgentCLIKitLiveHookDecisionProvider(sleep: { duration in
            try await sleepGate.sleep(duration)
        })
        let recorder = LiveHookRequestRecorder()
        await provider.setDeferredToolRequestHandler { request in
            await recorder.append(request)
        }
        let key = ClaudeToolApprovalKey(sessionId: "session-1", toolUseId: "tool-2")

        let decisionTask = Task {
            await provider.decision(
                for: liveHookRequest(conversationId: "conversation", toolUseId: "tool-2"),
                interactionId: "tool-2"
            )
        }
        await sleepGate.waitForSleep()
        await provider.recordFutureResolution(
            ClaudeToolApprovalResolution(decision: .allow),
            for: key
        )
        let decision = await decisionTask.value
        await sleepGate.release()
        try await Task.sleep(for: .milliseconds(100))
        let publishedRequests = await recorder.requests()

        XCTAssertEqual(decision.approval, .allow)
        XCTAssertTrue(publishedRequests.isEmpty)
    }

    func testAgentCLIKitLiveHookDecisionProviderResolveMissDoesNotRecordFutureDecision() async throws {
        let provider = AgentCLIKitLiveHookDecisionProvider(sleep: { _ in })
        let recorder = LiveHookRequestRecorder()
        await provider.setDeferredToolRequestHandler { request in
            await recorder.append(request)
        }
        let key = ClaudeToolApprovalKey(sessionId: "session-1", toolUseId: "tool-2")
        let didResolveHeldRequest = await provider.resolve(
            ClaudeToolApprovalResolution(decision: .allow),
            for: key
        )
        let hookRequest = AgentCLIKit.ClaudeHookRequest(
            bearerToken: "token",
            hookName: "PreToolUse",
            conversationId: "conversation",
            payload: .object([
                "session_id": .string("session-1"),
                "tool_name": .string("Bash"),
                "tool_input": .object(["command": .string("pwd")])
            ])
        )

        let decisionTask = Task {
            await provider.decision(for: hookRequest, interactionId: "tool-2")
        }
        try await waitUntil("expected unresolved future hook to publish") {
            (await recorder.requests()).isEmpty == false
        }
        let didResolvePublishedRequest = await provider.resolve(
            ClaudeToolApprovalResolution(decision: .deny),
            for: key
        )
        let decision = await decisionTask.value

        XCTAssertFalse(didResolveHeldRequest)
        XCTAssertTrue(didResolvePublishedRequest)
        XCTAssertEqual(decision.approval, .deny)
    }

    func testAgentCLIKitManagerRecordsFutureSiblingLiveHookDecision() async throws {
        let executable = try makeScript(named: "live-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let fixture = makeLiveHookManagerFixture(executable: executable)
        let manager = fixture.manager
        let conversationId = "agentclikit-future-live-sibling"
        let workingDirectory = executable.deletingLastPathComponent().path

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: workingDirectory))
        let maybeSubscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let firstDecisionTask = Task {
            await fixture.liveHookDecisionProvider.decision(
                for: liveHookRequest(conversationId: conversationId, toolUseId: "tool-1"),
                interactionId: "tool-1"
            )
        }
        let approvalEvent = try await nextLiveHookEvent(
            from: subscription.stream,
            description: "first AgentCLIKit live hook approval"
        )
        guard case let .toolApprovalRequested(firstApproval) = approvalEvent else {
            return XCTFail("Expected tool approval request, got \(approvalEvent)")
        }
        let secondApproval = bashApproval(toolUseId: "tool-2")

        let didRecordSessionApproval = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: firstApproval,
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            additionalApprovals: [secondApproval],
            sessionApproval: nil,
            config: spawnConfig(workingDirectory: workingDirectory)
        ))
        let firstDecision = await firstDecisionTask.value
        let retainedAfterFirstResolution = await manager.retainedEventCount(conversationId: conversationId)
        let secondDecision = await fixture.liveHookDecisionProvider.decision(
            for: liveHookRequest(conversationId: conversationId, toolUseId: "tool-2"),
            interactionId: "tool-2"
        )
        try await Task.sleep(for: .milliseconds(100))
        let retainedAfterSecondDecision = await manager.retainedEventCount(conversationId: conversationId)

        XCTAssertFalse(didRecordSessionApproval)
        XCTAssertEqual(firstDecision.approval, .allow)
        XCTAssertEqual(secondDecision.approval, .allow)
        XCTAssertEqual(retainedAfterSecondDecision, retainedAfterFirstResolution)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitLiveHookDecisionProviderCanResolveInsidePublishHandler() async {
        let provider = AgentCLIKitLiveHookDecisionProvider(sleep: { _ in })
        await provider.setDeferredToolRequestHandler { request in
            _ = await provider.resolve(
                ClaudeToolApprovalResolution(decision: .allow),
                for: ClaudeToolApprovalKey(
                    sessionId: request.request.sessionId,
                    toolUseId: request.request.toolUseId
                )
            )
        }
        let hookRequest = AgentCLIKit.ClaudeHookRequest(
            bearerToken: "token",
            hookName: "PreToolUse",
            conversationId: "conversation",
            payload: .object([
                "session_id": .string("session-1"),
                "tool_name": .string("Bash"),
                "tool_input": .object(["command": .string("pwd")])
            ])
        )

        let decision = await provider.decision(for: hookRequest, interactionId: "tool-1")

        XCTAssertEqual(decision.approval, .allow)
    }
}

private extension AgentsManagerTests {
    func makeLiveHookManagerFixture(executable: URL) -> AgentCLIKitManagerFixture {
        makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        )
    }
}

private func bashApproval(toolUseId: String) -> ToolApprovalRequest {
    ToolApprovalRequest(
        sessionId: "session-1",
        toolUseId: toolUseId,
        toolName: "Bash",
        toolInput: #"{"command":"pwd"}"#
    )
}

private func liveHookRequest(conversationId: String, toolUseId: String) -> AgentCLIKit.ClaudeHookRequest {
    AgentCLIKit.ClaudeHookRequest(
        bearerToken: "token",
        hookName: "PreToolUse",
        conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
        payload: .object([
            "session_id": .string("session-1"),
            "tool_use_id": .string(toolUseId),
            "tool_name": .string("Bash"),
            "tool_input": .object(["command": .string("pwd")])
        ])
    )
}

private func nextLiveHookEvent(
    from stream: AsyncStream<ConversationEvent>,
    description: String
) async throws -> ConversationEvent {
    try await withThrowingTaskGroup(of: ConversationEvent?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(5))
            throw WaitTimeoutError(description: description)
        }
        defer { group.cancelAll() }
        if let event = try await group.next() ?? nil {
            return event
        }
        throw WaitTimeoutError(description: description)
    }
}

private actor LiveHookRequestRecorder {
    private var storage: [ClaudeDeferredToolRequest] = []

    func append(_ request: ClaudeDeferredToolRequest) {
        storage.append(request)
    }

    func requests() -> [ClaudeDeferredToolRequest] {
        storage
    }
}

private actor LiveHookSleepRecorder {
    private var storage: [Duration] = []

    func record(_ duration: Duration) {
        storage.append(duration)
    }

    func durations() -> [Duration] {
        storage
    }
}

private actor LiveHookSleepGate {
    private var didSleep = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var waitContinuation: CheckedContinuation<Void, Never>?

    func sleep(_ _: Duration) async throws {
        didSleep = true
        waitContinuation?.resume()
        waitContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitForSleep() async {
        guard !didSleep else {
            return
        }
        await withCheckedContinuation { continuation in
            waitContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
