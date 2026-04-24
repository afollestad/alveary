import XCTest

@testable import Alveary

extension ClaudeHookServerTests {
    func testHookEndpointIgnoresStoredSessionApprovalWhenCurrentModeDoesNotDeferTool() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "acceptEdits", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        _ = await server.recordSessionApproval(
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: "conversation-1",
                sessionId: "session-123",
                matchKind: .filePathExact,
                matchValue: "Sources/Auth.swift"
            )
        )

        let response = await server.handle(
            request(
                token: token,
                toolName: "Edit",
                toolInput: ["file_path": "Sources/Auth.swift"]
            )
        )

        XCTAssertNil(response.body)
    }

    func testHookEndpointIgnoresTransientApprovalWhenCurrentModeDoesNotDeferTool() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "acceptEdits", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        await server.recordTransientApprovalDecision(
            ClaudeToolApprovalResolution(decision: .allow),
            for: exactFileGrant(conversationId: "conversation-1", filePath: "Sources/Auth.swift")
        )

        let firstResponse = await server.handle(
            request(
                token: token,
                toolName: "Edit",
                toolUseId: "regenerated-tool-1",
                toolInput: ["file_path": "Sources/Auth.swift"]
            )
        )
        let secondResponse = await server.handle(
            request(
                token: token,
                toolName: "Edit",
                permissionMode: "default",
                toolUseId: "regenerated-tool-2",
                toolInput: ["file_path": "Sources/Auth.swift"]
            )
        )

        XCTAssertNil(firstResponse.body)
        XCTAssertEqual(try hookDecision(from: secondResponse), "allow")
    }

    private func exactFileGrant(conversationId: String, filePath: String) -> AgentSessionApprovalGrant {
        AgentSessionApprovalGrant(
            providerId: "claude",
            conversationId: conversationId,
            sessionId: "session-123",
            matchKind: .filePathExact,
            matchValue: filePath
        )
    }
}
