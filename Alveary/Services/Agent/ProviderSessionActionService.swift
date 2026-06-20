import AgentCLIKit
import Foundation

struct ProviderSessionActionSnapshot: Equatable, Sendable {
    let conversations: [ProviderSessionConversationSnapshot]
    let workingDirectory: URL?

    var conversationIDs: [String] {
        conversations.map(\.conversationID)
    }

    var providerIDs: [String] {
        conversations.compactMap(\.actionProviderID)
    }

    init(
        conversations: [ProviderSessionConversationSnapshot],
        workingDirectory: URL?
    ) {
        self.conversations = conversations
        self.workingDirectory = workingDirectory.map { URL(fileURLWithPath: CanonicalPath.normalize($0.path), isDirectory: true) }
    }

    init(
        conversationIDs: [String],
        providerIDs: [String],
        workingDirectory: URL?
    ) {
        let conversations: [ProviderSessionConversationSnapshot]
        if conversationIDs.count == providerIDs.count {
            conversations = zip(conversationIDs, providerIDs).map {
                ProviderSessionConversationSnapshot(conversationID: $0.0, providerID: $0.1)
            }
        } else if providerIDs.count == 1, let providerID = providerIDs.first {
            conversations = conversationIDs.map {
                ProviderSessionConversationSnapshot(conversationID: $0, providerID: providerID)
            }
        } else {
            conversations = conversationIDs.map {
                ProviderSessionConversationSnapshot(conversationID: $0, providerID: nil)
            }
        }
        self.init(conversations: conversations, workingDirectory: workingDirectory)
    }
}

struct ProviderSessionConversationSnapshot: Equatable, Sendable {
    let conversationID: String
    let providerID: String?
    let providerSessionID: String?
    let providerSessionProviderID: String?
    let providerSessionWorkingDirectory: String?

    init(
        conversationID: String,
        providerID: String?,
        providerSessionID: String? = nil,
        providerSessionProviderID: String? = nil,
        providerSessionWorkingDirectory: String? = nil
    ) {
        self.conversationID = conversationID
        self.providerID = providerID
        self.providerSessionID = providerSessionID
        self.providerSessionProviderID = providerSessionProviderID
        self.providerSessionWorkingDirectory = providerSessionWorkingDirectory.map(CanonicalPath.normalize)
    }

    var actionProviderID: String? {
        providerID ?? providerSessionProviderID
    }
}

struct ProviderSessionActionResolution: Equatable, Sendable {
    let snapshot: ProviderSessionActionSnapshot
    let records: [AgentCLIKit.AgentSessionRecord]
    let missingBindings: [ProviderSessionActionMissingBinding]
}

struct ProviderSessionActionMissingBinding: Equatable, Sendable {
    let conversationID: AgentCLIKit.AgentConversationID
    let providerID: AgentCLIKit.AgentProviderID
}

struct ProviderSessionActionDiagnostic: Equatable, Sendable {
    enum Action: String, Equatable, Sendable {
        case archive
        case unarchive
        case delete

        var toastVerb: String {
            switch self {
            case .archive:
                "archive"
            case .unarchive:
                "restore"
            case .delete:
                "delete"
            }
        }
    }

    let action: Action
    let providerID: AgentCLIKit.AgentProviderID
    let providerDisplayName: String
    let providerSessionID: AgentCLIKit.AgentSessionID?
    let conversationID: AgentCLIKit.AgentConversationID?
    let message: String

    var toastMessage: String {
        if let providerSessionID {
            return "Could not \(action.toastVerb) \(providerDisplayName) provider session \(providerSessionID.rawValue): \(message)"
        }
        if let conversationID {
            return "Could not \(action.toastVerb) \(providerDisplayName) provider session for conversation \(conversationID.rawValue): \(message)"
        }
        return "Could not \(action.toastVerb) \(providerDisplayName) provider session: \(message)"
    }
}

