import AgentCLIKit
import Foundation

@testable import Alveary

struct AgentCLIKitManagerFixture {
    let manager: DefaultAgentsManager
    let sessionManager: InMemorySessionManager
    let runtime: AgentCLIKit.DefaultAgentRuntime
    let sessionStore: AgentCLIKit.JSONFileAgentSessionStore
    let approvalStore: AgentCLIKit.ClaudeApprovalPolicyStore
    let liveHookDecisionProvider: AgentCLIKitLiveHookDecisionProvider
    let services: AgentCLIKitHostServices
}

struct ModelEchoingAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "printf 'message:%s\\n' \"$1\"",
                "agent",
                spawnConfig.model ?? "default"
            ],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }
}

struct DelayedReconfigureAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
        if launch == 2 {
            try? await Task.sleep(for: .milliseconds(120))
        }
        let script = launch == 1
            ? "printf 'message:first\\n'; sleep 0.05"
            : "printf 'message:second\\n'"
        return AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", script],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }
}

struct FailedReplacementAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
        if launch == 2 {
            return AgentCLIKit.AgentLaunchConfiguration(
                executable: "/no/such/executable",
                includesSpawnArguments: true
            )
        }
        return AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 0.2; printf 'message:old-after-failed-reconfigure\\n'; sleep 5"],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }
}

struct DeferredThenMessageAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
        let output = launch == 1 ? "approval" : "message:resumed"
        // The deferred launch idles on stdin like the real CLI so the runtime's stdin-close teardown ends it.
        let command = launch == 1 ? "printf '%s\\n' \"$1\"; cat > /dev/null" : "printf '%s\\n' \"$1\""
        return AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", command, "agent", output],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if line == "approval" {
            return [
                .interaction(AgentCLIKit.AgentInteractionEvent(
                    id: "tool-1",
                    kind: .approval,
                    prompt: "Bash",
                    metadata: [
                        "session_id": .string("session-1"),
                        "tool_name": .string("Bash"),
                        "tool_input": .object(["command": .string("pwd")])
                    ]
                )),
                .usage(AgentCLIKit.AgentUsageEvent(
                    model: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    stopReason: "tool_deferred",
                    metadata: ["stop_reason": .string("tool_deferred")]
                ))
            ]
        }
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }
}

struct RestoredApprovalCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'message:restored-resumed\\n'"],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }
}

struct RestoredPromptResolutionCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        let script = """
        while IFS= read -r line; do
          case "$line" in
            *prompt-restored*answered*) printf 'message:restored-resolved\\n'; exit 0 ;;
          esac
        done
        sleep 5
        """
        return AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", script],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        switch input {
        case .interactionResolution(let resolution):
            Data("resolution:\(resolution.id.rawValue):\(resolution.outcome.rawValue)\n".utf8)
        case .userMessage, .interrupt:
            Data()
        }
    }
}

struct DeferredReplayAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
        let output = launch == 1 ? "approval:first" : "approval:second\nmessage:resumed"
        return AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", "printf '%s\\n' \"$1\"", "agent", output],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let marker = line.removingPrefix("approval:") {
            return [
                .interaction(AgentCLIKit.AgentInteractionEvent(
                    id: "tool-1",
                    kind: .approval,
                    prompt: "Bash",
                    metadata: [
                        "session_id": .string("session-1"),
                        "tool_name": .string("Bash"),
                        "tool_input": .object(["command": .string("pwd")]),
                        "raw_event": .string(marker)
                    ]
                )),
                .usage(AgentCLIKit.AgentUsageEvent(
                    model: "claude",
                    inputTokens: marker == "first" ? 10 : 11,
                    outputTokens: marker == "first" ? 1 : 2,
                    durationMs: marker == "first" ? 100 : 200,
                    stopReason: "tool_deferred",
                    metadata: [
                        "stop_reason": .string("tool_deferred"),
                        "raw_event": .string(marker)
                    ]
                ))
            ]
        }
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }
}

struct DeferredDeltaReplayAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
            ? "delta:Running 4 tools in parallel now.\ntool:glob-old\nresult:glob-old\napproval:first"
            : "message:Running 4 tools in parallel now.\ntool:glob-new\nresult:glob-new\nmessage:resumed"
        return AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", "printf '%s\\n' \"$1\"", "agent", output],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let text = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: text))]
        }
        if let text = line.removingPrefix("delta:") {
            return [.messageDelta(AgentCLIKit.AgentMessageDeltaEvent(role: .assistant, text: text))]
        }
        if let toolId = line.removingPrefix("tool:") {
            return [.toolCall(AgentCLIKit.AgentToolCallEvent(
                id: toolId,
                name: "Glob",
                input: .object(["pattern": .string("**/*.html")])
            ))]
        }
        if let toolId = line.removingPrefix("result:") {
            return [.toolResult(AgentCLIKit.AgentToolResultEvent(id: toolId, isError: false, content: "index.html"))]
        }
        if let marker = line.removingPrefix("approval:") {
            return [
                .interaction(AgentCLIKit.AgentInteractionEvent(
                    id: "tool-1",
                    kind: .approval,
                    prompt: "Bash",
                    metadata: [
                        "session_id": .string("session-1"),
                        "tool_name": .string("Bash"),
                        "tool_input": .object(["command": .string("git status")]),
                        "raw_event": .string(marker)
                    ]
                )),
                .usage(AgentCLIKit.AgentUsageEvent(
                    model: "claude",
                    inputTokens: 10,
                    outputTokens: 1,
                    durationMs: 100,
                    stopReason: "tool_deferred",
                    metadata: [
                        "stop_reason": .string("tool_deferred"),
                        "raw_event": .string(marker)
                    ]
                ))
            ]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }
}

struct DelayedInitialLaunchAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        try await Task.sleep(for: .milliseconds(150))
        return AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 5"],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }
}

struct RawThenMessageAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "printf 'raw\\nmessage:first\\n'; while IFS= read -r line; do printf 'message:%s\\n' \"$line\"; done"
            ],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if line == "raw" {
            return [.rawOutput(AgentCLIKit.AgentRawOutputEvent(text: line, isComplete: true))]
        }
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        switch input {
        case .userMessage(let message):
            return Data("\(message.text)\n".utf8)
        case .interrupt, .interactionResolution:
            return Data()
        }
    }
}

actor AgentCLIKitLaunchCounter {
    private var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}

extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}
