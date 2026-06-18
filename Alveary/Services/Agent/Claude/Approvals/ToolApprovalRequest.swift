import AgentCLIKit
import Foundation

/// Composer copy shown while a deferred tool or prompt is waiting for a user decision.
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

/// Button and title copy for a tool approval prompt.
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

/// Alveary's UI model for a Claude tool approval request.
///
/// `AgentCLIKit` owns the provider hook transport that creates these requests. This type owns
/// app-facing copy, summaries, supported session scopes, and updated-input helpers used by
/// transcript rows and approval controls.
struct ToolApprovalRequest: Sendable, Equatable, Identifiable {
    let sessionId: String
    let toolUseId: String
    let toolName: String
    let toolInput: String
    let approvalIdentityToolInput: String?
    let planMarkdownFallback: String?

    var id: String { toolUseId }

    /// Creates a request for a provider session tool approval.
    init(
        sessionId: String,
        toolUseId: String,
        toolName: String,
        toolInput: String,
        approvalIdentityToolInput: String? = nil,
        planMarkdownFallback: String? = nil
    ) {
        self.sessionId = sessionId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.toolInput = toolInput
        self.approvalIdentityToolInput = approvalIdentityToolInput
        self.planMarkdownFallback = planMarkdownFallback
    }

    /// Composer copy that reflects the tool family waiting on a decision.
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

    /// Whether this request represents an app-native prompt instead of a provider tool execution.
    var isAppNativeInteractionPrompt: Bool {
        toolName == "AskUserQuestion" || toolName == "ExitPlanMode"
    }

    /// Prompt copy for the transcript approval controls.
    var approvalPromptCopy: ToolApprovalPromptCopy {
        switch toolName {
        case "ExitPlanMode":
            return .exitPlanMode
        default:
            return .generic
        }
    }

    /// Short human-readable summary of the requested tool action.
    var conciseSummary: String {
        let parsedInput = parsedInput
        let candidate: String?
        switch toolName {
        case "Bash":
            candidate = normalizedBashCommand
        case "Write", "Edit", "MultiEdit", "NotebookEdit", "Read", "LS", "NotebookRead":
            candidate = Self.displayApprovalPath(
                parsedInput["file_path"] ?? parsedInput["path"] ?? parsedInput["notebook_path"]
            )
        case "Grep":
            candidate = Self.searchSummary(pattern: parsedInput["pattern"], path: parsedInput["path"])
        case "Glob":
            candidate = Self.searchSummary(pattern: parsedInput["pattern"], path: parsedInput["path"])
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

    /// Summary text shown inside transcript approval rows.
    var transcriptApprovalSummary: String? {
        switch toolName {
        case "ExitPlanMode":
            return nil
        default:
            return conciseSummary
        }
    }

    /// Notification body for the pending approval.
    var notificationMessage: String {
        if toolName == "AskUserQuestion" {
            return "Your agent has a question: \(askUserQuestionNotificationSummary)"
        }

        let title = Self.approvalPromptTitle(for: [self])
        return "Your agent needs permission: \(title) \(conciseSummary)"
    }

    /// Markdown plan payload for `ExitPlanMode`, including fallback transcript text when needed.
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

    /// Session approval scopes currently supported by this request.
    var supportedSessionApprovalScopes: [ToolApprovalSessionScope] {
        agentCLIKitSessionApprovalRequest.supportedSessionApprovalScopes.compactMap(Self.toolApprovalSessionScope)
    }

    /// Session approval scope that can be safely preselected for this request.
    var recommendedSessionApprovalScope: ToolApprovalSessionScope? {
        agentCLIKitSessionApprovalRequest.recommendedSessionApprovalScope.flatMap(Self.toolApprovalSessionScope)
    }

    /// Approval selection implied by the provider-owned recommendation, if any.
    var recommendedApprovalSelection: ToolApprovalSelection? {
        recommendedSessionApprovalScope.map(ToolApprovalSelection.init(sessionScope:))
    }

    /// Returns the prompt title for one or more same-family approval requests.
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

    /// Returns a durable approval grant for the selected reusable scope.
    func sessionApprovalGrant(
        conversationId: String,
        providerId: String,
        scope: ToolApprovalSessionScope
    ) -> AgentSessionApprovalGrant? {
        guard let agentProviderId = AgentCLIKit.AgentProviderID(rawValue: providerId),
              let agentScope = Self.agentCLIKitScope(scope),
              let grant = agentCLIKitSessionApprovalRequest(
                conversationId: conversationId,
                providerId: agentProviderId
              ).sessionApprovalGrant(for: agentScope),
              let matchKind = Self.agentSessionApprovalRuleKind(grant.matchKind) else {
            return nil
        }

        return AgentSessionApprovalGrant(
            providerId: grant.providerId.rawValue,
            conversationId: grant.conversationId.rawValue,
            sessionId: grant.sessionId.rawValue,
            matchKind: matchKind,
            matchValue: grant.matchValue
        )
    }

    /// Returns `AskUserQuestion` updated input containing user answers.
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
            approvalIdentityToolInput: approvalIdentityToolInput,
            planMarkdownFallback: fallback
        )
    }

