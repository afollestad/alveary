import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testClaudeHookServerDeferredToolKeepsRuntimeAliveWhileTokenInvalidationIsDelayed() async throws {
        let executable = try TempHookServerDeferredToolExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "token"]
            ),
            invalidateDelay: .seconds(2)
        )
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in ClaudeAdapter() }
        )
        let conversationId = "conversation-hook-server-deferred-tool-delayed-invalidation"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )
        try await waitUntil("expected first tool call before hook deferral") {
            await manager.retainedEventCount(conversationId: conversationId) >= 1
        }

        await manager.handleDeferredToolRequestFromHookServer(
            deferredToolRequest(
                conversationId: conversationId,
                toolUseId: "toolu_first",
                command: "date +%s"
            )
        )

        let isRunning = await manager.isRunning(conversationId: conversationId)
        XCTAssertTrue(isRunning)
    }

    func testAskUserQuestionLiveApprovalShowsWaitingThenBusyAfterResolution() async throws {
        let executable = try TempHookServerDeferredToolExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "token"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in ClaudeAdapter() }
        )
        let conversationId = "conversation-ask-user-question-status"
        let config = hookSpawnConfig(workingDirectory: executable.workingDirectory.path)
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }

        try await manager.spawn(id: conversationId, config: config, forkSession: false)
        try await waitUntil("expected first tool call before AskUserQuestion deferral") {
            await manager.retainedEventCount(conversationId: conversationId) >= 1
        }

        let approval = askUserQuestionRequest(conversationId: conversationId)
        await manager.handleDeferredToolRequestFromHookServer(approval)

        try await waitUntil("expected AskUserQuestion to show waiting status") {
            manager.status(for: conversationId) == .waitingForUser
        }

        _ = try await manager.resolveToolApproval(
            AgentToolApprovalResolutionRequest(
                conversationId: conversationId,
                approval: approval.request,
                resolution: ClaudeToolApprovalResolution(
                    decision: .allow,
                    updatedInput: #"{"answers":{"Pick one":"A"},"questions":[]}"#
                ),
                additionalApprovals: [],
                sessionApproval: nil,
                config: config
            )
        )

        XCTAssertEqual(manager.status(for: conversationId), .busy)
    }

    func testAskUserQuestionLiveApprovalFailureClearsWaitingStatus() async throws {
        let executable = try TempHookServerDeferredToolExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "token"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in ClaudeAdapter() }
        )
        let conversationId = "conversation-ask-user-question-failure-status"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )
        try await waitUntil("expected first tool call before AskUserQuestion deferral") {
            await manager.retainedEventCount(conversationId: conversationId) >= 1
        }

        let approval = askUserQuestionRequest(conversationId: conversationId)
        await manager.handleDeferredToolRequestFromHookServer(approval)

        try await waitUntil("expected AskUserQuestion to show waiting status") {
            manager.status(for: conversationId) == .waitingForUser
        }

        await emitToolApprovalFailure(manager: manager, conversationId: conversationId, approval: approval.request)

        XCTAssertEqual(manager.status(for: conversationId), .busy)
    }

    func testClaudeHookServerDeferredToolCanReplayLiveApprovalWithoutActiveSubscriber() async throws {
        let fixture = try hookServerDeferredToolRaceFixture()
        defer { cleanupHookServerDeferredToolRaceFixture(fixture) }

        try await fixture.manager.spawn(
            id: fixture.conversationId,
            config: hookSpawnConfig(workingDirectory: fixture.executable.workingDirectory.path),
            forkSession: false
        )
        try await waitUntil("expected first tool call before hook deferral") {
            await fixture.manager.retainedEventCount(conversationId: fixture.conversationId) >= 1
        }

        await fixture.manager.handleDeferredToolRequestFromHookServer(
            deferredToolRequest(
                conversationId: fixture.conversationId,
                toolUseId: "toolu_first",
                command: "date +%s"
            )
        )
        try await waitUntil("expected manager to retain live approval") {
            await fixture.manager.retainedEventCount(conversationId: fixture.conversationId) >= 2
        }

        guard let subscription = await fixture.manager.subscribe(
            conversationId: fixture.conversationId,
            afterIndex: 0
        ) else {
            return XCTFail("Expected live deferred buffer to remain replayable")
        }
        await fixture.manager.kill(conversationId: fixture.conversationId)
        let collected = await collectedEvents(from: subscription.stream)
        XCTAssertTrue(collected.contains { event in
            if case .toolApprovalRequested(let request) = event {
                return request.toolUseId == "toolu_first"
            }
            return false
        })
    }

    func testClaudeHookServerDeferredToolKeepsRuntimeAliveForLaterStdoutEvents() async throws {
        let fixture = try hookServerDeferredToolRaceFixture()
        defer { cleanupHookServerDeferredToolRaceFixture(fixture) }

        try await fixture.manager.spawn(
            id: fixture.conversationId,
            config: hookSpawnConfig(workingDirectory: fixture.executable.workingDirectory.path),
            forkSession: false
        )
        guard let subscription = await fixture.manager.subscribe(
            conversationId: fixture.conversationId,
            afterIndex: 0
        ) else {
            return XCTFail("Expected live event subscription")
        }
        async let events = collectedEvents(from: subscription.stream)

        try await waitUntil("expected first tool call before hook deferral") {
            await fixture.manager.retainedEventCount(conversationId: fixture.conversationId) >= 1
        }

        await fixture.manager.handleDeferredToolRequestFromHookServer(
            deferredToolRequest(
                conversationId: fixture.conversationId,
                toolUseId: "toolu_first",
                command: "date +%s"
            )
        )
        await fixture.manager.handleStreamEvent(
            .toolCall(
                id: "toolu_second",
                name: "Bash",
                input: #"{"command":"pwd"}"#,
                parentToolUseId: nil,
                callerAgent: nil
            ),
            conversationId: fixture.conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )

        try await waitUntil("expected manager to keep accepting live events after hook server deferral") {
            await fixture.manager.retainedEventCount(conversationId: fixture.conversationId) >= 3
        }
        await fixture.manager.kill(conversationId: fixture.conversationId)

        let collected = await events
        XCTAssertTrue(collected.contains { event in
            if case .toolCall(id: "toolu_second", name: _, input: _, parentToolUseId: _, callerAgent: _) = event {
                return true
            }
            return false
        })
    }

    func testClaudeHookServerDeferredToolRetainsConcurrentDeferredRequestsFromSameRuntime() async throws {
        let fixture = try hookServerDeferredToolRaceFixture()
        defer { cleanupHookServerDeferredToolRaceFixture(fixture) }

        try await fixture.manager.spawn(
            id: fixture.conversationId,
            config: hookSpawnConfig(workingDirectory: fixture.executable.workingDirectory.path),
            forkSession: false
        )
        guard let subscription = await fixture.manager.subscribe(
            conversationId: fixture.conversationId,
            afterIndex: 0
        ) else {
            return XCTFail("Expected live event subscription")
        }
        let (approvalToolIds, eventTask) = collectApprovalToolIds(from: subscription)
        defer { eventTask.cancel() }

        try await waitUntil("expected first tool call before hook deferrals") {
            await fixture.manager.retainedEventCount(conversationId: fixture.conversationId) >= 1
        }

        let hookServer = fixture.hookServer
        let firstRequest = deferredToolRequest(
            conversationId: fixture.conversationId,
            toolUseId: "toolu_first",
            command: "date +%s"
        )
        let secondRequest = deferredToolRequest(
            conversationId: fixture.conversationId,
            toolUseId: "toolu_second",
            command: "pwd"
        )
        let firstEmit = Task { await hookServer.emitDeferredToolRequest(firstRequest) }
        let secondEmit = Task { await hookServer.emitDeferredToolRequest(secondRequest) }
        await firstEmit.value
        await secondEmit.value

        try await waitUntil("expected manager to emit both live approval prompts") {
            approvalToolIds.withLock { $0.count } == 2
        }

        let isRunning = await fixture.manager.isRunning(conversationId: fixture.conversationId)
        XCTAssertTrue(isRunning)
        XCTAssertEqual(Set(approvalToolIds.withLock { $0 }), ["toolu_first", "toolu_second"])
    }

    func testResolvedBatchApprovalIgnoresLateSiblingHookNotification() async throws {
        let fixture = try hookServerDeferredToolRaceFixture()
        defer { cleanupHookServerDeferredToolRaceFixture(fixture) }

        try await fixture.manager.spawn(
            id: fixture.conversationId,
            config: hookSpawnConfig(workingDirectory: fixture.executable.workingDirectory.path),
            forkSession: false
        )
        guard let subscription = await fixture.manager.subscribe(
            conversationId: fixture.conversationId,
            afterIndex: 0
        ) else {
            return XCTFail("Expected live event subscription")
        }
        let (approvalToolIds, eventTask) = collectApprovalToolIds(from: subscription)
        defer { eventTask.cancel() }

        try await waitUntil("expected first tool call before hook deferral") {
            await fixture.manager.retainedEventCount(conversationId: fixture.conversationId) >= 1
        }

        let firstRequest = deferredToolRequest(
            conversationId: fixture.conversationId,
            toolUseId: "toolu_first",
            command: "date +%s"
        )
        let secondRequest = deferredToolRequest(
            conversationId: fixture.conversationId,
            toolUseId: "toolu_second",
            command: "pwd"
        )
        await fixture.hookServer.emitDeferredToolRequest(firstRequest)
        try await waitUntil("expected first live approval prompt") {
            approvalToolIds.withLock { $0 } == ["toolu_first"]
        }

        _ = try await fixture.manager.resolveToolApproval(
            AgentToolApprovalResolutionRequest(
                conversationId: fixture.conversationId,
                approval: firstRequest.request,
                resolution: ClaudeToolApprovalResolution(decision: .allow),
                additionalApprovals: [secondRequest.request],
                sessionApproval: nil,
                config: hookSpawnConfig(workingDirectory: fixture.executable.workingDirectory.path)
            )
        )
        await fixture.hookServer.emitDeferredToolRequest(secondRequest)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(approvalToolIds.withLock { $0 }, ["toolu_first"])
    }

    private func deferredToolRequest(
        conversationId: String,
        toolUseId: String,
        command: String
    ) -> ClaudeDeferredToolRequest {
        ClaudeDeferredToolRequest(
            conversationId: conversationId,
            launchToken: "token",
            request: ToolApprovalRequest(
                sessionId: "session-deferred",
                toolUseId: toolUseId,
                toolName: "Bash",
                toolInput: #"{"command":"\#(command)"}"#
            )
        )
    }

    private func askUserQuestionRequest(conversationId: String) -> ClaudeDeferredToolRequest {
        ClaudeDeferredToolRequest(
            conversationId: conversationId,
            launchToken: "token",
            request: ToolApprovalRequest(
                sessionId: "session-deferred",
                toolUseId: "toolu_question",
                toolName: "AskUserQuestion",
                toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
            )
        )
    }

    private func emitToolApprovalFailure(
        manager: DefaultAgentsManager,
        conversationId: String,
        approval: ToolApprovalRequest
    ) async {
        guard let subscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0) else {
            XCTFail("Expected live approval buffer")
            return
        }

        await manager.handleStreamEvent(
            .toolApprovalFailed(ToolApprovalFailure(
                sessionId: approval.sessionId,
                toolUseId: approval.toolUseId,
                toolName: approval.toolName,
                message: "Claude hook failed (PreToolUse:AskUserQuestion): socket closed"
            )),
            conversationId: conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )
    }

    private func collectApprovalToolIds(
        from subscription: AgentEventSubscription
    ) -> (ids: LockedState<[String]>, task: Task<Void, Never>) {
        let approvalToolIds = LockedState<[String]>([])
        let eventTask = Task {
            for await event in subscription.stream {
                if case .toolApprovalRequested(let request) = event {
                    approvalToolIds.withLock { $0.append(request.toolUseId) }
                }
            }
        }
        return (approvalToolIds, eventTask)
    }
}
