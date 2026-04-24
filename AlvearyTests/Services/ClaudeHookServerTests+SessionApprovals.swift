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

    func testBashCommandWithSubcommandSupportsExactAndGroupSessionApproval() {
        let request = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: #"{"command":"swift test --filter ClaudeAdapterTests"}"#
        )

        XCTAssertEqual(request.supportedSessionApprovalScopes, [.exact, .group])
    }

    func testBashCommandWithLeadingOptionOnlySupportsExactSessionApproval() {
        let request = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: #"{"command":"git -C repo status"}"#
        )

        XCTAssertEqual(request.supportedSessionApprovalScopes, [.exact])
    }

    func testHookEndpointDoesNotApplyGroupApprovalThroughLeadingOptionOperand() async throws {
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
                matchValue: "git repo"
            )
        )

        let response = await server.handle(
            request(
                token: token,
                toolName: "Bash",
                toolInput: ["command": "git -C repo status"]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "defer")
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

    func testToolApprovalSelectionPersistsAcrossServerRestart() async {
        let supportDirectory = temporarySupportDirectory()
        let firstServer = DefaultClaudeHookServer(supportDirectory: supportDirectory)

        await firstServer.recordToolApprovalSelection(
            .sessionGroup,
            providerId: "claude",
            conversationId: "conversation-1",
            sessionId: "session-123"
        )

        let secondServer = DefaultClaudeHookServer(supportDirectory: supportDirectory)
        let selection = await secondServer.toolApprovalSelection(
            providerId: "claude",
            conversationId: "conversation-1",
            sessionId: "session-123"
        )

        XCTAssertEqual(selection, .sessionGroup)
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

    func testRemoveSessionApprovalsRemovesStoredToolApprovalSelection() async {
        let supportDirectory = temporarySupportDirectory()
        let firstServer = DefaultClaudeHookServer(supportDirectory: supportDirectory)
        await firstServer.recordToolApprovalSelection(
            .sessionExact,
            providerId: "claude",
            conversationId: "conversation-1",
            sessionId: "session-123"
        )

        await firstServer.removeSessionApprovals(conversationId: "conversation-1", sessionId: "session-123")

        let secondServer = DefaultClaudeHookServer(supportDirectory: supportDirectory)
        let selection = await secondServer.toolApprovalSelection(
            providerId: "claude",
            conversationId: "conversation-1",
            sessionId: "session-123"
        )

        XCTAssertNil(selection)
    }

    func testHookEndpointConsumesTransientExactApprovalDecisionOnce() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        await server.recordTransientApprovalDecision(
            ClaudeToolApprovalResolution(decision: .allow),
            for: exactBashGrant(conversationId: "conversation-1", command: "date")
        )

        let firstResponse = await server.handle(
            request(
                token: token,
                toolName: "Bash",
                toolUseId: "regenerated-tool-1",
                toolInput: ["command": "date"]
            )
        )
        let secondResponse = await server.handle(
            request(
                token: token,
                toolName: "Bash",
                toolUseId: "regenerated-tool-2",
                toolInput: ["command": "date"]
            )
        )

        XCTAssertEqual(try hookDecision(from: firstResponse), "allow")
        XCTAssertEqual(try hookDecision(from: secondResponse), "defer")
    }

    func testRemoveSessionApprovalsRemovesTransientExactApprovalDecisions() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        await server.recordTransientApprovalDecision(
            ClaudeToolApprovalResolution(decision: .allow),
            for: exactBashGrant(conversationId: "conversation-1", command: "date")
        )

        await server.removeSessionApprovals(conversationId: "conversation-1", sessionId: "session-123")
        let response = await server.handle(
            request(
                token: token,
                toolName: "Bash",
                toolUseId: "regenerated-tool-1",
                toolInput: ["command": "date"]
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

    private func exactBashGrant(conversationId: String, command: String) -> AgentSessionApprovalGrant {
        AgentSessionApprovalGrant(
            providerId: "claude",
            conversationId: conversationId,
            sessionId: "session-123",
            matchKind: .bashExact,
            matchValue: command
        )
    }

}
