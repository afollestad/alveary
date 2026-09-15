import AgentCLIKit
import Foundation

@testable import Alveary

actor PathResolvingLaunchRecorder {
    struct Launch: Equatable, Sendable {
        let resumedHarnessSessionID: String?
        let forksSession: Bool
    }

    private var launches: [Launch] = []

    func record(
        resumedSession: AgentCLIKit.AgentSessionRecord?,
        spawnConfig: AgentCLIKit.AgentSpawnConfig
    ) {
        launches.append(Launch(
            resumedHarnessSessionID: resumedSession?.harnessSessionId.rawValue,
            forksSession: spawnConfig.forkSession
        ))
    }

    func values() -> [Launch] {
        launches
    }
}

struct PathResolvingAgentCLIKitAdapter: AgentCLIKit.AgentHarnessAdapter {
    let executableName: String
    let launchRecorder: PathResolvingLaunchRecorder?
    let definition = AgentCLIKit.AgentHarnessDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    init(
        executableName: String,
        launchRecorder: PathResolvingLaunchRecorder? = nil
    ) {
        self.executableName = executableName
        self.launchRecorder = launchRecorder
    }

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        await launchRecorder?.record(
            resumedSession: resumedSession,
            spawnConfig: spawnConfig
        )
        return AgentCLIKit.AgentLaunchConfiguration(
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

struct ResolvingAgentCLIKitAdapter: AgentCLIKit.AgentHarnessAdapter {
    let harnessId: AgentCLIKit.AgentHarnessID
    let resolutionRecorder: AgentInteractionResolutionRecorder?

    init(
        harnessId: AgentCLIKit.AgentHarnessID = .claude,
        resolutionRecorder: AgentInteractionResolutionRecorder? = nil
    ) {
        self.harnessId = harnessId
        self.resolutionRecorder = resolutionRecorder
    }

    var definition: AgentCLIKit.AgentHarnessDefinition {
        AgentCLIKit.AgentHarnessDefinition(
            id: harnessId,
            displayName: harnessId.rawValue.capitalized,
            executableNames: [harnessId.rawValue]
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

struct SteeringEchoAgentCLIKitAdapter: AgentCLIKit.AgentHarnessAdapter {
    let definition = AgentCLIKit.AgentHarnessDefinition(
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

actor GoalStartingAgentCLIKitRecorder {
    struct Call: Sendable, Equatable {
        let objective: String
        let conversationId: String
    }

    private var recordedCalls: [Call] = []

    func record(objective: String, conversationId: String) {
        recordedCalls.append(Call(objective: objective, conversationId: conversationId))
    }

    func calls() -> [Call] {
        recordedCalls
    }
}

struct GoalStartingAgentCLIKitAdapter: AgentCLIKit.AgentHarnessAdapter {
    let recorder: GoalStartingAgentCLIKitRecorder

    let definition = AgentCLIKit.AgentHarnessDefinition(
        id: .codex,
        displayName: "Codex",
        executableNames: ["codex"],
        capabilities: AgentCLIKit.AgentHarnessCapabilities(
            supportsGoalMode: true,
            supportsExistingSessionGoalStart: true
        )
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", "while IFS= read -r line; do :; done"],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }

    func startGoal(_ objective: String, context: AgentCLIKit.AgentHarnessGoalStartContext) async throws {
        await recorder.record(objective: objective, conversationId: context.conversationId.rawValue)
    }
}

/// Echoes `tasks:<count>`, `done:<task>`, and `active:<turn>` sentinels back as events and ends the
/// host turn after each, so a turn can finish while background tasks stay live.
struct BackgroundTaskAgentCLIKitAdapter: AgentCLIKit.AgentHarnessAdapter {
    let definition = AgentCLIKit.AgentHarnessDefinition(
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
                """
                while IFS= read -r line; do
                  case "$line" in
                    tasks:*|done:*|active:*) printf '%s\\nusage:end_turn\\n' "$line" ;;
                    finish) printf 'usage:end_turn\\n' ;;
                    *) printf 'usage:tool_use\\n' ;;
                  esac
                done
                """
            ],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let count = line.removingPrefix("tasks:").flatMap(Int.init) {
            let tasks = (0..<count).map { AgentCLIKit.AgentBackgroundTask(id: "task-\($0)", kind: "local_agent") }
            return [.backgroundTasks(AgentCLIKit.AgentBackgroundTasksEvent(tasks: tasks))]
        }
        if let taskId = line.removingPrefix("done:") {
            return [.subAgent(AgentCLIKit.AgentSubAgentEvent(
                id: "toolu_\(taskId)",
                phase: .terminal,
                status: "completed",
                metadata: [
                    AgentCLIKit.AgentBackgroundTaskMetadata.taskId: .string(taskId),
                    AgentCLIKit.AgentBackgroundTaskMetadata.delivery: .string(AgentCLIKit.AgentBackgroundTaskMetadata.dequeuedDelivery)
                ]
            ))]
        }
        if let turnId = line.removingPrefix("active:") {
            return [.activity(AgentCLIKit.AgentActivityEvent(state: .active, turnId: turnId, metadata: [:]))]
        }
        guard let stopReason = line.removingPrefix("usage:") else {
            return []
        }
        return [.usage(AgentCLIKit.AgentUsageEvent(
            model: nil,
            inputTokens: nil,
            outputTokens: nil,
            stopReason: stopReason
        ))]
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        if case let .userMessage(message) = input {
            return Data((message.text + "\n").utf8)
        }
        return Data()
    }
}
