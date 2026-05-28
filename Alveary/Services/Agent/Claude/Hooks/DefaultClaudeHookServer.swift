import Foundation
import SwiftData
actor DefaultClaudeHookServer: ClaudeHookServer {
    private static let tokenEnvironmentKey = "ALVEARY_HOOK_TOKEN"
    private static let settingsFileName = "claude-hooks-settings.json"
    private static let sessionApprovalStoreName = "session-approvals.store"
    private static let maxStartAttempts = 3
    private static let hookTimeoutSeconds = 600

    private let supportDirectory: URL
    private let pendingApprovalTimeout: Duration
    private let sessionApprovalContainer: ModelContainer?
    private var listener: ClaudeHookHTTPListener?
    private var listenerID: UUID?
    private var listenerPort: UInt16?
    var validTokens: Set<String> = []
    var launchContextByToken: [String: HookLaunchContext] = [:]
    var livePermissionModeByConversation: [String: String] = [:]
    var decisions: [ClaudeToolApprovalKey: ClaudeToolApprovalDecision] = [:]
    var updatedInputs: [ClaudeToolApprovalKey: String] = [:]
    var pendingApprovalContinuations: [ClaudeToolApprovalKey: CheckedContinuation<ClaudeToolApprovalResolution?, Never>] = [:]
    var pendingApprovalContinuationTokens: [ClaudeToolApprovalKey: String] = [:]
    var transientApprovalDecisions: [AgentSessionApprovalGrant: ClaudeToolApprovalDecision] = [:]
    var deferredToolRequestHandler: (@Sendable (ClaudeDeferredToolRequest) async -> Void)?

    init(supportDirectory: URL? = nil, pendingApprovalTimeout: Duration = .seconds(595)) {
        let supportDirectory = supportDirectory ?? Self.defaultSupportDirectory()
        self.supportDirectory = supportDirectory
        self.pendingApprovalTimeout = pendingApprovalTimeout
        self.sessionApprovalContainer = try? Self.makeSessionApprovalContainer(supportDirectory: supportDirectory)
    }

    func setDeferredToolRequestHandler(
        _ handler: (@Sendable (ClaudeDeferredToolRequest) async -> Void)?
    ) {
        deferredToolRequestHandler = handler
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
            if let permissionMode {
                livePermissionModeByConversation[conversationId] = permissionMode
            } else {
                livePermissionModeByConversation.removeValue(forKey: conversationId)
            }
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

    func updatePermissionMode(_ permissionMode: String?, for conversationId: String) {
        if let permissionMode {
            livePermissionModeByConversation[conversationId] = permissionMode
        } else {
            livePermissionModeByConversation.removeValue(forKey: conversationId)
        }
    }

    func recordDecision(_ resolution: ClaudeToolApprovalResolution, for key: ClaudeToolApprovalKey) {
        if let continuation = pendingApprovalContinuations.removeValue(forKey: key) {
            pendingApprovalContinuationTokens.removeValue(forKey: key)
            continuation.resume(returning: resolution)
            return
        }

        decisions[key] = resolution.decision
        if let updatedInput = resolution.updatedInput {
            updatedInputs[key] = updatedInput
        } else {
            updatedInputs.removeValue(forKey: key)
        }
    }
    func recordTransientApprovalDecision(
        _ resolution: ClaudeToolApprovalResolution,
        for approval: AgentSessionApprovalGrant
    ) {
        transientApprovalDecisions[approval] = resolution.decision
    }
    func discardTransientApprovalDecision(for approval: AgentSessionApprovalGrant) {
        transientApprovalDecisions.removeValue(forKey: approval)
    }
    func discardDecision(for key: ClaudeToolApprovalKey) {
        if let continuation = pendingApprovalContinuations.removeValue(forKey: key) {
            pendingApprovalContinuationTokens.removeValue(forKey: key)
            continuation.resume(returning: nil)
        }
        decisions.removeValue(forKey: key)
        updatedInputs.removeValue(forKey: key)
    }
    func waitForPendingApprovalDecision(
        for key: ClaudeToolApprovalKey,
        launchToken: String
    ) async -> ClaudeToolApprovalResolution? {
        await withCheckedContinuation { continuation in
            if let existingContinuation = pendingApprovalContinuations[key] {
                existingContinuation.resume(returning: nil)
            }
            pendingApprovalContinuations[key] = continuation
            pendingApprovalContinuationTokens[key] = launchToken
            Task { [pendingApprovalTimeout] in
                try? await Task.sleep(for: pendingApprovalTimeout)
                self.expirePendingApprovalDecision(for: key)
            }
        }
    }
    func expirePendingApprovalDecision(for key: ClaudeToolApprovalKey) {
        guard let continuation = pendingApprovalContinuations.removeValue(forKey: key) else {
            return
        }
        pendingApprovalContinuationTokens.removeValue(forKey: key)
        continuation.resume(returning: nil)
    }
    func invalidateToken(_ token: String) {
        validTokens.remove(token)
        launchContextByToken.removeValue(forKey: token)
        let expiredKeys = pendingApprovalContinuationTokens.compactMap { key, launchToken in
            launchToken == token ? key : nil
        }
        for key in expiredKeys {
            expirePendingApprovalDecision(for: key)
        }
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
        livePermissionModeByConversation.removeAll()
        decisions.removeAll()
        updatedInputs.removeAll()
        for continuation in pendingApprovalContinuations.values {
            continuation.resume(returning: nil)
        }
        pendingApprovalContinuations.removeAll()
        pendingApprovalContinuationTokens.removeAll()
        transientApprovalDecisions.removeAll()
    }
    func authorizationToken(from authorization: String?) -> String? {
        guard let authorization,
              authorization.hasPrefix("Bearer ") else {
            return nil
        }
        return String(authorization.dropFirst("Bearer ".count))
    }

    func sessionApprovalContext() -> ModelContext? {
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
                    "matcher": ClaudeHookPolicy.preToolUseMatcher,
                    "hooks": [[
                        "type": "http",
                        "url": "http://127.0.0.1:\(port)/claude/hooks/pre-tool-use",
                        "timeout": Self.hookTimeoutSeconds,
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

    func decisionResponse(
        _ decision: ClaudeHookResponseDecision,
        reason: String? = nil,
        updatedInput: Any? = nil
    ) -> ClaudeHookHTTPResponse {
        var output: [String: Any] = [
            "hookEventName": "PreToolUse",
            "permissionDecision": decision.rawValue
        ]
        if let reason {
            output["permissionDecisionReason"] = reason
        }
        if let updatedInput {
            output["updatedInput"] = updatedInput
        }
        return .json(["hookSpecificOutput": output])
    }

    func decisionResponse(
        _ decision: ClaudeToolApprovalDecision,
        reason: String,
        toolName: String,
        toolInput: String?,
        updatedInput: String? = nil
    ) -> ClaudeHookHTTPResponse {
        switch decision {
        case .allow:
            let responseUpdatedInput = updatedInput.flatMap(deserializedJSONObject)
                ?? (requiresUpdatedInput(toolName: toolName) ? deserializedJSONObject(from: toolInput) : nil)
            return decisionResponse(
                ClaudeHookResponseDecision.allow,
                reason: reason,
                updatedInput: responseUpdatedInput
            )
        case .deny:
            return decisionResponse(ClaudeHookResponseDecision.deny, reason: reason)
        }
    }

    private func requiresUpdatedInput(toolName: String) -> Bool {
        [
            "AskUserQuestion",
            "ExitPlanMode"
        ].contains(toolName)
    }

    func reason(for decision: ClaudeToolApprovalDecision) -> String {
        switch decision {
        case .allow:
            return "The user approved this permission prompt in Alveary"
        case .deny:
            return "The user denied this permission prompt in Alveary"
        }
    }

    func serializedToolInput(_ rawToolInput: Any?) -> String? {
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

    func deserializedJSONObject(from serialized: String?) -> Any? {
        guard let serialized,
              let data = serialized.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    func shouldAllowForStoredSessionApproval(
        conversationId: String,
        sessionId: String,
        toolName: String,
        toolInput: String
    ) -> Bool {
        allowsSessionApproval(
            providerId: "claude",
            conversationId: conversationId,
            sessionId: sessionId,
            toolName: toolName,
            toolInput: toolInput
        )
    }

    func allowsSessionApproval(
        providerId: String,
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

        let requestConversationId = conversationId
        let requestSessionId = sessionId
        let requestProviderId = providerId
        for scope in request.supportedSessionApprovalScopes {
            guard let match = request.sessionApprovalMatch(for: scope) else {
                continue
            }

            let matchKind = match.kind.rawValue
            let matchValue = match.value
            let matchingRules = (try? context.fetch(
                FetchDescriptor<AgentSessionApprovalRule>(
                    predicate: #Predicate {
                        $0.providerId == requestProviderId &&
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
            AgentSessionApprovalSelection.self,
            configurations: ModelConfiguration(
                url: supportDirectory.appendingPathComponent(Self.sessionApprovalStoreName)
            )
        )
    }
}

extension DefaultClaudeHookServer {
    func handle(_ request: ClaudeHookHTTPRequest) async -> ClaudeHookHTTPResponse {
        switch validatedPreToolUsePayload(from: request) {
        case .payload(let payload):
            return await handlePreToolUsePayload(payload)
        case .response(let response):
            return response
        }
    }
}

struct HookLaunchContext {
    let conversationId: String
    let permissionMode: String?
}

enum ClaudeHookResponseDecision: String {
    case allow
    case deny
    case `defer`
}
