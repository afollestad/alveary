import Darwin
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
        await server.recordDecision(.allow, for: key)

        let firstResponse = await server.handle(request(token: token, toolName: "Bash"))
        let secondResponse = await server.handle(request(token: token, toolName: "Bash"))

        XCTAssertEqual(try hookDecision(from: firstResponse), "allow")
        XCTAssertEqual(try hookDecision(from: secondResponse), "defer")
    }

    func testHookEndpointConsumesOneShotDenyDecision() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        let key = ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")
        await server.recordDecision(.deny, for: key)

        let response = await server.handle(request(token: token, toolName: "Bash"))

        XCTAssertEqual(try hookDecision(from: response), "deny")
    }

    func testHookEndpointDoesNotConsumeDiscardedDecision() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        let key = ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")
        await server.recordDecision(.allow, for: key)

        await server.discardDecision(for: key)
        let response = await server.handle(request(token: token, toolName: "Bash"))

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testHookListenerStartsOnEphemeralLoopbackPort() async throws {
        let listener = ClaudeHookHTTPListener { _ in .empty() }
        defer { listener.cancel() }

        let port = try await listener.start()

        XCTAssertGreaterThan(port, 0)
    }

    func testHookListenerReportsUnavailableWhenCancelled() async throws {
        let expectation = expectation(description: "listener unavailable")
        let listener = ClaudeHookHTTPListener(
            onUnavailable: {
                expectation.fulfill()
            },
            handler: { _ in .empty() }
        )

        _ = try await listener.start()
        listener.cancel()

        await fulfillment(of: [expectation], timeout: 0.5)
    }

    func testHookListenerDeniesOversizedRequestsWithTwoHundred() async throws {
        let listener = ClaudeHookHTTPListener { _ in .empty(statusCode: 500) }
        defer { listener.cancel() }

        let port = try await listener.start()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/claude/hooks/pre-tool-use"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(repeating: UInt8(ascii: "x"), count: 300 * 1024)

        let (data, response) = try await URLSession.shared.data(for: request)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try hookDecision(from: data), "deny")
    }

    func testHookListenerDeniesIncompleteClosedRequestsWithTwoHundred() async throws {
        let listener = ClaudeHookHTTPListener { _ in .empty(statusCode: 500) }
        defer { listener.cancel() }

        let port = try await listener.start()
        let responseData = try readRawHTTPResponse(
            port: port,
            payload: """
            POST /claude/hooks/pre-tool-use HTTP/1.1\r
            Host: 127.0.0.1\r
            Content-Length: 20\r
            \r
            {}
            """
        )
        let response = String(data: responseData, encoding: .utf8)

        XCTAssertTrue(response?.hasPrefix("HTTP/1.1 200 OK") == true)
        XCTAssertEqual(try hookDecision(from: httpBody(from: responseData)), "deny")
    }

    func testHookListenerDeniesNegativeContentLengthWithTwoHundred() async throws {
        let listener = ClaudeHookHTTPListener { _ in .empty(statusCode: 500) }
        defer { listener.cancel() }

        let port = try await listener.start()
        let responseData = try readRawHTTPResponse(
            port: port,
            payload: """
            POST /claude/hooks/pre-tool-use HTTP/1.1\r
            Host: 127.0.0.1\r
            Content-Length: -1\r
            \r

            """
        )
        let response = String(data: responseData, encoding: .utf8)

        XCTAssertTrue(response?.hasPrefix("HTTP/1.1 200 OK") == true)
        XCTAssertEqual(try hookDecision(from: httpBody(from: responseData)), "deny")
    }

    func request(
        token: String,
        toolName: String,
        toolInput: [String: Any] = [:]
    ) -> ClaudeHookHTTPRequest {
        let body: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "session-123",
            "tool_use_id": "tool-1",
            "tool_name": toolName,
            "tool_input": toolInput
        ]
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

    func hookDecision(from body: Data) throws -> String? {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        return output["permissionDecision"] as? String
    }

    private func httpBody(from responseData: Data) throws -> Data {
        let separator = Data("\r\n\r\n".utf8)
        let range = try XCTUnwrap(responseData.range(of: separator))
        return Data(responseData[range.upperBound...])
    }

    private func readRawHTTPResponse(port: UInt16, payload: String) throws -> Data {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw posixError()
        }
        defer { close(socketFD) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(socketFD, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            throw posixError()
        }

        let bytes = Array(payload.utf8)
        let sent = bytes.withUnsafeBytes { buffer in
            Darwin.write(socketFD, buffer.baseAddress, buffer.count)
        }
        guard sent == bytes.count else {
            throw posixError()
        }

        shutdown(socketFD, SHUT_WR)
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(socketFD, &buffer, buffer.count)
            if count > 0 {
                response.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                return response
            } else if errno != EINTR {
                throw posixError()
            }
        }
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    func temporarySupportDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
