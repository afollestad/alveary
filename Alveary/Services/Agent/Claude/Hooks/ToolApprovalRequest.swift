import Foundation

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
    let approveTitle: String
    let approvedTitle: String
    let denyTitle: String
    let deniedTitle: String

    static let generic = ToolApprovalPromptCopy(
        title: "Approve tool use?",
        approveTitle: "Approve",
        approvedTitle: "Approved",
        denyTitle: "Deny",
        deniedTitle: "Denied"
    )

    static let exitPlanMode = ToolApprovalPromptCopy(
        title: "Ready to leave plan mode?",
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
    let planMarkdownFallback: String?

    var id: String { toolUseId }

    init(
        sessionId: String,
        toolUseId: String,
        toolName: String,
        toolInput: String,
        planMarkdownFallback: String? = nil
    ) {
        self.sessionId = sessionId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.toolInput = toolInput
        self.planMarkdownFallback = planMarkdownFallback
    }

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

    var conciseSummary: String {
        let parsedInput = parsedInput
        let candidate: String?
        switch toolName {
        case "Bash":
            candidate = parsedInput["command"]
        case "Write", "Edit", "MultiEdit", "NotebookEdit":
            candidate = Self.displayApprovalPath(
                parsedInput["file_path"] ?? parsedInput["path"] ?? parsedInput["notebook_path"]
            )
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

    var planMarkdown: String? {
        guard toolName == "ExitPlanMode" else {
            return nil
        }

        let explicitPlan = parsedInput["plan"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let fallbackPlan = planMarkdownFallback?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        return explicitPlan ?? fallbackPlan
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

    static func approvalPromptTitle(for approvals: [ToolApprovalRequest]) -> String {
        // Keep header copy here so transcript views do not grow duplicate
        // tool-family switches just to choose singular/plural approval wording.
        guard let firstApproval = approvals.first else {
            return ToolApprovalPromptCopy.generic.title
        }

        guard approvals.count > 1 else {
            return firstApproval.approvalPromptTitle(isPlural: false)
        }

        guard approvals.allSatisfy({ $0.toolName == firstApproval.toolName }) else {
            return "Approve tool uses?"
        }

        return firstApproval.approvalPromptTitle(isPlural: true)
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

    func withPlanMarkdownFallback(_ fallback: String) -> ToolApprovalRequest {
        ToolApprovalRequest(
            sessionId: sessionId,
            toolUseId: toolUseId,
            toolName: toolName,
            toolInput: toolInput,
            planMarkdownFallback: fallback
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

    private func approvalPromptTitle(isPlural: Bool) -> String {
        switch toolName {
        case "Bash":
            return "Approve Bash \(isPlural ? "commands" : "command")?"
        case "Write":
            return "Approve writing to \(isPlural ? "files" : "a file")?"
        case "Edit", "MultiEdit":
            return "Approve editing \(isPlural ? "files" : "a file")?"
        case "NotebookEdit":
            return "Approve editing \(isPlural ? "notebooks" : "a notebook")?"
        case "EnterPlanMode":
            return "Approve entering plan mode?"
        case "ExitPlanMode":
            return approvalPromptCopy.title
        default:
            return genericApprovalPromptTitle(isPlural: isPlural)
        }
    }

    private func genericApprovalPromptTitle(isPlural: Bool) -> String {
        if toolName.hasPrefix("mcp__") {
            return "Approve MCP tool \(isPlural ? "uses" : "use")?"
        }
        return "Approve \(toolName) tool \(isPlural ? "uses" : "use")?"
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

    private static func displayApprovalPath(_ path: String?) -> String? {
        // Approval summaries should show the exact path being approved, while
        // still using the transcript's canonical home-abbreviated path style.
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return CanonicalPath.displayMentionPath(path, relativeTo: nil)
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