protocol ProviderSessionActionService: Sendable {
    func resolveSessions(matching snapshot: ProviderSessionActionSnapshot) async -> ProviderSessionActionResolution
    func archiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic]
    func unarchiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic]
    func deleteSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic]
}

struct NoopProviderSessionActionService: ProviderSessionActionService {
    func resolveSessions(matching snapshot: ProviderSessionActionSnapshot) async -> ProviderSessionActionResolution {
        ProviderSessionActionResolution(snapshot: snapshot, records: [], missingBindings: [])
    }

    func archiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        []
    }

    func unarchiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        []
    }

    func deleteSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        []
    }
}

actor AgentCLIKitProviderSessionActionService: ProviderSessionActionService {
    private let sessionStore: any AgentCLIKit.AgentSessionStore
    private let router: AgentCLIKit.AgentProviderSessionActionRouter
    private let providerLookup: any AgentCLIKit.AgentProviderLookup

    init(
        sessionStore: any AgentCLIKit.AgentSessionStore,
        router: AgentCLIKit.AgentProviderSessionActionRouter,
        providerLookup: any AgentCLIKit.AgentProviderLookup
    ) {
        self.sessionStore = sessionStore
        self.router = router
        self.providerLookup = providerLookup
    }

    func resolveSessions(matching snapshot: ProviderSessionActionSnapshot) async -> ProviderSessionActionResolution {
        do {
            let result = try await sessionRecords(matching: snapshot)
            return ProviderSessionActionResolution(
                snapshot: snapshot,
                records: result.records,
                missingBindings: result.missingBindings
            )
        } catch {
            return ProviderSessionActionResolution(snapshot: snapshot, records: [], missingBindings: [])
        }
    }

    func archiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        await routeSessions(resolution, sessionAction: .archive) { [router] record in
            try await router.archiveSession(record)
        }
    }

    func unarchiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        await routeSessions(resolution, sessionAction: .unarchive) { [router] record in
            try await router.unarchiveSession(record)
        }
    }

    func deleteSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        var diagnostics: [ProviderSessionActionDiagnostic] = []
        for record in resolution.records {
            guard let definition = await providerLookup.definition(for: record.providerId) else {
                diagnostics.append(.missingProviderDefinition(action: .delete, record: record))
                continue
            }
            do {
                try await router.deleteSession(record)
            } catch {
                let fallbackDiagnostics = await archiveFallbackDiagnostics(
                    record: record,
                    definition: definition
                )
                if fallbackDiagnostics.isEmpty {
                    continue
                }
                diagnostics.append(contentsOf: fallbackDiagnostics)
            }
        }

        for missingBinding in resolution.missingBindings {
            guard let definition = await providerLookup.definition(for: missingBinding.providerID) else {
                diagnostics.append(.missingProviderDefinition(action: .delete, missingBinding: missingBinding))
                continue
            }
            diagnostics.append(.missingSessionBinding(
                action: .delete,
                missingBinding: missingBinding,
                definition: definition
            ))
        }
        return diagnostics
    }

    private func routeSessions(
        _ records: [AgentCLIKit.AgentSessionRecord],
        sessionAction: ProviderSessionActionDiagnostic.Action,
        perform: @Sendable (AgentCLIKit.AgentSessionRecord) async throws -> Void
    ) async -> [ProviderSessionActionDiagnostic] {
        var diagnostics: [ProviderSessionActionDiagnostic] = []
        for record in records {
            guard let definition = await providerLookup.definition(for: record.providerId) else {
                diagnostics.append(.missingProviderDefinition(action: sessionAction, record: record))
                continue
            }
            guard definition.capabilities.supports(sessionAction) else {
                continue
            }
            do {
                try await perform(record)
            } catch {
                diagnostics.append(.providerFailure(
                    action: sessionAction,
                    record: record,
                    definition: definition,
                    error: error
                ))
            }
        }
        return diagnostics
    }

    private func routeSessions(
        _ resolution: ProviderSessionActionResolution,
        sessionAction: ProviderSessionActionDiagnostic.Action,
        perform: @Sendable (AgentCLIKit.AgentSessionRecord) async throws -> Void
    ) async -> [ProviderSessionActionDiagnostic] {
        var diagnostics = await routeSessions(
            resolution.records,
            sessionAction: sessionAction,
            perform: perform
        )
        for missingBinding in resolution.missingBindings {
            guard let definition = await providerLookup.definition(for: missingBinding.providerID) else {
                diagnostics.append(.missingProviderDefinition(action: sessionAction, missingBinding: missingBinding))
                continue
            }
            guard definition.capabilities.supports(sessionAction) else {
                continue
            }
            diagnostics.append(.missingSessionBinding(
                action: sessionAction,
                missingBinding: missingBinding,
                definition: definition
            ))
        }
        return diagnostics
    }

    private func archiveFallbackDiagnostics(
        record: AgentCLIKit.AgentSessionRecord,
        definition: AgentCLIKit.AgentProviderDefinition
    ) async -> [ProviderSessionActionDiagnostic] {
        guard definition.capabilities.supports(.archive) else {
            return [
                .providerFailure(
                    action: .delete,
                    record: record,
                    definition: definition,
                    error: ProviderSessionDeleteFallbackError.archiveUnsupported
                )
            ]
        }
        do {
            try await router.archiveSession(record)
            return []
        } catch {
            return [
                .providerFailure(
                    action: .archive,
                    record: record,
                    definition: definition,
                    error: error
                )
            ]
        }
    }

    private func sessionRecords(
        matching snapshot: ProviderSessionActionSnapshot
    ) async throws -> (records: [AgentCLIKit.AgentSessionRecord], missingBindings: [ProviderSessionActionMissingBinding]) {
        var records: [AgentCLIKit.AgentSessionRecord] = []
        var missingBindings: [ProviderSessionActionMissingBinding] = []
        var seenRecords = Set<ProviderSessionActionRecordKey>()

        for conversation in snapshot.conversations {
            guard let rawProviderID = conversation.actionProviderID,
                  let providerID = AgentCLIKit.AgentProviderID(rawValue: rawProviderID) else {
                continue
            }

            let conversationID = AgentCLIKit.AgentConversationID(rawValue: conversation.conversationID)
            if let record = try await sessionStore.record(conversationId: conversationID, providerId: providerID) {
                append(record, to: &records, seenRecords: &seenRecords)
                continue
            }

            if let record = fallbackRecord(from: conversation, providerID: providerID, snapshot: snapshot) {
                append(record, to: &records, seenRecords: &seenRecords)
                continue
            }

            missingBindings.append(ProviderSessionActionMissingBinding(
                conversationID: conversationID,
                providerID: providerID
            ))
        }

        return (records.sorted {
            if $0.conversationId.rawValue == $1.conversationId.rawValue {
                return $0.providerSessionId.rawValue < $1.providerSessionId.rawValue
            }
            return $0.conversationId.rawValue < $1.conversationId.rawValue
        }, missingBindings.sorted {
            if $0.conversationID.rawValue == $1.conversationID.rawValue {
                return $0.providerID.rawValue < $1.providerID.rawValue
            }
            return $0.conversationID.rawValue < $1.conversationID.rawValue
        })
    }

    private func append(
        _ record: AgentCLIKit.AgentSessionRecord,
        to records: inout [AgentCLIKit.AgentSessionRecord],
        seenRecords: inout Set<ProviderSessionActionRecordKey>
    ) {
        guard seenRecords.insert(ProviderSessionActionRecordKey(record)).inserted else {
            return
        }
        records.append(record)
    }

    private func fallbackRecord(
        from conversation: ProviderSessionConversationSnapshot,
        providerID: AgentCLIKit.AgentProviderID,
        snapshot: ProviderSessionActionSnapshot
    ) -> AgentCLIKit.AgentSessionRecord? {
        guard conversation.providerSessionProviderID == providerID.rawValue,
              let providerSessionID = conversation.providerSessionID else {
            return nil
        }
        return AgentCLIKit.AgentSessionRecord(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversation.conversationID),
            providerId: providerID,
            providerSessionId: AgentCLIKit.AgentSessionID(rawValue: providerSessionID),
            workingDirectory: fallbackWorkingDirectory(from: conversation, snapshot: snapshot),
            generation: 0
        )
    }

    private func fallbackWorkingDirectory(
        from conversation: ProviderSessionConversationSnapshot,
        snapshot: ProviderSessionActionSnapshot
    ) -> URL? {
        if let providerSessionWorkingDirectory = conversation.providerSessionWorkingDirectory {
            return URL(fileURLWithPath: providerSessionWorkingDirectory, isDirectory: true)
        }
        return snapshot.workingDirectory
    }

}

