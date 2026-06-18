import AgentCLIKit
import Foundation

@testable import Alveary

struct PathResolvingAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let executableName: String
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
            executable: "/usr/bin/env",
            arguments: [executableName],
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

actor AgentInteractionResolutionRecorder {
    private var recordedResolutions: [AgentCLIKit.AgentInteractionResolution] = []

    func record(_ resolution: AgentCLIKit.AgentInteractionResolution) {
        recordedResolutions.append(resolution)
    }

    func resolutions() -> [AgentCLIKit.AgentInteractionResolution] {
        recordedResolutions
    }
}

struct ResolvingAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "printf 'interaction:tool\\n'; read resolution; printf 'message:resolved:%s\\n' \"$resolution\""
            ],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if line == "interaction:tool" {
            return [.interaction(AgentCLIKit.AgentInteractionEvent(
                id: "tool-1",
                kind: .approval,
                prompt: "Bash",
                metadata: [
                    "session_id": .string("session-1"),
                    "tool_name": .string("Bash"),
                    "tool_input": .object(["command": .string("pwd")])
                ]
            ))]
        }
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        switch input {
        case .userMessage, .interrupt:
            return Data()
        case .interactionResolution(let resolution):
            await resolutionRecorder?.record(resolution)
            return Data("\(resolution.outcome.rawValue)\n".utf8)
        }
    }
}

struct SteeringEchoAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
            arguments: ["-c", "while IFS= read -r line; do printf 'message:%s\\n' \"$line\"; done"],
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
        guard case .userMessage(let message) = input else {
            return Data()
        }

        let isSteering: Bool
        if case .bool(true)? = message.metadata[AgentCLIKit.AgentSteeringMetadata.isSteering] {
            isSteering = true
        } else {
            isSteering = false
        }

        let inputID: String
        if case .string(let value)? = message.metadata[AgentCLIKit.AgentSteeringMetadata.inputId] {
            inputID = value
        } else {
            inputID = ""
        }

        return Data("steering:\(isSteering):\(inputID):\(message.text)\n".utf8)
    }
}
