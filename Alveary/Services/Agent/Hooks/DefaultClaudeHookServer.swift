import Foundation
import SwiftData

actor DefaultClaudeHookServer: ClaudeHookServer {
    private static let tokenEnvironmentKey = "ALVEARY_HOOK_TOKEN"
    private static let settingsFileName = "claude-hooks-settings.json"
    private static let sessionApprovalStoreName = "session-approvals.store"
    private static let maxStartAttempts = 3

    private let supportDirectory: URL
    private let sessionApprovalContainer: ModelContainer?
    private var listener: ClaudeHookHTTPListener?
    private var listenerID: UUID?
    private var listenerPort: UInt16?
    private var validTokens: Set<String> = []
    private var launchContextByToken: [String: HookLaunchContext] = [:]
    private var decisions: [ClaudeToolApprovalKey: ClaudeToolApprovalDecision] = [:]

    init(supportDirectory: URL? = nil) {
        let supportDirectory = supportDirectory ?? Self.defaultSupportDirectory()
        self.supportDirectory = supportDirectory
        self.sessionApprovalContainer = try? Self.makeSessionApprovalContainer(supportDirectory: supportDirectory)
    }

    func prepareLaunch(
        permissionMode: String?,
        conversationId: String
    ) async -> ClaudeHookLaunchConfig? {
        guard ClaudeHookPolicy.shouldEnableHooks(permissionMode: permissionMode) else {
            return nil
        }

        do {
            let port = try await ensureListenerStarted()
            let settingsURL = try writeSettings(port: port)
            let token = UUID().uuidString
            validTokens.insert(token)
            launchContextByToken[token] = HookLaunchContext(
                conversationId: conversationId,
                permissionMode: permissionMode
            )
            return ClaudeHookLaunchConfig(
                arguments: ["--settings", settingsURL.path],
                environment: [Self.tokenEnvironmentKey: token]
            )
        } catch {
            return nil
        }
    }

    func recordDecision(_ decision: ClaudeToolApprovalDecision, for key: ClaudeToolApprovalKey) {
        decisions[key] = decision
    }

    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) -> SessionApprovalRecordResult {
        guard let context = sessionApprovalContext() else {
            return SessionApprovalRecordResult(isEffective: false, wasInserted: false)
        }

        let providerId = approval.providerId
        let conversationId = approval.conversationId
        let sessionId = approval.sessionId
        let matchKind = approval.matchKind.rawValue
        let matchValue = approval.matchValue
        let existingRules = (try? context.fetch(
            FetchDescriptor<AgentSessionApprovalRule>(
                predicate: #Predicate {
                    $0.providerId == providerId &&
                        $0.conversationId == conversationId &&
                        $0.sessionId == sessionId &&
                        $0.matchKind == matchKind &&
                        $0.matchValue == matchValue
                }
            )
        )) ?? []
        guard existingRules.isEmpty else {
            return SessionApprovalRecordResult(isEffective: true, wasInserted: false)
        }

        let rule = AgentSessionApprovalRule(
            providerId: approval.providerId,
            conversationId: approval.conversationId,
            sessionId: approval.sessionId,
            matchKind: approval.matchKind.rawValue,
            matchValue: approval.matchValue
        )
        context.insert(rule)
        do {
            try context.save()
            return SessionApprovalRecordResult(isEffective: true, wasInserted: true)
        } catch {
            context.delete(rule)
            return SessionApprovalRecordResult(isEffective: false, wasInserted: false)
        }
    }

    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) {
        guard let context = sessionApprovalContext() else {
            return
        }

        let providerId = approval.providerId
        let conversationId = approval.conversationId
        let sessionId = approval.sessionId
        let matchKind = approval.matchKind.rawValue
        let matchValue = approval.matchValue
        let matchingRules = (try? context.fetch(
            FetchDescriptor<AgentSessionApprovalRule>(
                predicate: #Predicate {
                    $0.providerId == providerId &&
                        $0.conversationId == conversationId &&
                        $0.sessionId == sessionId &&
                        $0.matchKind == matchKind &&
                        $0.matchValue == matchValue
                }
            )
        )) ?? []
        guard !matchingRules.isEmpty else {
            return
        }

        for rule in matchingRules {
            context.delete(rule)
        }
        try? context.save()
    }

    func removeSessionApprovals(conversationId: String, sessionId: String) {
        guard let context = sessionApprovalContext() else {
            return
        }

        let providerId = "claude"
        let existingRules = (try? context.fetch(
            FetchDescriptor<AgentSessionApprovalRule>(
                predicate: #Predicate {
                    $0.providerId == providerId &&
                        $0.conversationId == conversationId &&
                        $0.sessionId == sessionId
                }
            )
        )) ?? []
        guard !existingRules.isEmpty else {
            return
        }

        for rule in existingRules {
            context.delete(rule)
        }
        try? context.save()
    }

    func discardDecision(for key: ClaudeToolApprovalKey) {
        decisions.removeValue(forKey: key)
    }

    func invalidateToken(_ token: String) {
        validTokens.remove(token)
        launchContextByToken.removeValue(forKey: token)
    }

    private func ensureListenerStarted() async throws -> UInt16 {
        if let listenerPort {
            return listenerPort
        }

        var lastError: Error?
        for _ in 0..<Self.maxStartAttempts {
            do {
                let listenerID = UUID()
                let listener = ClaudeHookHTTPListener(
                    onUnavailable: { [weak self] in
                        Task {
                            await self?.markListenerUnavailable(id: listenerID)
                        }
                    },
                    handler: { [weak self] request in
                        guard let self else {
                            return .empty(statusCode: 503)
                        }
                        return await self.handle(request)
                    }
                )
                self.listenerID = listenerID
                self.listener = listener
                let port = try await listener.start()
                self.listenerPort = port
                return port
            } catch {
                lastError = error
                listener?.cancel()
                if self.listenerID == listenerID {
                    listener = nil
                    listenerPort = nil
                    self.listenerID = nil
                }
            }
        }

        throw lastError ?? ClaudeHookListenerError.cancelled
    }

    private func markListenerUnavailable(id: UUID) {
        guard listenerID == id else {
            return
        }

        listener = nil
        listenerID = nil
        listenerPort = nil
        validTokens.removeAll()
        launchContextByToken.removeAll()
        decisions.removeAll()
    }

    func handle(_ request: ClaudeHookHTTPRequest) -> ClaudeHookHTTPResponse {
        guard let token = authorizationToken(from: request.authorization),
              validTokens.contains(token),
              let launchContext = launchContextByToken[token] else {
            return decisionResponse(
                .deny,
                reason: "Invalid Alveary hook token"
            )
        }

        guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            return decisionResponse(
                .deny,
                reason: "Invalid Alveary hook request"
            )
        }

        guard let hookEventName = payload["hook_event_name"] as? String else {
            return decisionResponse(
                .deny,
                reason: "Incomplete Alveary hook request"
            )
        }

        guard hookEventName == "PreToolUse" else {
            return .empty()
        }

        guard let sessionId = payload["session_id"] as? String,
              let toolUseId = payload["tool_use_id"] as? String,
              let toolName = payload["tool_name"] as? String else {
            return decisionResponse(
                .deny,
                reason: "Incomplete Alveary hook request"
            )
        }

        let key = ClaudeToolApprovalKey(sessionId: sessionId, toolUseId: toolUseId)
        if let decision = decisions.removeValue(forKey: key) {
            return decisionResponse(decision, reason: reason(for: decision))
        }

        if let toolInput = serializedToolInput(payload["tool_input"]),
           shouldAllowForStoredSessionApproval(
               conversationId: launchContext.conversationId,
               sessionId: sessionId,
               toolName: toolName,
               toolInput: toolInput
           ) {
            return decisionResponse(.allow, reason: "Approved for session in Alveary")
        }

        let permissionMode = payload["permission_mode"] as? String ?? launchContext.permissionMode
        guard ClaudeHookPolicy.shouldDefer(toolName: toolName, permissionMode: permissionMode) else {
            return .empty()
        }

        return decisionResponse(.defer)
    }

    private func authorizationToken(from authorization: String?) -> String? {
        guard let authorization,
              authorization.hasPrefix("Bearer ") else {
            return nil
        }
        return String(authorization.dropFirst("Bearer ".count))
    }

    private func sessionApprovalContext() -> ModelContext? {
        guard let sessionApprovalContainer else {
            return nil
        }
        return ModelContext(sessionApprovalContainer)
    }

    private func writeSettings(port: UInt16) throws -> URL {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let settingsURL = supportDirectory.appendingPathComponent(Self.settingsFileName)
        let settings: [String: Any] = [
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash|Write|Edit|MultiEdit|NotebookEdit|mcp__.*",
                    "hooks": [[
                        "type": "http",
                        "url": "http://127.0.0.1:\(port)/claude/hooks/pre-tool-use",
                        "timeout": 30,
                        "headers": [
                            "Authorization": "Bearer $\(Self.tokenEnvironmentKey)"
                        ],
                        "allowedEnvVars": [Self.tokenEnvironmentKey]
                    ]]
                ]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
        return settingsURL
    }

    private func decisionResponse(
        _ decision: ClaudeHookResponseDecision,
        reason: String? = nil
    ) -> ClaudeHookHTTPResponse {
        var output: [String: Any] = [
            "hookEventName": "PreToolUse",
            "permissionDecision": decision.rawValue
        ]
        if let reason {
            output["permissionDecisionReason"] = reason
        }
        return .json(["hookSpecificOutput": output])
    }

    private func decisionResponse(
        _ decision: ClaudeToolApprovalDecision,
        reason: String
    ) -> ClaudeHookHTTPResponse {
        switch decision {
        case .allow:
            return decisionResponse(ClaudeHookResponseDecision.allow, reason: reason)
        case .deny:
            return decisionResponse(ClaudeHookResponseDecision.deny, reason: reason)
        }
    }

    private func reason(for decision: ClaudeToolApprovalDecision) -> String {
        switch decision {
        case .allow:
            return "Approved in Alveary"
        case .deny:
            return "Denied in Alveary"
        }
    }

    private func serializedToolInput(_ rawToolInput: Any?) -> String? {
        if let rawToolInput {
            if let data = try? JSONSerialization.data(withJSONObject: rawToolInput, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            if let string = rawToolInput as? String {
                return string
            }
        }
        return "{}"
    }

    private func shouldAllowForStoredSessionApproval(
        conversationId: String,
        sessionId: String,
        toolName: String,
        toolInput: String
    ) -> Bool {
        guard let context = sessionApprovalContext() else {
            return false
        }

        let request = ToolApprovalRequest(
            sessionId: sessionId,
            toolUseId: "",
            toolName: toolName,
            toolInput: toolInput
        )

        let providerId = "claude"
        let requestConversationId = conversationId
        let requestSessionId = sessionId
        for scope in request.supportedSessionApprovalScopes {
            guard let match = request.sessionApprovalMatch(for: scope) else {
                continue
            }

            let matchKind = match.kind.rawValue
            let matchValue = match.value
            let matchingRules = (try? context.fetch(
                FetchDescriptor<AgentSessionApprovalRule>(
                    predicate: #Predicate {
                        $0.providerId == providerId &&
                            $0.conversationId == requestConversationId &&
                            $0.sessionId == requestSessionId &&
                            $0.matchKind == matchKind &&
                            $0.matchValue == matchValue
                    }
                )
            )) ?? []
            if !matchingRules.isEmpty {
                return true
            }
        }

        return false
    }

    private static func defaultSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Alveary", isDirectory: true)
            .appendingPathComponent("ClaudeHooks", isDirectory: true)
    }

    private static func makeSessionApprovalContainer(supportDirectory: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return try ModelContainer(
            for: AgentSessionApprovalRule.self,
            configurations: ModelConfiguration(
                url: supportDirectory.appendingPathComponent(Self.sessionApprovalStoreName)
            )
        )
    }
}

private struct HookLaunchContext {
    let conversationId: String
    let permissionMode: String?
}

private enum ClaudeHookResponseDecision: String {
    case allow
    case deny
    case `defer`
}
