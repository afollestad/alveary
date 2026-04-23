import Foundation

struct ClaudeHookLaunchConfig: Sendable, Equatable {
    let arguments: [String]
    let environment: [String: String]
}

struct ClaudeToolApprovalKey: Sendable, Hashable {
    let sessionId: String
    let toolUseId: String
}

enum ToolApprovalSessionScope: String, CaseIterable, Sendable, Equatable {
    case exact
    case group

    var pendingTitle: String {
        switch self {
        case .exact:
            return "Approve exactly"
        case .group:
            return "Approve group"
        }
    }

    var resolvedTitle: String {
        switch self {
        case .exact:
            return "Approved exactly"
        case .group:
            return "Approved group"
        }
    }
}

enum ClaudeToolApprovalDecision: String, Sendable, Equatable {
    case allow
    case deny
}

enum AgentSessionApprovalRuleKind: String, Sendable, Equatable {
    case bashExact
    case bashCommandGroup
    case filePathExact
}

struct AgentSessionApprovalGrant: Sendable, Equatable {
    let providerId: String
    let conversationId: String
    let sessionId: String
    let matchKind: AgentSessionApprovalRuleKind
    let matchValue: String
}

struct SessionApprovalRecordResult: Sendable, Equatable {
    let isEffective: Bool
    let wasInserted: Bool
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
        let parsedInput = parsedInput
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

    var supportedSessionApprovalScopes: [ToolApprovalSessionScope] {
        switch toolName {
        case "Bash":
            var scopes: [ToolApprovalSessionScope] = []
            if sessionApprovalMatch(for: .exact) != nil {
                scopes.append(.exact)
            }
            if sessionApprovalMatch(for: .group) != nil {
                scopes.append(.group)
            }
            return scopes
        case "Write", "Edit", "MultiEdit", "NotebookEdit":
            return sessionApprovalMatch(for: .exact) == nil ? [] : [.exact]
        default:
            return []
        }
    }

    func sessionApprovalGrant(
        conversationId: String,
        providerId: String,
        scope: ToolApprovalSessionScope
    ) -> AgentSessionApprovalGrant? {
        guard let match = sessionApprovalMatch(for: scope) else {
            return nil
        }

        return AgentSessionApprovalGrant(
            providerId: providerId,
            conversationId: conversationId,
            sessionId: sessionId,
            matchKind: match.kind,
            matchValue: match.value
        )
    }

    func sessionApprovalMatch(
        for scope: ToolApprovalSessionScope
    ) -> (kind: AgentSessionApprovalRuleKind, value: String)? {
        switch (toolName, scope) {
        case ("Bash", .exact):
            guard let command = normalizedBashCommand else {
                return nil
            }
            return (.bashExact, command)
        case ("Bash", .group):
            guard let commandGroup = bashCommandGroup else {
                return nil
            }
            return (.bashCommandGroup, commandGroup)
        case ("Write", .exact), ("Edit", .exact), ("MultiEdit", .exact), ("NotebookEdit", .exact):
            guard let path = normalizedApprovalPath else {
                return nil
            }
            return (.filePathExact, path)
        default:
            return nil
        }
    }

    private var parsedInput: [String: String] {
        Self.parseInput(toolInput)
    }

    private var normalizedBashCommand: String? {
        parsedInput["command"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private var normalizedApprovalPath: String? {
        (parsedInput["file_path"] ?? parsedInput["path"] ?? parsedInput["notebook_path"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private var bashCommandGroup: String? {
        guard let command = normalizedBashCommand else {
            return nil
        }
        guard !Self.containsShellControlOperator(command) else {
            return nil
        }

        let tokens = (try? parseExtraArgs(command)).flatMap { $0.isEmpty ? nil : $0 } ?? Self.fallbackCommandTokens(command)
        guard let executable = tokens.first?.nilIfEmpty else {
            return nil
        }

        guard let groupToken = tokens.dropFirst().first(where: Self.isCommandGroupToken)?.nilIfEmpty else {
            return nil
        }
        return [executable, groupToken]
            .joined(separator: " ")
            .nilIfEmpty
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

    private static func fallbackCommandTokens(_ command: String) -> [String] {
        command
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func isCommandGroupToken(_ token: String) -> Bool {
        guard !token.isEmpty, !token.hasPrefix("-") else {
            return false
        }

        return token.rangeOfCharacter(from: CharacterSet(charactersIn: "./")) == nil
    }

    private static func containsShellControlOperator(_ command: String) -> Bool {
        let controlCharacters = CharacterSet(charactersIn: "&;|<>")
        var activeQuote: Character?
        var isEscaping = false

        for character in command {
            if isEscaping {
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if character == "\"" || character == "'" {
                if activeQuote == character {
                    activeQuote = nil
                } else if activeQuote == nil {
                    activeQuote = character
                }
                continue
            }

            guard activeQuote == nil else {
                continue
            }

            if let scalar = character.unicodeScalars.first,
               controlCharacters.contains(scalar) {
                return true
            }
        }

        return false
    }
}

enum ToolApprovalStatus: String, Sendable, Equatable {
    case pending
    case approving
    case denying
    case approvingForSessionExact
    case approvingForSessionGroup
    case approved
    case approvedForSessionExact
    case approvedForSessionGroup
    case denied
    case superseded
}

struct PendingToolApproval: Sendable, Equatable {
    var request: ToolApprovalRequest
    var status: ToolApprovalStatus
}

protocol ClaudeHookServer: Actor {
    func prepareLaunch(
        permissionMode: String?,
        conversationId: String
    ) async -> ClaudeHookLaunchConfig?
    func recordDecision(_ decision: ClaudeToolApprovalDecision, for key: ClaudeToolApprovalKey) async
    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) async -> SessionApprovalRecordResult
    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async
    func removeSessionApprovals(conversationId: String, sessionId: String) async
    func discardDecision(for key: ClaudeToolApprovalKey) async
    func invalidateToken(_ token: String) async
}

actor DisabledClaudeHookServer: ClaudeHookServer {
    func prepareLaunch(
        permissionMode: String?,
        conversationId: String
    ) async -> ClaudeHookLaunchConfig? {
        nil
    }

    func recordDecision(_ decision: ClaudeToolApprovalDecision, for key: ClaudeToolApprovalKey) async {}
    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) async -> SessionApprovalRecordResult {
        SessionApprovalRecordResult(isEffective: false, wasInserted: false)
    }
    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async {}
    func removeSessionApprovals(conversationId: String, sessionId: String) async {}
    func discardDecision(for key: ClaudeToolApprovalKey) async {}
    func invalidateToken(_ token: String) async {}
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
