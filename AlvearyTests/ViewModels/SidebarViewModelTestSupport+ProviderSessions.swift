import AgentCLIKit
import Foundation

@testable import Alveary

actor RecordingProviderSessionActionService: ProviderSessionActionService {
    enum Action: Sendable, Equatable {
        case resolve(ProviderSessionActionSnapshot)
        case archive(ProviderSessionActionSnapshot)
        case unarchive(ProviderSessionActionSnapshot)
        case delete(ProviderSessionActionSnapshot)
    }

    private(set) var actions: [Action] = []
    private(set) var archivedRecords: [AgentCLIKit.AgentSessionRecord] = []
    private(set) var archivedMissingBindings: [ProviderSessionActionMissingBinding] = []
    private(set) var deletedRecords: [AgentCLIKit.AgentSessionRecord] = []
    private(set) var deletedMissingBindings: [ProviderSessionActionMissingBinding] = []
    private var resolvedRecords: [AgentCLIKit.AgentSessionRecord]
    private var resolvedRecordsByConversationID: [String: [AgentCLIKit.AgentSessionRecord]]
    private var resolvedMissingBindings: [ProviderSessionActionMissingBinding]
    private var archiveDiagnostics: [ProviderSessionActionDiagnostic]
    private var unarchiveDiagnostics: [ProviderSessionActionDiagnostic]
    private var deleteDiagnostics: [ProviderSessionActionDiagnostic]
    private let pausesResolution: Bool
    private var didBeginResolution = false
    private var resolutionWaiters: [CheckedContinuation<Void, Never>] = []
    private var resolutionContinuation: CheckedContinuation<Void, Never>?

    init(
        resolvedRecords: [AgentCLIKit.AgentSessionRecord] = [],
        resolvedRecordsByConversationID: [String: [AgentCLIKit.AgentSessionRecord]] = [:],
        resolvedMissingBindings: [ProviderSessionActionMissingBinding] = [],
        archiveDiagnostics: [ProviderSessionActionDiagnostic] = [],
        unarchiveDiagnostics: [ProviderSessionActionDiagnostic] = [],
        deleteDiagnostics: [ProviderSessionActionDiagnostic] = [],
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

    func resolveSessions(matching snapshot: ProviderSessionActionSnapshot) async -> ProviderSessionActionResolution {
        actions.append(.resolve(snapshot))
        if pausesResolution {
            didBeginResolution = true
            resolutionWaiters.forEach { $0.resume() }
            resolutionWaiters.removeAll()
            await withCheckedContinuation { resolutionContinuation = $0 }
        }
        if !resolvedRecordsByConversationID.isEmpty {
            let records = snapshot.conversationIDs.flatMap { resolvedRecordsByConversationID[$0] ?? [] }
            return ProviderSessionActionResolution(snapshot: snapshot, records: records, missingBindings: [])
        }
        return ProviderSessionActionResolution(snapshot: snapshot, records: resolvedRecords, missingBindings: resolvedMissingBindings)
    }

    func archiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        actions.append(.archive(resolution.snapshot))
        archivedRecords = resolution.records
        archivedMissingBindings = resolution.missingBindings
        return archiveDiagnostics
    }

    func unarchiveSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
        actions.append(.unarchive(resolution.snapshot))
        return unarchiveDiagnostics
    }

    func deleteSessions(_ resolution: ProviderSessionActionResolution) async -> [ProviderSessionActionDiagnostic] {
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

extension ProviderSessionActionDiagnostic {
    static func fixture(
        action: Action,
        providerID: AgentCLIKit.AgentProviderID = .codex,
        providerDisplayName: String = "Codex",
        providerSessionID: AgentCLIKit.AgentSessionID = "session-1",
        message: String = "Sync failed"
    ) -> ProviderSessionActionDiagnostic {
        ProviderSessionActionDiagnostic(
            action: action,
            providerID: providerID,
            providerDisplayName: providerDisplayName,
            providerSessionID: providerSessionID,
            conversationID: "conversation-1",
            message: message
        )
    }
}
