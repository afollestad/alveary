import AgentCLIKit
import Foundation

@testable import Alveary

actor RecordingHarnessSessionActionService: HarnessSessionActionService {
    enum Action: Sendable, Equatable {
        case resolve(HarnessSessionActionSnapshot)
        case archive(HarnessSessionActionSnapshot)
        case unarchive(HarnessSessionActionSnapshot)
        case delete(HarnessSessionActionSnapshot)
    }

    private(set) var actions: [Action] = []
    private(set) var archivedRecords: [AgentCLIKit.AgentSessionRecord] = []
    private(set) var archivedMissingBindings: [HarnessSessionActionMissingBinding] = []
    private(set) var deletedRecords: [AgentCLIKit.AgentSessionRecord] = []
    private(set) var deletedMissingBindings: [HarnessSessionActionMissingBinding] = []
    private var resolvedRecords: [AgentCLIKit.AgentSessionRecord]
    private var resolvedRecordsByConversationID: [String: [AgentCLIKit.AgentSessionRecord]]
    private var resolvedMissingBindings: [HarnessSessionActionMissingBinding]
    private var archiveDiagnostics: [HarnessSessionActionDiagnostic]
    private var unarchiveDiagnostics: [HarnessSessionActionDiagnostic]
    private var deleteDiagnostics: [HarnessSessionActionDiagnostic]
    private let pausesResolution: Bool
    private var didBeginResolution = false
    private var resolutionWaiters: [CheckedContinuation<Void, Never>] = []
    private var resolutionContinuation: CheckedContinuation<Void, Never>?

    init(
        resolvedRecords: [AgentCLIKit.AgentSessionRecord] = [],
        resolvedRecordsByConversationID: [String: [AgentCLIKit.AgentSessionRecord]] = [:],
        resolvedMissingBindings: [HarnessSessionActionMissingBinding] = [],
        archiveDiagnostics: [HarnessSessionActionDiagnostic] = [],
        unarchiveDiagnostics: [HarnessSessionActionDiagnostic] = [],
        deleteDiagnostics: [HarnessSessionActionDiagnostic] = [],
        pausesResolution: Bool = false
    ) {
        self.resolvedRecords = resolvedRecords
        self.resolvedRecordsByConversationID = resolvedRecordsByConversationID
        self.resolvedMissingBindings = resolvedMissingBindings
        self.archiveDiagnostics = archiveDiagnostics
        self.unarchiveDiagnostics = unarchiveDiagnostics
        self.deleteDiagnostics = deleteDiagnostics
        self.pausesResolution = pausesResolution
    }

    func resolveSessions(matching snapshot: HarnessSessionActionSnapshot) async -> HarnessSessionActionResolution {
        actions.append(.resolve(snapshot))
        if pausesResolution {
            didBeginResolution = true
            resolutionWaiters.forEach { $0.resume() }
            resolutionWaiters.removeAll()
            await withCheckedContinuation { resolutionContinuation = $0 }
        }
        if !resolvedRecordsByConversationID.isEmpty {
            let records = snapshot.conversationIDs.flatMap { resolvedRecordsByConversationID[$0] ?? [] }
            return HarnessSessionActionResolution(snapshot: snapshot, records: records, missingBindings: [])
        }
        return HarnessSessionActionResolution(snapshot: snapshot, records: resolvedRecords, missingBindings: resolvedMissingBindings)
    }

    func archiveSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic] {
        actions.append(.archive(resolution.snapshot))
        archivedRecords = resolution.records
        archivedMissingBindings = resolution.missingBindings
        return archiveDiagnostics
    }

    func unarchiveSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic] {
        actions.append(.unarchive(resolution.snapshot))
        return unarchiveDiagnostics
    }

    func deleteSessions(_ resolution: HarnessSessionActionResolution) async -> [HarnessSessionActionDiagnostic] {
        actions.append(.delete(resolution.snapshot))
        deletedRecords = resolution.records
        deletedMissingBindings = resolution.missingBindings
        return deleteDiagnostics
    }

    func waitUntilResolutionBegins() async {
        guard !didBeginResolution else {
            return
        }
        await withCheckedContinuation { resolutionWaiters.append($0) }
    }

    func resumeResolution() {
        resolutionContinuation?.resume()
        resolutionContinuation = nil
    }
}

@MainActor
final class RecordingUnexpectedErrors {
    private(set) var messages: [String] = []

    func present(_ message: String) {
        messages.append(message)
    }
}

extension HarnessSessionActionDiagnostic {
    static func fixture(
        action: Action,
        harnessID: AgentCLIKit.AgentHarnessID = .codex,
        harnessDisplayName: String = "Codex",
        harnessSessionID: AgentCLIKit.AgentSessionID = "session-1",
        message: String = "Sync failed"
    ) -> HarnessSessionActionDiagnostic {
        HarnessSessionActionDiagnostic(
            action: action,
            harnessID: harnessID,
            harnessDisplayName: harnessDisplayName,
            harnessSessionID: harnessSessionID,
            conversationID: "conversation-1",
            message: message
        )
    }
}
