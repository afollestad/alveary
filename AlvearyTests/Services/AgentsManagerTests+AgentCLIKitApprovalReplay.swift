import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitFallbackApprovalResumeDoesNotReplayApprovalRows() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: DeferredReplayAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-fallback-approval-replay"
        addTeardownBlock {
            try? await manager.destroyRuntime(conversationId: conversationId)
        }

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let approvalEvent = try await nextEvent(from: subscription.stream, description: "AgentCLIKit fallback approval event")
        guard case let .toolApprovalRequested(approval) = approvalEvent else {
            return XCTFail("Expected tool approval request, got \(approvalEvent)")
        }
        try await waitForFallbackApprovalResumeReadiness(manager: manager, conversationId: conversationId)

        _ = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: approval,
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            additionalApprovals: [],
            sessionApproval: nil,
            config: spawnConfig(workingDirectory: "/tmp")
        ))
        var resumedSubscription: Alveary.AgentEventSubscription?
        try await waitUntil("expected AgentCLIKit fallback approval to install resumed buffer") {
            let candidate = await self.awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
            resumedSubscription = candidate?.generation == subscription.generation ? nil : candidate
            return resumedSubscription != nil
        }
        let resolvedSubscription = try XCTUnwrap(resumedSubscription)
        let resumedEvent = try await nextEvent(
            from: resolvedSubscription.stream,
            description: "AgentCLIKit fallback approval resumed event"
        )

        XCTAssertEqual(resumedEvent, .message(role: "assistant", content: "resumed", parentToolUseId: nil))
    }

    func testAgentCLIKitReplacementBufferDropsOnlyPreStartTerminalLifecycle() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: DeferredReplayAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-replacement-buffer-lifecycle"
        let upstream = AsyncStream<AgentCLIKit.AgentEventEnvelope>.makeStream()
        defer { upstream.continuation.finish() }

        await manager.installAgentCLIKitSubscriptionBuffer(
            conversationId: conversationId,
            config: spawnConfig(workingDirectory: "/tmp"),
            subscription: AgentCLIKit.AgentEventSubscription(generation: 1, events: upstream.stream),
            dropsPreStartTerminalLifecycle: true
        )
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)

        yieldApprovalReplayLifecycleSequence(
            to: upstream.continuation,
            conversationId: conversationId
        )

        let received = try await events(
            from: subscription.stream,
            until: { $0.contains(.error(message: "replacement failed")) },
            description: "replacement buffer lifecycle events"
        )
        XCTAssertEqual(received, [
            .message(role: "assistant", content: "replayed content", parentToolUseId: nil),
            .message(role: "assistant", content: "resumed", parentToolUseId: nil),
            .error(message: "replacement failed")
        ])
    }

    func testAgentCLIKitFallbackApprovalResumeDoesNotReplayDeltaBackedTranscript() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: DeferredDeltaReplayAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-fallback-delta-replay"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let approvalEvent = try await firstApprovalEvent(from: subscription.stream)
        guard case let .toolApprovalRequested(approval) = approvalEvent else {
            return XCTFail("Expected tool approval request, got \(approvalEvent)")
        }
        try await waitForFallbackApprovalResumeReadiness(manager: manager, conversationId: conversationId)

        let resumedEvents = try await approveAndCollectDeltaReplayEvents(
            manager: manager,
            conversationId: conversationId,
            approval: approval,
            previousGeneration: subscription.generation
        )

        XCTAssertFalse(resumedEvents.contains { event in
            event == .message(role: "assistant", content: "Running 4 tools in parallel now.", parentToolUseId: nil)
        })
        XCTAssertFalse(resumedEvents.contains { event in
            if case .toolCall = event {
                return true
            }
            return false
        })
        XCTAssertFalse(resumedEvents.contains { event in
            if case .toolResult = event {
                return true
            }
            return false
        })
        XCTAssertTrue(resumedEvents.contains(.message(role: "assistant", content: "resumed", parentToolUseId: nil)))
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitFallbackPlanFileApprovalResumeDoesNotReplayFreshApprovalRows() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: PlanFileReplayAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-fallback-plan-file-approval-replay"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let approvalEvent = try await firstApprovalEvent(from: subscription.stream)
        guard case let .toolApprovalRequested(approval) = approvalEvent else {
            return XCTFail("Expected tool approval request, got \(approvalEvent)")
        }
        try await waitForFallbackApprovalResumeReadiness(manager: manager, conversationId: conversationId)

        let resumedEvents = try await approveAndCollectDeltaReplayEvents(
            manager: manager,
            conversationId: conversationId,
            approval: approval,
            previousGeneration: subscription.generation
        )

        XCTAssertFalse(resumedEvents.contains(.message(
            role: "assistant",
            content: "Writing a test plan now.",
            parentToolUseId: nil
        )))
        XCTAssertFalse(resumedEvents.contains { event in
            if case .toolApprovalRequested = event {
                return true
            }
            return false
        })
        XCTAssertFalse(resumedEvents.contains { event in
            if case .tokens(_, _, _, _, _, let stopReason, _, _, _, _, _, _) = event {
                return stopReason == "tool_deferred"
            }
            return false
        })
        XCTAssertTrue(resumedEvents.contains(.message(role: "assistant", content: "resumed", parentToolUseId: nil)))
        await manager.kill(conversationId: conversationId)
    }

    private func approveAndCollectDeltaReplayEvents(
        manager: DefaultAgentsManager,
        conversationId: String,
        approval: ToolApprovalRequest,
        previousGeneration: UUID
    ) async throws -> [ConversationEvent] {
        _ = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: approval,
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            additionalApprovals: [],
            sessionApproval: nil,
            config: spawnConfig(workingDirectory: "/tmp")
        ))
        var resumedSubscription: Alveary.AgentEventSubscription?
        try await waitUntil("expected AgentCLIKit fallback approval to install resumed buffer") {
            let candidate = await self.awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
            resumedSubscription = candidate?.generation == previousGeneration ? nil : candidate
            return resumedSubscription != nil
        }
        let resolvedSubscription = try XCTUnwrap(resumedSubscription)
        return try await events(
            from: resolvedSubscription.stream,
            until: {
                $0.contains(.message(role: "assistant", content: "resumed", parentToolUseId: nil))
            },
            description: "AgentCLIKit fallback approval resumed events"
        )
    }

    private func firstApprovalEvent(from stream: AsyncStream<ConversationEvent>) async throws -> ConversationEvent {
        let collected = try await events(
            from: stream,
            until: { events in
                events.contains {
                    if case .toolApprovalRequested = $0 {
                        return true
                    }
                    return false
                }
            },
            description: "AgentCLIKit fallback approval event"
        )
        guard let approval = collected.first(where: {
            if case .toolApprovalRequested = $0 {
                return true
            }
            return false
        }) else {
            throw WaitTimeoutError(description: "AgentCLIKit fallback approval event")
        }
        return approval
    }

    private func events(
        from stream: AsyncStream<ConversationEvent>,
        until predicate: @escaping @Sendable ([ConversationEvent]) -> Bool,
        description: String,
        timeout: Duration = .seconds(5)
    ) async throws -> [ConversationEvent] {
        try await withThrowingTaskGroup(of: [ConversationEvent].self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                var events: [ConversationEvent] = []
                while let event = await iterator.next() {
                    events.append(event)
                    if predicate(events) {
                        return events
                    }
                }
                return events
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WaitTimeoutError(description: description)
            }

            defer { group.cancelAll() }
            return try await group.next() ?? []
        }
    }
}

