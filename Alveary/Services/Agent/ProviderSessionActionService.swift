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

protocol ProviderSessionActionService: Sendable {
    func resolveSessions(matching snapshot: ProviderSessionActionSnapshot) async -> ProviderSessionActionResolution
    func archiveSessions(_ resolution: ProviderSessionActionResolution) async
    func unarchiveSessions(_ resolution: ProviderSessionActionResolution) async
}

struct NoopProviderSessionActionService: ProviderSessionActionService {
    func resolveSessions(matching snapshot: ProviderSessionActionSnapshot) async -> ProviderSessionActionResolution {
        ProviderSessionActionResolution(snapshot: snapshot, records: [])
    }

    func archiveSessions(_ resolution: ProviderSessionActionResolution) async {}
    func unarchiveSessions(_ resolution: ProviderSessionActionResolution) async {}
}

actor AgentCLIKitProviderSessionActionService: ProviderSessionActionService {
    private let sessionStore: any AgentCLIKit.AgentSessionStore
    private let router: AgentCLIKit.AgentProviderSessionActionRouter

    init(
        sessionStore: any AgentCLIKit.AgentSessionStore,
        router: AgentCLIKit.AgentProviderSessionActionRouter
    ) {
        self.sessionStore = sessionStore
        self.router = router
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

    func archiveSessions(_ resolution: ProviderSessionActionResolution) async {
        await routeSessions(resolution.records) { [router] record in
            try await router.archiveSession(record)
        }
    }

    func unarchiveSessions(_ resolution: ProviderSessionActionResolution) async {
        await routeSessions(resolution.records) { [router] record in
            try await router.unarchiveSession(record)
        }
    }

    private func routeSessions(
        _ records: [AgentCLIKit.AgentSessionRecord],
        action: @Sendable (AgentCLIKit.AgentSessionRecord) async throws -> Void
    ) async {
        for record in records {
            do {
                try await action(record)
            } catch {
                continue
            }
        }
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