    func sessionApprovalMatch(
        for scope: ToolApprovalSessionScope
    ) -> (kind: AgentSessionApprovalRuleKind, value: String)? {
        guard let agentScope = Self.agentCLIKitScope(scope),
              let grant = agentCLIKitSessionApprovalRequest.sessionApprovalGrant(for: agentScope),
              let matchKind = Self.agentSessionApprovalRuleKind(grant.matchKind) else {
            return nil
        }
        return (matchKind, grant.matchValue)
    }

    private func approvalPromptTitle(isPlural: Bool) -> String {
        if let title = nativeReadOnlyApprovalPromptTitle(isPlural: isPlural) {
            return title
        }

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

    private func nativeReadOnlyApprovalPromptTitle(isPlural: Bool) -> String? {
        switch toolName {
        case "Read":
            return "Approve reading \(isPlural ? "files" : "a file")?"
        case "LS":
            return "Approve listing \(isPlural ? "directories" : "a directory")?"
        case "NotebookRead":
            return "Approve reading \(isPlural ? "notebooks" : "a notebook")?"
        case "Grep", "Glob":
            return "Approve searching \(isPlural ? "paths" : "a path")?"
        default:
            return nil
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

    private var askUserQuestionNotificationSummary: String {
        Self.truncated(firstAskUserQuestionText ?? "Review the pending question")
    }

    private var firstAskUserQuestionText: String? {
        guard let data = toolInput.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questions = object["questions"] as? [[String: Any]] else {
            return nil
        }

        return (questions.first?["question"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private var normalizedBashCommand: String? {
        agentCLIKitSessionApprovalRequest.sessionApprovalGrant(for: .exact)?.matchValue
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

    private static func searchSummary(pattern: String?, path: String?) -> String? {
        guard let pattern = pattern?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        guard let path = displayApprovalPath(path) else {
            return pattern
        }
        return "\(pattern) in \(path)"
    }

    private static func truncated(_ value: String, limit: Int = 140) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit - 1)) + "..."
    }

    private var agentCLIKitSessionApprovalRequest: AgentCLIKit.AgentSessionApprovalRequest {
        // Scope, recommendation, and match-value lookups do not depend on the
        // conversation, so a placeholder ID is safe here; real grants thread
        // actual IDs through the parameterized variant below.
        agentCLIKitSessionApprovalRequest(conversationId: "", providerId: .claude)
    }

    private func agentCLIKitSessionApprovalRequest(
        conversationId: String,
        providerId: AgentCLIKit.AgentProviderID
    ) -> AgentCLIKit.AgentSessionApprovalRequest {
        AgentCLIKit.AgentSessionApprovalRequest(
            providerId: providerId,
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
            sessionId: AgentCLIKit.AgentSessionID(rawValue: sessionId),
            toolName: toolName,
            toolInput: agentCLIKitToolInput,
            approvalIdentityToolInput: agentCLIKitApprovalIdentityToolInput
        )
    }

    private var agentCLIKitToolInput: AgentCLIKit.JSONValue {
        guard let data = toolInput.data(using: .utf8),
              let value = try? JSONDecoder().decode(AgentCLIKit.JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }

    private var agentCLIKitApprovalIdentityToolInput: AgentCLIKit.JSONValue? {
        guard let approvalIdentityToolInput,
              let data = approvalIdentityToolInput.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AgentCLIKit.JSONValue.self, from: data)
    }

    private static func agentCLIKitScope(_ scope: ToolApprovalSessionScope) -> AgentCLIKit.AgentToolApprovalSessionScope? {
        switch scope {
        case .exact:
            return .exact
        case .group:
            return .group
        }
    }

    private static func toolApprovalSessionScope(
        _ scope: AgentCLIKit.AgentToolApprovalSessionScope
    ) -> ToolApprovalSessionScope? {
        switch scope {
        case .exact:
            return .exact
        case .group:
            return .group
        }
    }

    private static func agentSessionApprovalRuleKind(
        _ kind: AgentCLIKit.AgentSessionApprovalMatchKind
    ) -> AgentSessionApprovalRuleKind? {
        AgentSessionApprovalRuleKind(rawValue: kind.rawValue)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