private struct ProviderSessionActionRecordKey: Hashable {
    let conversationID: AgentCLIKit.AgentConversationID
    let providerID: AgentCLIKit.AgentProviderID

    init(_ record: AgentCLIKit.AgentSessionRecord) {
        conversationID = record.conversationId
        providerID = record.providerId
    }
}

private extension AgentCLIKit.AgentProviderCapabilities {
    func supports(_ action: ProviderSessionActionDiagnostic.Action) -> Bool {
        switch action {
        case .archive:
            supportsSessionArchiving
        case .unarchive:
            supportsSessionUnarchiving
        case .delete:
            true
        }
    }
}

private enum ProviderSessionDeleteFallbackError: LocalizedError {
    case archiveUnsupported

    var errorDescription: String? {
        switch self {
        case .archiveUnsupported:
            return "Provider deletion failed and archive fallback is unsupported."
        }
    }
}

private extension ProviderSessionActionDiagnostic {
    static func missingProviderDefinition(
        action: Action,
        record: AgentCLIKit.AgentSessionRecord
    ) -> ProviderSessionActionDiagnostic {
        ProviderSessionActionDiagnostic(
            action: action,
            providerID: record.providerId,
            providerDisplayName: record.providerId.rawValue,
            providerSessionID: record.providerSessionId,
            conversationID: record.conversationId,
            message: "Provider is not registered."
        )
    }

