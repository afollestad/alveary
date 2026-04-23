import XCTest

@testable import Alveary

extension ClaudeHookServerTests {
    func testHookEndpointAllowsMatchingExactBashSessionApproval() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        _ = await server.recordSessionApproval(
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: "conversation-1",
                sessionId: "session-123",
                matchKind: .bashExact,
                matchValue: "git add foo.swift"
            )
        )

        let response = await server.handle(
            request(
                token: token,
                toolName: "Bash",
                toolInput: ["command": "git add foo.swift"]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "allow")
    }

    func testHookEndpointDefersNonMatchingExactBashSessionApproval() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        _ = await server.recordSessionApproval(
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: "conversation-1",
                sessionId: "session-123",
                matchKind: .bashExact,
                matchValue: "git add foo.swift"
            )
        )

        let response = await server.handle(
            request(
                token: token,
                toolName: "Bash",
                toolInput: ["command": "git add -A"]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testHookEndpointAllowsMatchingBashCommandGroupSessionApproval() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        _ = await server.recordSessionApproval(
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: "conversation-1",
                sessionId: "session-123",
                matchKind: .bashCommandGroup,
                matchValue: "git add"
            )
        )

        let response = await server.handle(
            request(
                token: token,
                toolName: "Bash",
                toolInput: ["command": "git add bar.swift"]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "allow")
    }

    func testHookEndpointDoesNotApplyGroupApprovalToCompoundShellCommands() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        _ = await server.recordSessionApproval(
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: "conversation-1",
                sessionId: "session-123",
                matchKind: .bashCommandGroup,
                matchValue: "git add"
            )
        )

        let response = await server.handle(
            request(
                token: token,
                toolName: "Bash",
                toolInput: ["command": "git add foo.swift && git push"]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testBashCommandWithoutSubcommandOnlySupportsExactSessionApproval() {
        let request = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: #"{"command":"python script.py"}"#
        )

        XCTAssertEqual(request.supportedSessionApprovalScopes, [.exact])
    }

    func testHookEndpointAllowsMatchingFilePathSessionApproval() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
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

        XCTAssertEqual(try hookDecision(from: response), "allow")
    }

    func testHookEndpointPersistsSessionApprovalsAcrossServerRestart() async throws {
        let supportDirectory = temporarySupportDirectory()
        let firstServer = DefaultClaudeHookServer(supportDirectory: supportDirectory)
        _ = await firstServer.recordSessionApproval(
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: "conversation-1",
                sessionId: "session-123",
                matchKind: .bashExact,
                matchValue: "git status"
            )
        )

        let secondServer = DefaultClaudeHookServer(supportDirectory: supportDirectory)
        let launchConfig = await secondServer.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await secondServer.handle(
            request(
                token: token,
                toolName: "Bash",
                toolInput: ["command": "git status"]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "allow")
    }

    func testHookEndpointRemovesStoredSessionApprovals() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        _ = await server.recordSessionApproval(
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: "conversation-1",
                sessionId: "session-123",
                matchKind: .bashExact,
                matchValue: "git status"
            )
        )

        await server.removeSessionApprovals(conversationId: "conversation-1", sessionId: "session-123")
        let response = await server.handle(
            request(
                token: token,
                toolName: "Bash",
                toolInput: ["command": "git status"]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testHookEndpointRemovalKeepsOtherProviderSessionApprovals() async throws {
        let supportDirectory = temporarySupportDirectory()
        let firstServer = DefaultClaudeHookServer(supportDirectory: supportDirectory)
        _ = await firstServer.recordSessionApproval(
            AgentSessionApprovalGrant(
                providerId: "other-agent",
                conversationId: "conversation-1",
                sessionId: "session-123",
                matchKind: .bashExact,
                matchValue: "git status"
            )
        )

        await firstServer.removeSessionApprovals(conversationId: "conversation-1", sessionId: "session-123")

        let secondServer = DefaultClaudeHookServer(supportDirectory: supportDirectory)
        let preserved = await secondServer.recordSessionApproval(
            AgentSessionApprovalGrant(
                providerId: "other-agent",
                conversationId: "conversation-1",
                sessionId: "session-123",
                matchKind: .bashExact,
                matchValue: "git status"
            )
        )

        XCTAssertEqual(
            preserved,
            SessionApprovalRecordResult(isEffective: true, wasInserted: false)
        )
    }

    func testRecordSessionApprovalReturnsFalseWhenRuleAlreadyExists() async {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let approval = AgentSessionApprovalGrant(
            providerId: "claude",
            conversationId: "conversation-1",
            sessionId: "session-123",
            matchKind: .bashCommandGroup,
            matchValue: "git add"
        )

        let firstInsert = await server.recordSessionApproval(approval)
        let secondInsert = await server.recordSessionApproval(approval)

        XCTAssertEqual(
            firstInsert,
            SessionApprovalRecordResult(isEffective: true, wasInserted: true)
        )
        XCTAssertEqual(
            secondInsert,
            SessionApprovalRecordResult(isEffective: true, wasInserted: false)
        )
    }

    func testHookEndpointDoesNotApplySessionApprovalAcrossConversations() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        _ = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let secondLaunchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-2")
        let secondLaunch = try XCTUnwrap(secondLaunchConfig)
        let secondToken = try XCTUnwrap(secondLaunch.environment["ALVEARY_HOOK_TOKEN"])
        _ = await server.recordSessionApproval(
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: "conversation-1",
                sessionId: "session-123",
                matchKind: .bashExact,
                matchValue: "git status"
            )
        )

        let response = await server.handle(
            request(
                token: secondToken,
                toolName: "Bash",
                toolInput: ["command": "git status"]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }
}
