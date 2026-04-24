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

enum ToolApprovalSelection: String, Sendable, Equatable, Hashable {
    case once
    case sessionExact
    case sessionGroup

    init(sessionScope: ToolApprovalSessionScope) {
        switch sessionScope {
        case .exact:
            self = .sessionExact
        case .group:
            self = .sessionGroup
        }
    }

    var sessionScope: ToolApprovalSessionScope? {
        switch self {
        case .once:
            return nil
        case .sessionExact:
            return .exact
        case .sessionGroup:
            return .group
        }
    }

    func normalized(for availableScopes: [ToolApprovalSessionScope]) -> ToolApprovalSelection {
        guard let sessionScope else {
            return .once
        }
        if availableScopes.contains(sessionScope) {
            return self
        }
        if let firstScope = availableScopes.first {
            return ToolApprovalSelection(sessionScope: firstScope)
        }
        return .once
    }
}

enum ClaudeToolApprovalDecision: String, Sendable, Equatable {
    case allow
    case deny
}

struct ClaudeToolApprovalResolution: Sendable, Equatable {
    let decision: ClaudeToolApprovalDecision
    let updatedInput: String?

    init(decision: ClaudeToolApprovalDecision, updatedInput: String? = nil) {
        self.decision = decision
        self.updatedInput = updatedInput
    }
}

enum AgentSessionApprovalRuleKind: String, Sendable, Equatable, Hashable {
    case bashExact
    case bashCommandGroup
    case filePathExact
}

struct AgentSessionApprovalGrant: Sendable, Equatable, Hashable {
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

struct DeferredToolComposerStatusText: Sendable, Equatable {
    let progressLabel: String
    let placeholder: String

    static let genericApproval = DeferredToolComposerStatusText(
        progressLabel: "Waiting for approval...",
        placeholder: "Waiting for tool approval..."
    )

    static let askUserQuestion = DeferredToolComposerStatusText(
        progressLabel: "Waiting for question response...",
        placeholder: "Answer the pending question in the transcript..."
    )

    static let exitPlanMode = DeferredToolComposerStatusText(
        progressLabel: "Waiting for plan approval...",
        placeholder: "Approve or deny the plan exit in the transcript..."
    )
}

struct ToolApprovalPromptCopy: Sendable, Equatable {
    let title: String
    let showsDisplayName: Bool
    let approveTitle: String
    let approvedTitle: String
    let denyTitle: String
    let deniedTitle: String

    static let generic = ToolApprovalPromptCopy(
        title: "Approve tool use?",
        showsDisplayName: true,
        approveTitle: "Approve",
        approvedTitle: "Approved",
        denyTitle: "Deny",
        deniedTitle: "Denied"
    )

    static let exitPlanMode = ToolApprovalPromptCopy(
        title: "Ready to leave plan mode?",
        showsDisplayName: false,
        approveTitle: "Leave plan mode",
        approvedTitle: "Leaving plan mode",
        denyTitle: "Keep planning",
        deniedTitle: "Continuing plan mode"
    )
}

struct ToolApprovalRequest: Sendable, Equatable, Identifiable {
    let sessionId: String
    let toolUseId: String
    let toolName: String
    let toolInput: String

    var id: String { toolUseId }

    var composerStatusText: DeferredToolComposerStatusText {
        switch toolName {
        case "AskUserQuestion":
            return .askUserQuestion
        case "ExitPlanMode":
            return .exitPlanMode
        default:
            return .genericApproval
        }
    }

    var approvalPromptCopy: ToolApprovalPromptCopy {
        switch toolName {
        case "ExitPlanMode":
            return .exitPlanMode
        default:
            return .generic
        }
    }

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
        case "EnterPlanMode":
            return "Enter plan mode"
        case "ExitPlanMode":
            return "Exit plan mode"
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
        case "EnterPlanMode":
            candidate = "Switch the session into plan mode"
        case "ExitPlanMode":
            candidate = "Present the plan and leave plan mode"
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

    func askUserQuestionUpdatedInput(
        answers: [(question: String, answer: String)]
    ) -> String? {
        guard toolName == "AskUserQuestion",
              let data = toolInput.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        var answerMap: [String: String] = [:]
        for answer in answers {
            answerMap[answer.question] = answer.answer
        }
        object["answers"] = answerMap

        guard let updatedData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: updatedData, encoding: .utf8)
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

        guard tokens.count >= 2 else {
            return nil
        }

        let groupToken = tokens[1]
        guard Self.isCommandGroupToken(groupToken) else {
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

struct ClaudeDeferredToolRequest: Sendable, Equatable {
    let conversationId: String
    let launchToken: String?
    let request: ToolApprovalRequest
}

protocol ClaudeHookServer: Actor {
    func setDeferredToolRequestHandler(
        _ handler: (@Sendable (ClaudeDeferredToolRequest) async -> Void)?
    ) async
    func prepareLaunch(
        permissionMode: String?,
        conversationId: String
    ) async -> ClaudeHookLaunchConfig?
    func updatePermissionMode(_ permissionMode: String?, for conversationId: String) async
    func recordDecision(_ resolution: ClaudeToolApprovalResolution, for key: ClaudeToolApprovalKey) async
    func recordTransientApprovalDecision(
        _ resolution: ClaudeToolApprovalResolution,
        for approval: AgentSessionApprovalGrant
    ) async
    func discardTransientApprovalDecision(for approval: AgentSessionApprovalGrant) async
    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) async -> SessionApprovalRecordResult
    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async
    func toolApprovalSelection(providerId: String, conversationId: String, sessionId: String) async -> ToolApprovalSelection?
    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async
    func removeSessionApprovals(conversationId: String, sessionId: String) async
    func discardDecision(for key: ClaudeToolApprovalKey) async
    func invalidateToken(_ token: String) async
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
