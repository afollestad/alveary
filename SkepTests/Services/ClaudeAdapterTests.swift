import Foundation
import XCTest

@testable import Skep

final class ClaudeAdapterTests: XCTestCase {
    func testBuildArgsIncludesEachSupportedPermissionModeAndEffort() {
        let adapter = ClaudeAdapter()
        let permissionModes = DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry())
            .provider(for: "claude")?
            .supportedPermissionModes?
            .map(\.value) ?? []

        XCTAssertFalse(permissionModes.isEmpty)

        for permissionMode in permissionModes {
            let args = adapter.buildArgs(
                config: AgentConfig(
                    providerId: "claude",
                    sessionId: "session-123",
                    workingDirectory: "/tmp/project",
                    permissionMode: permissionMode,
                    model: "sonnet",
                    effort: "max",
                    initialPrompt: nil
                )
            )

            XCTAssertTrue(args.containsSubsequence(["--permission-mode", permissionMode]))
            XCTAssertTrue(args.containsSubsequence(["--model", "sonnet"]))
            XCTAssertTrue(args.containsSubsequence(["--effort", "max"]))
        }
    }

    func testSessionLaunchUsesResumeAndForkWhenArtifactExists() throws {
        let adapter = ClaudeAdapter()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        let sessionId = "session-123"
        let sessionFilePath = try XCTUnwrap(adapter.sessionFilePath(sessionId: sessionId, cwd: tempDirectory.path))
        let sessionFileURL = URL(fileURLWithPath: sessionFilePath)
        defer {
            try? FileManager.default.removeItem(at: sessionFileURL)
            try? FileManager.default.removeItem(at: sessionFileURL.deletingLastPathComponent())
        }
        try FileManager.default.createDirectory(
            at: sessionFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data().write(to: sessionFileURL)

        let decision = adapter.sessionLaunch(
            sessionId: sessionId,
            cwd: tempDirectory.path,
            isResuming: true,
            forkSession: true
        )

        XCTAssertEqual(
            decision,
            SessionLaunchDecision(args: ["--resume", sessionId, "--fork-session"], continuity: .preserved)
        )
    }

    func testSessionLaunchFallsBackToFreshSessionWhenArtifactIsMissing() {
        let adapter = ClaudeAdapter()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let decision = adapter.sessionLaunch(
            sessionId: "session-123",
            cwd: tempDirectory.path,
            isResuming: true,
            forkSession: true
        )

        XCTAssertEqual(
            decision,
            SessionLaunchDecision(args: ["--session-id", "session-123"], continuity: .restartedFresh)
        )
    }

    func testDecodePreservesParentToolUseIdAndToolMetadata() {
        let adapter = ClaudeAdapter()
        let json: [String: Any] = [
            "type": "user",
            "parent_tool_use_id": "agent-tool-1",
            "message": [
                "role": "user",
                "content": [[
                    "type": "tool_result",
                    "tool_use_id": "tool-1",
                    "is_error": false,
                    "content": "stdout text"
                ]]
            ],
            "tool_use_result": [
                "stderr": "stderr text",
                "interrupted": true,
                "isImage": false,
                "noOutputExpected": true
            ]
        ]

        let events = adapter.decode(json)

        XCTAssertEqual(
            events,
            [
                .toolResult(
                    id: "tool-1",
                    output: "stdout text",
                    isError: false,
                    parentToolUseId: "agent-tool-1",
                    metadata: ToolResultMetadata(
                        stderr: "stderr text",
                        interrupted: true,
                        isImage: false,
                        noOutputExpected: true
                    )
                )
            ]
        )
    }

    func testSendMessageWritesStructuredJSONLineToStdin() throws {
        let adapter = ClaudeAdapter()
        let process = Process()
        let pipe = Pipe()
        process.standardInput = pipe

        try adapter.sendMessage("hello world", to: process)
        pipe.fileHandleForWriting.closeFile()

        let payload = pipe.fileHandleForReading.readDataToEndOfFile()
        let payloadString = try XCTUnwrap(String(data: payload, encoding: .utf8))
        let trimmed = payloadString.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonData = try XCTUnwrap(trimmed.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let message = try XCTUnwrap(object["message"] as? [String: Any])
        let content = try XCTUnwrap(message["content"] as? [[String: Any]])

        XCTAssertEqual(object["type"] as? String, "user")
        XCTAssertEqual(message["role"] as? String, "user")
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "hello world")
    }
}

private extension [String] {
    func containsSubsequence(_ subsequence: [String]) -> Bool {
        guard !subsequence.isEmpty, subsequence.count <= count else {
            return subsequence.isEmpty
        }

        for startIndex in 0...(count - subsequence.count)
        where Array(self[startIndex..<(startIndex + subsequence.count)]) == subsequence {
            return true
        }

        return false
    }
}
