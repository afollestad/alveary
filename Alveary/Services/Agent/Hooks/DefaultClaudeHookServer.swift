import Foundation

actor DefaultClaudeHookServer: ClaudeHookServer {
    private static let tokenEnvironmentKey = "ALVEARY_HOOK_TOKEN"
    private static let settingsFileName = "claude-hooks-settings.json"
    private static let maxStartAttempts = 3

    private let supportDirectory: URL
    private var listener: ClaudeHookHTTPListener?
    private var listenerID: UUID?
    private var listenerPort: UInt16?
    private var validTokens: Set<String> = []
    private var permissionModesByToken: [String: String] = [:]
    private var decisions: [ClaudeToolApprovalKey: ClaudeToolApprovalDecision] = [:]

    init(supportDirectory: URL? = nil) {
        self.supportDirectory = supportDirectory ?? Self.defaultSupportDirectory()
    }

    func prepareLaunch(permissionMode: String?) async -> ClaudeHookLaunchConfig? {
        guard ClaudeHookPolicy.shouldEnableHooks(permissionMode: permissionMode) else {
            return nil
        }

        do {
            let port = try await ensureListenerStarted()
            let settingsURL = try writeSettings(port: port)
            let token = UUID().uuidString
            validTokens.insert(token)
            if let permissionMode {
                permissionModesByToken[token] = permissionMode
            }
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

    func discardDecision(for key: ClaudeToolApprovalKey) {
        decisions.removeValue(forKey: key)
    }

    func invalidateToken(_ token: String) {
        validTokens.remove(token)
        permissionModesByToken.removeValue(forKey: token)
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
        permissionModesByToken.removeAll()
        decisions.removeAll()
    }

    func handle(_ request: ClaudeHookHTTPRequest) -> ClaudeHookHTTPResponse {
        guard let token = authorizationToken(from: request.authorization),
              validTokens.contains(token) else {
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

        let permissionMode = payload["permission_mode"] as? String ?? permissionModesByToken[token]
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

    private static func defaultSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Alveary", isDirectory: true)
            .appendingPathComponent("ClaudeHooks", isDirectory: true)
    }
}

private enum ClaudeHookResponseDecision: String {
    case allow
    case deny
    case `defer`
}
