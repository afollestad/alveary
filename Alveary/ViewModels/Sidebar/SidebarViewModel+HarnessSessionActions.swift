import AgentCLIKit
import Foundation

extension SidebarViewModel {
    /// Resolves the harness sessions a deletion should clean up.
    ///
    /// Missing bindings are kept rather than dropped: a conversation whose harness session cannot be resolved leaves
    /// a live harness-side session behind, and reporting that beats deleting the thread in silence. A thread that
    /// never completed initial setup is the exception, dropped in `resolveSessions` — it has no session to strand.
    func deleteHarnessSessionResolution(
        for snapshot: HarnessSessionActionSnapshot
    ) async -> HarnessSessionActionResolution {
        let resolution = await harnessSessionActionService.resolveSessions(matching: snapshot)
        return HarnessSessionActionResolution(
            snapshot: resolution.snapshot,
            records: uniqueHarnessSessionRecords(resolution.records),
            missingBindings: resolution.missingBindings
        )
    }

    func deleteHarnessSessionResolution(
        for snapshots: [ThreadCleanupSnapshot]
    ) async -> HarnessSessionActionResolution {
        let combinedSnapshot = combinedHarnessSessionActionSnapshot(for: snapshots)
        let resolution = await harnessSessionActionService.resolveSessions(matching: combinedSnapshot)
        return HarnessSessionActionResolution(
            snapshot: resolution.snapshot,
            records: uniqueHarnessSessionRecords(resolution.records),
            missingBindings: resolution.missingBindings
        )
    }

    private func combinedHarnessSessionActionSnapshot(for snapshots: [ThreadCleanupSnapshot]) -> HarnessSessionActionSnapshot {
        HarnessSessionActionSnapshot(
            conversations: snapshots.flatMap(\.harnessSessionAction.conversations),
            workingDirectory: snapshots.compactMap(\.harnessSessionAction.workingDirectory).first
        )
    }

    private func uniqueHarnessSessionRecords(
        _ records: [AgentCLIKit.AgentSessionRecord]
    ) -> [AgentCLIKit.AgentSessionRecord] {
        var seen = Set<HarnessSessionCleanupRecordKey>()
        return records.filter { record in
            seen.insert(HarnessSessionCleanupRecordKey(record)).inserted
        }
    }
}

private struct HarnessSessionCleanupRecordKey: Hashable {
    let harnessID: AgentCLIKit.AgentHarnessID
    let harnessSessionID: AgentCLIKit.AgentSessionID

    init(_ record: AgentCLIKit.AgentSessionRecord) {
        harnessID = record.harnessId
        harnessSessionID = record.harnessSessionId
    }
}
