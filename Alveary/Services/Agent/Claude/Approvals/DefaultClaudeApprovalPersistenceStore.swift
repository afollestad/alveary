import Foundation
import SwiftData

/// SwiftData-backed approval persistence for Claude session approvals.
///
/// Runtime hook transport and transient fallback decisions are owned by `AgentCLIKit`.
/// This actor stores only Alveary-owned reusable approval rules and the last selected
/// approval scope for each Claude session. Missing or unavailable storage fails open
/// to "not approved" so historical approval state never fabricates a provider decision.
actor DefaultClaudeApprovalPersistenceStore: ClaudeApprovalPersistenceStore {
    private static let sessionApprovalStoreName = "session-approvals.store"

    private let supportDirectory: URL
    private let sessionApprovalContainer: ModelContainer?

    /// Creates a persistence store rooted at the supplied support directory.
    ///
    /// When `supportDirectory` is omitted, the store continues to use the existing
    /// `Application Support/Alveary/ClaudeHooks` directory so approvals recorded by
    /// older Alveary builds remain available after the hook transport moves to `AgentCLIKit`.
    init(supportDirectory: URL? = nil) {
        let supportDirectory = supportDirectory ?? Self.defaultSupportDirectory()
        self.supportDirectory = supportDirectory
        self.sessionApprovalContainer = try? Self.makeSessionApprovalContainer(supportDirectory: supportDirectory)
    }

    /// Creates a fresh SwiftData context for approval reads and writes.
    func sessionApprovalContext() -> ModelContext? {
        guard let sessionApprovalContainer else {
            return nil
        }
        return ModelContext(sessionApprovalContainer)
    }

    /// Returns whether an existing stored approval covers the supplied Claude request.
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
