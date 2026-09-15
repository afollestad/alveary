import AgentCLIKit
import Foundation

struct HarnessSessionActionSnapshot: Equatable, Sendable {
    let conversations: [HarnessSessionConversationSnapshot]
    let workingDirectory: URL?

    var conversationIDs: [String] {
        conversations.map(\.conversationID)
    }

    var harnessIDs: [String] {
        conversations.compactMap(\.actionHarnessID)
    }

    init(
        conversations: [HarnessSessionConversationSnapshot],
        workingDirectory: URL?
    ) {
        self.conversations = conversations
        self.workingDirectory = workingDirectory.map { URL(fileURLWithPath: CanonicalPath.normalize($0.path), isDirectory: true) }
    }

    init(
        conversationIDs: [String],
        harnessIDs: [String],
        workingDirectory: URL?
    ) {
        let conversations: [HarnessSessionConversationSnapshot]
        if conversationIDs.count == harnessIDs.count {
            conversations = zip(conversationIDs, harnessIDs).map {
                HarnessSessionConversationSnapshot(conversationID: $0.0, harnessID: $0.1)
            }
        } else if harnessIDs.count == 1, let harnessID = harnessIDs.first {
            conversations = conversationIDs.map {
                HarnessSessionConversationSnapshot(conversationID: $0, harnessID: harnessID)
            }
        } else {
            conversations = conversationIDs.map {
                HarnessSessionConversationSnapshot(conversationID: $0, harnessID: nil)
            }
        }
        self.init(conversations: conversations, workingDirectory: workingDirectory)
    }
}

struct HarnessSessionConversationSnapshot: Equatable, Sendable {
    let conversationID: String
    let harnessID: String?
    let harnessSessionID: String?
    let harnessSessionHarnessID: String?
    let harnessSessionWorkingDirectory: String?
    /// Whether this conversation's thread ever completed initial setup. `false` means no harness
    /// session can exist, so an unresolved binding is nothing to report. Defaults to `true` so a
    /// caller that only ever snapshots started threads keeps reporting them.
    let hasStartedHarnessSession: Bool

    init(
        conversationID: String,
        harnessID: String?,
        harnessSessionID: String? = nil,
        harnessSessionHarnessID: String? = nil,
        harnessSessionWorkingDirectory: String? = nil,
        hasStartedHarnessSession: Bool = true
    ) {
        self.conversationID = conversationID
        self.harnessID = harnessID
        self.harnessSessionID = harnessSessionID
        self.harnessSessionHarnessID = harnessSessionHarnessID
        self.harnessSessionWorkingDirectory = harnessSessionWorkingDirectory.map(CanonicalPath.normalize)
        self.hasStartedHarnessSession = hasStartedHarnessSession
    }

    var actionHarnessID: String? {
        harnessID ?? harnessSessionHarnessID
    }
}

struct HarnessSessionActionResolution: Equatable, Sendable {
    let snapshot: HarnessSessionActionSnapshot
    let records: [AgentCLIKit.AgentSessionRecord]
    let missingBindings: [HarnessSessionActionMissingBinding]
}

struct HarnessSessionActionMissingBinding: Equatable, Sendable {
    let conversationID: AgentCLIKit.AgentConversationID
    let harnessID: AgentCLIKit.AgentHarnessID
}

struct HarnessSessionActionDiagnostic: Equatable, Sendable {
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
    let harnessID: AgentCLIKit.AgentHarnessID
    let harnessDisplayName: String
    let harnessSessionID: AgentCLIKit.AgentSessionID?
    let conversationID: AgentCLIKit.AgentConversationID?
    let message: String

    var toastMessage: String {
        if let harnessSessionID {
            return "Could not \(action.toastVerb) \(harnessDisplayName) harness session \(harnessSessionID.rawValue): \(message)"
        }
        if let conversationID {
            return "Could not \(action.toastVerb) \(harnessDisplayName) harness session for conversation \(conversationID.rawValue): \(message)"
        }
        return "Could not \(action.toastVerb) \(harnessDisplayName) harness session: \(message)"
    }
}

protocol HarnessSessionActionService: Sendable {
    func resolveSessions(matching snapshot: HarnessSessionActionSnapshot) async -> HarnessSessionActionResolution
    func archiveSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic]
    func unarchiveSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic]
    func deleteSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic]
}

struct NoopHarnessSessionActionService: HarnessSessionActionService {
    func resolveSessions(matching snapshot: HarnessSessionActionSnapshot) async -> HarnessSessionActionResolution {
        HarnessSessionActionResolution(snapshot: snapshot, records: [], missingBindings: [])
    }

    func archiveSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic] {
        []
    }

    func unarchiveSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic] {
        []
    }

    func deleteSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic] {
        []
    }
}

