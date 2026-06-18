import AgentCLIKit
import Foundation

@testable import Alveary

struct ParallelApprovalResolutionAdapter: AgentCLIKit.AgentProviderAdapter {
    let counter = AgentCLIKitLaunchCounter()
    let providerId: AgentCLIKit.AgentProviderID
    let resolutionRecorder: AgentInteractionResolutionRecorder?

    init(
        providerId: AgentCLIKit.AgentProviderID = .claude,
        resolutionRecorder: AgentInteractionResolutionRecorder? = nil
    ) {
        self.providerId = providerId
        self.resolutionRecorder = resolutionRecorder
    }

    var definition: AgentCLIKit.AgentProviderDefinition {
        AgentCLIKit.AgentProviderDefinition(
            id: providerId,
            displayName: providerId.rawValue.capitalized,
            executableNames: [providerId.rawValue]
        )
    }

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        let launch = await counter.next()
        // The deferred launch idles on stdin like the real CLI so the runtime's stdin-close teardown ends it.
        let script = launch == 1
            ? "printf 'approval:tool-1\\napproval:tool-2\\ndeferred\\n'; cat > /dev/null"
            : """
            first=
            second=
            while IFS= read -r line; do
              case "$line" in
                *tool-1*approved*) first=1 ;;
                *tool-2*approved*) second=1 ;;
              esac
              if [ "$first$second" = "11" ]; then
                printf 'message:resumed-both\\n'
                exit 0
              fi
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
        if let toolId = line.removingPrefix("approval:") {
            return [.interaction(approvalEvent(toolId: toolId))]
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
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        switch input {
        case .interactionResolution(let resolution):
            await resolutionRecorder?.record(resolution)
            return Data("resolution:\(resolution.id.rawValue):\(resolution.outcome.rawValue)\n".utf8)
        case .userMessage, .interrupt:
            return Data()
        }
    }

    private func approvalEvent(toolId: String) -> AgentCLIKit.AgentInteractionEvent {
        AgentCLIKit.AgentInteractionEvent(
            id: AgentCLIKit.AgentInteractionID(rawValue: toolId),
            kind: .approval,
            prompt: "Bash",
            metadata: [
                "session_id": .string("session-1"),
                "tool_name": .string("Bash"),
                "tool_input": .object(["command": .string(toolId)])
            ]
        )
    }
}
