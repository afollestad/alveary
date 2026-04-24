import Foundation
import XCTest

@testable import Alveary

final class ClaudeHookServerTests: XCTestCase {
    func testPrepareLaunchSkipsAutomaticPermissionModes() async {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())

        let automatic = await server.prepareLaunch(permissionMode: "auto", conversationId: "conversation-1")
        let bypass = await server.prepareLaunch(permissionMode: "bypassPermissions", conversationId: "conversation-1")

        XCTAssertNil(automatic)
        XCTAssertNil(bypass)
    }

    func testHookEndpointRejectsInvalidToken() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        _ = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")

        let response = await server.handle(request(token: "wrong-token", toolName: "Bash"))
        let decision = try hookDecision(from: response)

        XCTAssertEqual(decision, "deny")
    }

    func testHookEndpointDeniesMalformedRequestWithValidToken() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(
            ClaudeHookHTTPRequest(
                authorization: "Bearer \(token)",
                body: Data("{\"hook_event_name\":\"PreToolUse\"}".utf8)
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "deny")
    }

    func testHookEndpointNoOpsForReadTool() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(request(token: token, toolName: "Read"))

        XCTAssertNil(response.body)
    }

    func testHookEndpointNoOpsForEnterPlanMode() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(request(token: token, toolName: "EnterPlanMode"))

        XCTAssertNil(response.body)
    }

    func testHookEndpointRejectsInvalidatedToken() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        await server.invalidateToken(token)
        let response = await server.handle(request(token: token, toolName: "Bash"))

        XCTAssertEqual(try hookDecision(from: response), "deny")
    }

    func testHookEndpointDefersApprovalWorthyTool() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(request(token: token, toolName: "Bash"))
        let decision = try hookDecision(from: response)

        XCTAssertEqual(decision, "defer")
    }

    func testHookEndpointNotifiesDeferredToolRequestHandler() async throws {
        let server = DefaultClaudeHookServer(
            supportDirectory: temporarySupportDirectory(),
            pendingApprovalTimeout: .milliseconds(50)
        )
        let capturedRequest = LockedState<ClaudeDeferredToolRequest?>(nil)
        await server.setDeferredToolRequestHandler { request in
            capturedRequest.withLock { $0 = request }
        }
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        _ = await server.handle(
            request(
                token: token,
                toolName: "Bash",
                toolInput: ["command": "date +%s"]
            )
        )
        try await waitUntil("expected deferred tool notification") {
            capturedRequest.withLock { $0 } != nil
        }

        XCTAssertEqual(
            capturedRequest.withLock { $0 },
            ClaudeDeferredToolRequest(
                conversationId: "conversation-1",
                launchToken: token,
                request: ToolApprovalRequest(
                    sessionId: "session-123",
                    toolUseId: "tool-1",
                    toolName: "Bash",
                    toolInput: #"{"command":"date +%s"}"#
                )
            )
        )
    }

    func testHookEndpointFallsBackToDeferWhenDeferredToolDecisionTimesOut() async throws {
        let server = DefaultClaudeHookServer(
            supportDirectory: temporarySupportDirectory(),
            pendingApprovalTimeout: .milliseconds(50)
        )
        await server.setDeferredToolRequestHandler { _ in
            try? await Task.sleep(for: .seconds(2))
        }
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        let request = request(token: token, toolName: "Bash")

        let response = try await Self.responseBeforeTimeout {
            await server.handle(request)
        }

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testHookEndpointAllowsDeferredToolWhenDecisionIsRecordedBeforeTimeout() async throws {
        let server = DefaultClaudeHookServer(
            supportDirectory: temporarySupportDirectory(),
            pendingApprovalTimeout: .seconds(2)
        )
        let capturedRequest = LockedState<ClaudeDeferredToolRequest?>(nil)
        await server.setDeferredToolRequestHandler { request in
            capturedRequest.withLock { $0 = request }
        }
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        let hookRequest = request(token: token, toolName: "Bash")

        async let response = server.handle(hookRequest)
        try await waitUntil("expected deferred tool notification") {
            capturedRequest.withLock { $0 } != nil
        }
        await server.recordDecision(
            ClaudeToolApprovalResolution(decision: .allow),
            for: ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")
        )

        let decision = try await hookDecision(from: response)
        XCTAssertEqual(decision, "allow")
    }

    func testInvalidatingTokenReleasesOpenDeferredToolDecisionWait() async throws {
        let server = DefaultClaudeHookServer(
            supportDirectory: temporarySupportDirectory(),
            pendingApprovalTimeout: .seconds(2)
        )
        let capturedRequest = LockedState<ClaudeDeferredToolRequest?>(nil)
        await server.setDeferredToolRequestHandler { request in
            capturedRequest.withLock { $0 = request }
        }
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        let hookRequest = request(token: token, toolName: "Bash")

        async let pendingResponse = Self.responseBeforeTimeout {
            await server.handle(hookRequest)
        }
        try await waitUntil("expected deferred tool notification") {
            capturedRequest.withLock { $0 } != nil
        }

        await server.invalidateToken(token)

        let response = try await pendingResponse
        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testHookEndpointAllowsEditToolsInAcceptEditsMode() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "acceptEdits", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(request(token: token, toolName: "Edit"))

        XCTAssertNil(response.body)
    }

    func testHookEndpointStillDefersBashInAcceptEditsMode() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "acceptEdits", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(request(token: token, toolName: "Bash"))

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testHookPolicyUsesSharedApprovalControlledToolPredicate() {
        XCTAssertTrue(ClaudeHookPolicy.isPotentiallyApprovalControlledTool("Write"))
        XCTAssertTrue(ClaudeHookPolicy.shouldDefer(toolName: "Write", permissionMode: "default"))
        XCTAssertFalse(ClaudeHookPolicy.shouldDefer(toolName: "Write", permissionMode: "acceptEdits"))
        XCTAssertTrue(ClaudeHookPolicy.shouldDefer(toolName: "Bash", permissionMode: "acceptEdits"))
        XCTAssertFalse(ClaudeHookPolicy.canRenderToolApproval("AskUserQuestion"))
        XCTAssertFalse(ClaudeHookPolicy.isPotentiallyApprovalControlledTool("Read"))
    }

    func testHookSettingsUseSharedPreToolUseMatcher() async throws {
        let supportDirectory = temporarySupportDirectory()
        let server = DefaultClaudeHookServer(supportDirectory: supportDirectory)
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let settingsIndex = try XCTUnwrap(launch.arguments.firstIndex(of: "--settings"))
        let settingsURL = URL(fileURLWithPath: launch.arguments[settingsIndex + 1])
        let settingsData = try Data(contentsOf: settingsURL)
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: settingsData) as? [String: Any])
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let preToolUse = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        let hookConfig = try XCTUnwrap(preToolUse.first)

        XCTAssertEqual(hookConfig["matcher"] as? String, ClaudeHookPolicy.preToolUseMatcher)
    }

    func testHookPolicyOnlyBatchesPotentialApprovalToolCallsWithinSameToolFamily() {
        XCTAssertTrue(ClaudeHookPolicy.canBatchPotentialApprovalToolCall(
            toolName: "Write",
            with: ["Write"]
        ))
        XCTAssertFalse(ClaudeHookPolicy.canBatchPotentialApprovalToolCall(
            toolName: "Write",
            with: ["Bash"]
        ))
        XCTAssertFalse(ClaudeHookPolicy.canBatchPotentialApprovalToolCall(
            toolName: "Read",
            with: ["Read"]
        ))
    }

    func testHookEndpointDefersExitPlanModeWhileSessionIsInPlanMode() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(
            request(
                token: token,
                toolName: "ExitPlanMode",
                permissionMode: "plan"
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testHookEndpointDefersExitPlanModeUsingUpdatedConversationModeWithoutPayloadOverride() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        await server.updatePermissionMode("plan", for: "conversation-1")

        let response = await server.handle(
            request(
                token: token,
                toolName: "ExitPlanMode"
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testPrepareLaunchWithoutPermissionModeClearsStoredConversationMode() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        _ = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        await server.updatePermissionMode("plan", for: "conversation-1")
        let launchConfig = await server.prepareLaunch(permissionMode: nil, conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(
            request(
                token: token,
                toolName: "ExitPlanMode"
            )
        )

        XCTAssertNil(response.body)
    }

    func testHookEndpointNoOpsForExitPlanModeOutsidePlanMode() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(
            request(
                token: token,
                toolName: "ExitPlanMode",
                permissionMode: "default"
            )
        )

        XCTAssertNil(response.body)
    }

    func testHookEndpointDefersMutatingMCPTool() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(request(token: token, toolName: "mcp__github__create_issue"))

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testHookEndpointNoOpsForReadOnlyMCPTool() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(request(token: token, toolName: "mcp__github__list_issues"))

        XCTAssertNil(response.body)
    }

    func testHookEndpointConsumesOneShotAllowDecision() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        let key = ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")
        await server.recordDecision(ClaudeToolApprovalResolution(decision: .allow), for: key)

        let firstResponse = await server.handle(request(token: token, toolName: "Bash"))
        let secondResponse = await server.handle(request(token: token, toolName: "Bash"))

        XCTAssertEqual(try hookDecision(from: firstResponse), "allow")
        XCTAssertEqual(try hookDecision(from: secondResponse), "defer")
    }

    func testHookEndpointAllowForExitPlanModeEchoesUpdatedInput() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        let key = ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")
        await server.recordDecision(ClaudeToolApprovalResolution(decision: .allow), for: key)

        let response = await server.handle(
            request(
                token: token,
                toolName: "ExitPlanMode",
                permissionMode: "plan",
                toolInput: [:]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "allow")
        XCTAssertEqual(try updatedInput(from: response) as? NSDictionary, [:])
    }

    func testHookEndpointConsumesOneShotDenyDecision() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        let key = ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")
        await server.recordDecision(ClaudeToolApprovalResolution(decision: .deny), for: key)

        let response = await server.handle(request(token: token, toolName: "Bash"))

        XCTAssertEqual(try hookDecision(from: response), "deny")
    }

    func testHookEndpointDoesNotConsumeDiscardedDecision() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        let key = ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")
        await server.recordDecision(ClaudeToolApprovalResolution(decision: .allow), for: key)

        await server.discardDecision(for: key)
        let response = await server.handle(request(token: token, toolName: "Bash"))

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func request(
        token: String,
        toolName: String,
        permissionMode: String? = nil,
        toolUseId: String = "tool-1",
        toolInput: [String: Any] = [:]
    ) -> ClaudeHookHTTPRequest {
        var body: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "session-123",
            "tool_use_id": toolUseId,
            "tool_name": toolName,
            "tool_input": toolInput
        ]
        if let permissionMode {
            body["permission_mode"] = permissionMode
        }
        let data = try? JSONSerialization.data(withJSONObject: body)
        return ClaudeHookHTTPRequest(
            authorization: "Bearer \(token)",
            body: data ?? Data()
        )
    }

    func hookDecision(from response: ClaudeHookHTTPResponse) throws -> String? {
        let body = try XCTUnwrap(response.body)
        return try hookDecision(from: body)
    }

    func updatedInput(from response: ClaudeHookHTTPResponse) throws -> Any? {
        let body = try XCTUnwrap(response.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        return output["updatedInput"]
    }

    func hookDecision(from body: Data) throws -> String? {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        return output["permissionDecision"] as? String
    }

    func temporarySupportDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