private func yieldApprovalReplayLifecycleSequence(
    to continuation: AsyncStream<AgentCLIKit.AgentEventEnvelope>.Continuation,
    conversationId: String
) {
    continuation.yield(approvalReplayEnvelope(
        index: 1,
        conversationId: conversationId,
        event: .message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: "replayed content"))
    ))
    continuation.yield(approvalReplayEnvelope(
        index: 2,
        conversationId: conversationId,
        source: .process,
        event: .lifecycle(AgentCLIKit.AgentLifecycleEvent(state: .exited))
    ))
    continuation.yield(approvalReplayEnvelope(
        index: 3,
        conversationId: conversationId,
        source: .process,
        event: .lifecycle(AgentCLIKit.AgentLifecycleEvent(state: .starting))
    ))
    continuation.yield(approvalReplayEnvelope(
        index: 4,
        conversationId: conversationId,
        event: .message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: "resumed"))
    ))
    continuation.yield(approvalReplayEnvelope(
        index: 5,
        conversationId: conversationId,
        source: .process,
        event: .lifecycle(AgentCLIKit.AgentLifecycleEvent(state: .failed, message: "replacement failed"))
    ))
}

private func approvalReplayEnvelope(
    index: Int,
    conversationId: String,
    source: AgentCLIKit.AgentEventSource = .stdout,
    event: AgentCLIKit.AgentEvent
) -> AgentCLIKit.AgentEventEnvelope {
    AgentCLIKit.AgentEventEnvelope(
        generation: 1,
        index: index,
        providerId: .claude,
        conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
        providerSessionId: nil,
        source: source,
        event: event
    )
}

private struct PlanFileReplayAdapter: AgentCLIKit.AgentProviderAdapter {
    let counter = AgentCLIKitLaunchCounter()
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        let launch = await counter.next()
        let output = launch == 1
            ? "message:Writing a test plan now.\nplan-approval:write-original:write\ndeferred"
            : "message:Writing a test plan now.\nplan-approval:write-replayed:write\ndeferred\nmessage:resumed"
        return AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", "printf '%s\\n' \"$1\"", "agent", output],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        if let rawPlanApproval = line.removingPrefix("plan-approval:") {
            return planApprovalEvents(from: rawPlanApproval)
        }
        if line == "deferred" {
            return [.usage(AgentCLIKit.AgentUsageEvent(
                model: nil,
                inputTokens: nil,
                outputTokens: nil,
                stopReason: "tool_deferred",
                metadata: ["stop_reason": .string("tool_deferred")]
            ))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }

    private func planApprovalEvents(from rawPlanApproval: String) -> [AgentCLIKit.AgentEvent] {
        let components = rawPlanApproval.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            return []
        }
        let isWrite = components[1] == "write"
        return [.interaction(AgentCLIKit.AgentInteractionEvent(
            id: AgentCLIKit.AgentInteractionID(rawValue: components[0]),
            kind: .approval,
            prompt: isWrite ? "Write" : "Edit",
            metadata: [
                "session_id": .string("session-1"),
                "tool_name": .string(isWrite ? "Write" : "Edit"),
                "tool_input": .object([
                    "file_path": .string("/Users/afollestad/.claude/plans/test-plan.md"),
                    "content": .string(components[1])
                ])
            ]
        ))]
    }
}
