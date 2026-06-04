import AgentCLIKit
import Foundation

struct ProviderSessionActionSnapshot: Equatable, Sendable {
    let conversationIDs: [String]
    let providerIDs: [String]
    let workingDirectory: URL?
}

struct ProviderSessionActionResolution: Equatable, Sendable {
    let snapshot: ProviderSessionActionSnapshot
    let records: [AgentCLIKit.AgentSessionRecord]
}

struct ProviderSessionActionDiagnostic: Equatable, Sendable {
    enum Action: String, Equatable, Sendable {
        case archive
        case unarchive

        var toastVerb: String {
            switch self {
            case .archive:
                "archive"
            case .unarchive:
                "restore"
            }
        }
    }

    let action: Action
    let providerID: AgentCLIKit.AgentProviderID
    let providerDisplayName: String
    let providerSessionID: AgentCLIKit.AgentSessionID
    let message: String

    var toastMessage: String {
        "Could not \(action.toastVerb) \(providerDisplayName) provider session \(providerSessionID.rawValue): \(message)"
    }
}

protocol ProviderSessionActionService: Sendable {
    func resolveSessions(matching snapshot: ProviderSessionActionSnapshot) async -> ProviderSessionActionResolution
    func archiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic]
    func unarchiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic]
}

struct NoopProviderSessionActionService: ProviderSessionActionService {
    func resolveSessions(matching snapshot: ProviderSessionActionSnapshot) async -> ProviderSessionActionResolution {
        ProviderSessionActionResolution(snapshot: snapshot, records: [])
    }

    func archiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        []
    }

    func unarchiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
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
            return ProviderSessionActionResolution(
                snapshot: snapshot,
                records: try await sessionRecords(matching: snapshot)
            )
        } catch {
            return ProviderSessionActionResolution(snapshot: snapshot, records: [])
        }
    }

    func archiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        await routeSessions(resolution.records, sessionAction: .archive) { [router] record in
            try await router.archiveSession(record)
        }
    }

    func unarchiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        await routeSessions(resolution.records, sessionAction: .unarchive) { [router] record in
            try await router.unarchiveSession(record)
        }
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

    private func sessionRecords(matching snapshot: ProviderSessionActionSnapshot) async throws -> [AgentCLIKit.AgentSessionRecord] {
        let conversationIDs = Set(snapshot.conversationIDs)
        var records: [AgentCLIKit.AgentSessionRecord] = []
        for providerID in providerIDs(from: snapshot.providerIDs) {
            let providerRecords = try await sessionStore.records(
                providerId: providerID,
                workingDirectory: snapshot.workingDirectory
            )
            records.append(contentsOf: providerRecords.filter { conversationIDs.contains($0.conversationId.rawValue) })
        }
        return records.sorted {
            if $0.conversationId.rawValue == $1.conversationId.rawValue {
                return $0.providerSessionId.rawValue < $1.providerSessionId.rawValue
            }
            return $0.conversationId.rawValue < $1.conversationId.rawValue
        }
    }

    private func providerIDs(from rawValues: [String]) -> [AgentCLIKit.AgentProviderID] {
        var seen = Set<AgentCLIKit.AgentProviderID>()
        return rawValues.compactMap(AgentCLIKit.AgentProviderID.init(rawValue:)).filter {
            seen.insert($0).inserted
        }
    }
}

private extension AgentCLIKit.AgentProviderCapabilities {
    func supports(_ action: ProviderSessionActionDiagnostic.Action) -> Bool {
        switch action {
        case .archive:
            supportsSessionArchiving
        case .unarchive:
            supportsSessionUnarchiving
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
            message: error.localizedDescription
        )
    }
}