actor AgentCLIKitHarnessSessionActionService: HarnessSessionActionService {
    private let sessionStore: any AgentCLIKit.AgentSessionStore
    private let router: AgentCLIKit.AgentHarnessSessionActionRouter
    private let harnessLookup: any AgentCLIKit.AgentHarnessLookup

    init(
        sessionStore: any AgentCLIKit.AgentSessionStore,
        router: AgentCLIKit.AgentHarnessSessionActionRouter,
        harnessLookup: any AgentCLIKit.AgentHarnessLookup
    ) {
        self.sessionStore = sessionStore
        self.router = router
        self.harnessLookup = harnessLookup
    }

    func resolveSessions(matching snapshot: HarnessSessionActionSnapshot) async -> HarnessSessionActionResolution {
        do {
            let result = try await sessionRecords(matching: snapshot)
            return HarnessSessionActionResolution(
                snapshot: snapshot,
                records: result.records,
                missingBindings: result.missingBindings
            )
        } catch {
            return HarnessSessionActionResolution(snapshot: snapshot, records: [], missingBindings: [])
        }
    }

    func archiveSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic] {
        await routeSessions(resolution, sessionAction: .archive) { [router] record in
            try await router.archiveSession(record)
        }
    }

    func unarchiveSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic] {
        await routeSessions(resolution, sessionAction: .unarchive) { [router] record in
            try await router.unarchiveSession(record)
        }
    }

    func deleteSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic] {
        var diagnostics: [HarnessSessionActionDiagnostic] = []
        for record in resolution.records {
            guard let definition = await harnessLookup.definition(for: record.harnessId) else {
                diagnostics.append(.missingHarnessDefinition(action: .delete, record: record))
                continue
            }
            guard definition.capabilities.supports(.delete) else {
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
            guard let definition = await harnessLookup.definition(for: missingBinding.harnessID) else {
                diagnostics.append(.missingHarnessDefinition(action: .delete, missingBinding: missingBinding))
                continue
            }
            guard definition.capabilities.supports(.delete) || definition.capabilities.supports(.archive) else {
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
        sessionAction: HarnessSessionActionDiagnostic.Action,
        perform: @Sendable (AgentCLIKit.AgentSessionRecord) async throws -> Void
    ) async -> [HarnessSessionActionDiagnostic] {
        var diagnostics: [HarnessSessionActionDiagnostic] = []
        for record in records {
            guard let definition = await harnessLookup.definition(for: record.harnessId) else {
                diagnostics.append(.missingHarnessDefinition(action: sessionAction, record: record))
                continue
            }
            guard definition.capabilities.supports(sessionAction) else {
                continue
            }
            do {
                try await perform(record)
            } catch {
                diagnostics.append(.harnessFailure(
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
        _ resolution: HarnessSessionActionResolution,
        sessionAction: HarnessSessionActionDiagnostic.Action,
        perform: @Sendable (AgentCLIKit.AgentSessionRecord) async throws -> Void
    ) async -> [HarnessSessionActionDiagnostic] {
        var diagnostics = await routeSessions(
            resolution.records,
            sessionAction: sessionAction,
            perform: perform
        )
        for missingBinding in resolution.missingBindings {
            guard let definition = await harnessLookup.definition(for: missingBinding.harnessID) else {
                diagnostics.append(.missingHarnessDefinition(action: sessionAction, missingBinding: missingBinding))
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
        definition: AgentCLIKit.AgentHarnessDefinition
    ) async -> [HarnessSessionActionDiagnostic] {
        guard definition.capabilities.supports(.archive) else {
            return [
                .harnessFailure(
                    action: .delete,
                    record: record,
                    definition: definition,
                    error: HarnessSessionDeleteFallbackError.archiveUnsupported
                )
            ]
        }
        do {
            try await router.archiveSession(record)
            return []
        } catch {
            return [
                .harnessFailure(
                    action: .archive,
                    record: record,
                    definition: definition,
                    error: error
                )
            ]
        }
    }

    private func sessionRecords(
        matching snapshot: HarnessSessionActionSnapshot
    ) async throws -> (records: [AgentCLIKit.AgentSessionRecord], missingBindings: [HarnessSessionActionMissingBinding]) {
        var records: [AgentCLIKit.AgentSessionRecord] = []
        var missingBindings: [HarnessSessionActionMissingBinding] = []
        var seenRecords = Set<HarnessSessionActionRecordKey>()

        for conversation in snapshot.conversations {
            guard let rawHarnessID = conversation.actionHarnessID,
                  let harnessID = AgentCLIKit.AgentHarnessID(rawValue: rawHarnessID) else {
                continue
            }

            let conversationID = AgentCLIKit.AgentConversationID(rawValue: conversation.conversationID)
            if let record = try await sessionStore.record(conversationId: conversationID, harnessId: harnessID) {
                append(record, to: &records, seenRecords: &seenRecords)
                continue
            }

            if let record = fallbackRecord(from: conversation, harnessID: harnessID, snapshot: snapshot) {
                append(record, to: &records, seenRecords: &seenRecords)
                continue
            }

            // A thread whose initial setup never completed has no harness session to strand, so
            // its unresolved binding is a false alarm rather than something to warn about.
            guard conversation.hasStartedHarnessSession else {
                continue
            }

            missingBindings.append(HarnessSessionActionMissingBinding(
                conversationID: conversationID,
                harnessID: harnessID
            ))
        }

        return (records.sorted {
            if $0.conversationId.rawValue == $1.conversationId.rawValue {
                return $0.harnessSessionId.rawValue < $1.harnessSessionId.rawValue
            }
            return $0.conversationId.rawValue < $1.conversationId.rawValue
        }, missingBindings.sorted {
            if $0.conversationID.rawValue == $1.conversationID.rawValue {
                return $0.harnessID.rawValue < $1.harnessID.rawValue
            }
            return $0.conversationID.rawValue < $1.conversationID.rawValue
        })
    }

    private func append(
        _ record: AgentCLIKit.AgentSessionRecord,
        to records: inout [AgentCLIKit.AgentSessionRecord],
        seenRecords: inout Set<HarnessSessionActionRecordKey>
    ) {
        guard seenRecords.insert(HarnessSessionActionRecordKey(record)).inserted else {
            return
        }
        records.append(record)
    }

    private func fallbackRecord(
        from conversation: HarnessSessionConversationSnapshot,
        harnessID: AgentCLIKit.AgentHarnessID,
        snapshot: HarnessSessionActionSnapshot
    ) -> AgentCLIKit.AgentSessionRecord? {
        guard conversation.harnessSessionHarnessID == harnessID.rawValue,
              let harnessSessionID = conversation.harnessSessionID else {
            return nil
        }
        return AgentCLIKit.AgentSessionRecord(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversation.conversationID),
            harnessId: harnessID,
            harnessSessionId: AgentCLIKit.AgentSessionID(rawValue: harnessSessionID),
            workingDirectory: fallbackWorkingDirectory(from: conversation, snapshot: snapshot),
            generation: 0
        )
    }

    private func fallbackWorkingDirectory(
        from conversation: HarnessSessionConversationSnapshot,
        snapshot: HarnessSessionActionSnapshot
    ) -> URL? {
        if let harnessSessionWorkingDirectory = conversation.harnessSessionWorkingDirectory {
            return URL(fileURLWithPath: harnessSessionWorkingDirectory, isDirectory: true)
        }
        return snapshot.workingDirectory
    }

}

private struct HarnessSessionActionRecordKey: Hashable {
    let conversationID: AgentCLIKit.AgentConversationID
    let harnessID: AgentCLIKit.AgentHarnessID

    init(_ record: AgentCLIKit.AgentSessionRecord) {
        conversationID = record.conversationId
        harnessID = record.harnessId
    }
}

private extension AgentCLIKit.AgentHarnessCapabilities {
    func supports(_ action: HarnessSessionActionDiagnostic.Action) -> Bool {
        switch action {
        case .archive:
            supportsSessionArchiving
        case .unarchive:
            supportsSessionUnarchiving
        case .delete:
            supportsSessionDeletion
        }
    }
}

private enum HarnessSessionDeleteFallbackError: LocalizedError {
    case archiveUnsupported

    var errorDescription: String? {
        switch self {
        case .archiveUnsupported:
            return "Harness deletion failed and archive fallback is unsupported."
        }
    }
}

private extension HarnessSessionActionDiagnostic {
    static func missingHarnessDefinition(
        action: Action,
        record: AgentCLIKit.AgentSessionRecord
    ) -> HarnessSessionActionDiagnostic {
        HarnessSessionActionDiagnostic(
            action: action,
            harnessID: record.harnessId,
            harnessDisplayName: record.harnessId.rawValue,
            harnessSessionID: record.harnessSessionId,
            conversationID: record.conversationId,
            message: "Harness is not registered."
        )
    }

    static func missingHarnessDefinition(
        action: Action,
        missingBinding: HarnessSessionActionMissingBinding
    ) -> HarnessSessionActionDiagnostic {
        HarnessSessionActionDiagnostic(
            action: action,
            harnessID: missingBinding.harnessID,
            harnessDisplayName: missingBinding.harnessID.rawValue,
            harnessSessionID: nil,
            conversationID: missingBinding.conversationID,
            message: "Harness is not registered."
        )
    }

    static func harnessFailure(
        action: Action,
        record: AgentCLIKit.AgentSessionRecord,
        definition: AgentCLIKit.AgentHarnessDefinition,
        error: Error
    ) -> HarnessSessionActionDiagnostic {
        HarnessSessionActionDiagnostic(
            action: action,
            harnessID: record.harnessId,
            harnessDisplayName: definition.displayName,
            harnessSessionID: record.harnessSessionId,
            conversationID: record.conversationId,
            message: error.localizedDescription
        )
    }

    static func missingSessionBinding(
        action: Action,
        missingBinding: HarnessSessionActionMissingBinding,
        definition: AgentCLIKit.AgentHarnessDefinition
    ) -> HarnessSessionActionDiagnostic {
        HarnessSessionActionDiagnostic(
            action: action,
            harnessID: missingBinding.harnessID,
            harnessDisplayName: definition.displayName,
            harnessSessionID: nil,
            conversationID: missingBinding.conversationID,
            message: "No harness session binding is available."
        )
    }
}
