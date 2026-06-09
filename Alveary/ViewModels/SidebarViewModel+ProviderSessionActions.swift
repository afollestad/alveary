import AgentCLIKit
import Foundation

extension SidebarViewModel {
    func deleteProviderSessionResolution(
        for snapshot: ProviderSessionActionSnapshot
    ) async -> ProviderSessionActionResolution {
        let resolution = await providerSessionActionService.resolveSessions(matching: snapshot)
        return ProviderSessionActionResolution(
            snapshot: resolution.snapshot,
            records: uniqueProviderSessionRecords(resolution.records),
            missingBindings: []
        )
    }

    func deleteProviderSessionResolution(
        for snapshots: [ThreadCleanupSnapshot]
    ) async -> ProviderSessionActionResolution {
        let combinedSnapshot = combinedProviderSessionActionSnapshot(for: snapshots)
        let resolution = await providerSessionActionService.resolveSessions(matching: combinedSnapshot)
        return ProviderSessionActionResolution(
            snapshot: resolution.snapshot,
            records: uniqueProviderSessionRecords(resolution.records),
            missingBindings: []
        )
    }

    private func combinedProviderSessionActionSnapshot(for snapshots: [ThreadCleanupSnapshot]) -> ProviderSessionActionSnapshot {
        ProviderSessionActionSnapshot(
            conversations: snapshots.flatMap(\.providerSessionAction.conversations),
            workingDirectory: snapshots.compactMap(\.providerSessionAction.workingDirectory).first
        )
    }

    private func uniqueProviderSessionRecords(
        _ records: [AgentCLIKit.AgentSessionRecord]
    ) -> [AgentCLIKit.AgentSessionRecord] {
        var seen = Set<ProviderSessionCleanupRecordKey>()
        return records.filter { record in
            seen.insert(ProviderSessionCleanupRecordKey(record)).inserted
        }
    }
}

private struct ProviderSessionCleanupRecordKey: Hashable {
    let providerID: AgentCLIKit.AgentProviderID
    let providerSessionID: AgentCLIKit.AgentSessionID

    init(_ record: AgentCLIKit.AgentSessionRecord) {
        providerID = record.providerId
        providerSessionID = record.providerSessionId
    }
}
