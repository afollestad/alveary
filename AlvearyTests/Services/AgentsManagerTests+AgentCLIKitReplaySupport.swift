import AgentCLIKit
import Foundation

@testable import Alveary

struct AgentCLIKitManagerFixture {
    let manager: DefaultAgentsManager
    let runtime: AgentCLIKit.DefaultAgentRuntime
    let sessionStore: AgentCLIKit.JSONFileAgentSessionStore
    let approvalStore: AgentCLIKit.ClaudeApprovalPolicyStore
    let liveHookDecisionProvider: AgentCLIKitLiveHookDecisionProvider
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
        let command = launch == 1 ? "printf '%s\\n' \"$1\"; sleep 5" : "printf '%s\\n' \"$1\""
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