    static func missingProviderDefinition(
        action: Action,
        missingBinding: ProviderSessionActionMissingBinding
    ) -> ProviderSessionActionDiagnostic {
        ProviderSessionActionDiagnostic(
            action: action,
            providerID: missingBinding.providerID,
            providerDisplayName: missingBinding.providerID.rawValue,
            providerSessionID: nil,
            conversationID: missingBinding.conversationID,
            message: "Provider is not registered."
        )
    }

    static func providerFailure(
        action: Action,
        record: AgentCLIKit.AgentSessionRecord,
        definition: AgentCLIKit.AgentProviderDefinition,
        error: Error
    ) -> ProviderSessionActionDiagnostic {
        ProviderSessionActionDiagnostic(
            action: action,
            providerID: record.providerId,
            providerDisplayName: definition.displayName,
            providerSessionID: record.providerSessionId,
            conversationID: record.conversationId,
            message: error.localizedDescription
        )
    }

    static func missingSessionBinding(
        action: Action,
        missingBinding: ProviderSessionActionMissingBinding,
        definition: AgentCLIKit.AgentProviderDefinition
    ) -> ProviderSessionActionDiagnostic {
        ProviderSessionActionDiagnostic(
            action: action,
            providerID: missingBinding.providerID,
            providerDisplayName: definition.displayName,
            providerSessionID: nil,
            conversationID: missingBinding.conversationID,
            message: "No provider session binding is available."
        )
    }
}
