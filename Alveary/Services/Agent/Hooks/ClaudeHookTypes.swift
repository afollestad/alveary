import Foundation

struct ClaudeHookLaunchConfig: Sendable, Equatable {
    let arguments: [String]
    let environment: [String: String]
}

struct ClaudeToolApprovalKey: Sendable, Hashable {
    let sessionId: String
    let toolUseId: String
}

enum ClaudeToolApprovalDecision: String, Sendable, Equatable {
    case allow
    case deny
}

struct ToolApprovalRequest: Sendable, Equatable, Identifiable {
    let sessionId: String
    let toolUseId: String
    let toolName: String
    let toolInput: String

    var id: String { toolUseId }

    var displayName: String {
        switch toolName {
        case "Bash":
            return "Bash command"
        case "Write":
            return "Write file"
        case "Edit", "MultiEdit":
            return "Edit file"
        case "NotebookEdit":
            return "Edit notebook"
        default:
            return toolName
        }
    }

    var conciseSummary: String {
        let parsedInput = Self.parseInput(toolInput)
        let candidate: String?
        switch toolName {
        case "Bash":
            candidate = parsedInput["command"]
        case "Write", "Edit", "MultiEdit", "NotebookEdit":
            candidate = parsedInput["file_path"] ?? parsedInput["path"] ?? parsedInput["notebook_path"]
        default:
            candidate = parsedInput["file_path"] ?? parsedInput["path"] ?? parsedInput["command"]
        }

        return Self.truncated(
            candidate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Review requested tool input"
        )
    }

    private static func parseInput(_ input: String) -> [String: String] {
        guard let data = input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        return object.reduce(into: [:]) { partialResult, entry in
            if let string = entry.value as? String {
                partialResult[entry.key] = string
            }
        }
    }

    private static func truncated(_ value: String, limit: Int = 140) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit - 1)) + "..."
    }
}

enum ToolApprovalStatus: String, Sendable, Equatable {
    case pending
    case approving
    case denying
    case approved
    case denied
}

struct PendingToolApproval: Sendable, Equatable {
    var request: ToolApprovalRequest
    var status: ToolApprovalStatus
}

protocol ClaudeHookServer: Actor {
    func prepareLaunch(permissionMode: String?) async -> ClaudeHookLaunchConfig?
    func recordDecision(_ decision: ClaudeToolApprovalDecision, for key: ClaudeToolApprovalKey) async
    func discardDecision(for key: ClaudeToolApprovalKey) async
    func invalidateToken(_ token: String) async
}

actor DisabledClaudeHookServer: ClaudeHookServer {
    func prepareLaunch(permissionMode: String?) async -> ClaudeHookLaunchConfig? {
        nil
    }

    func recordDecision(_ decision: ClaudeToolApprovalDecision, for key: ClaudeToolApprovalKey) async {}
    func discardDecision(for key: ClaudeToolApprovalKey) async {}
    func invalidateToken(_ token: String) async {}
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
