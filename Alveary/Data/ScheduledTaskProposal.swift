import Foundation
import SwiftData

enum ScheduledTaskProposalAction: String, Codable, CaseIterable, Sendable {
    case create
    case edit
    case pause
    case resume
    case delete
    case runNow = "run_now"
}

struct ScheduledTaskProposalSchedule: Codable, Equatable, Sendable {
    let recurrence: ScheduledTaskRecurrence
    let timeZoneIdentifier: String
}

struct ScheduledTaskProposalEditChanges: Equatable, Sendable {
    let title: String?
    let prompt: String?
    let schedule: ScheduledTaskProposalSchedule?
}

enum ScheduledTaskProposalRequest: Equatable, Sendable {
    case create(title: String, prompt: String, schedule: ScheduledTaskProposalSchedule)
    case edit(definitionID: String, expectedRevision: Int, changes: ScheduledTaskProposalEditChanges)
    case pause(definitionID: String, expectedRevision: Int)
    case resume(definitionID: String, expectedRevision: Int)
    case delete(definitionID: String, expectedRevision: Int)
    case runNow(definitionID: String, expectedRevision: Int)

    var action: ScheduledTaskProposalAction {
        switch self {
        case .create:
            .create
        case .edit:
            .edit
        case .pause:
            .pause
        case .resume:
            .resume
        case .delete:
            .delete
        case .runNow:
            .runNow
        }
    }
}

struct ScheduledTaskParsedProposalRequest: Equatable, Sendable {
    let request: ScheduledTaskProposalRequest
    let canonicalPayloadJSON: String
    let canonicalPayloadHash: String
}

struct ScheduledTaskProposalReceipt: Codable, Equatable, Sendable {
    let deduplicationKey: String
    let proposalID: String
    let action: ScheduledTaskProposalAction?
    let message: String
    let sourceProcessToken: String
    let createdAt: Date
}

struct ScheduledTaskProposalDefinitionDraft: Codable, Equatable, Sendable {
    let title: String
    let prompt: String
    let destination: ScheduledTaskDestination
    let targetConversationID: String?
    let recurrence: ScheduledTaskRecurrence
    let timeZoneIdentifier: String
    let providerID: String
    let model: String?
    let effort: String
    let permissionMode: String
    let workspaceKind: ScheduledTaskWorkspaceKind
    let workspaceStrategy: ScheduledTaskWorkspaceStrategy
    let grantedRoots: [String]
    let projectPath: String?

    init(
        title: String,
        prompt: String,
        destination: ScheduledTaskDestination = .newThread,
        targetConversationID: String? = nil,
        recurrence: ScheduledTaskRecurrence,
        timeZoneIdentifier: String,
        providerID: String,
        model: String?,
        effort: String,
        permissionMode: String,
        workspaceKind: ScheduledTaskWorkspaceKind,
        workspaceStrategy: ScheduledTaskWorkspaceStrategy,
        grantedRoots: [String],
        projectPath: String?
    ) {
        self.title = title
        self.prompt = prompt
        self.destination = destination
        self.targetConversationID = targetConversationID
        self.recurrence = recurrence
        self.timeZoneIdentifier = timeZoneIdentifier
        self.providerID = providerID
        self.model = model
        self.effort = effort
        self.permissionMode = permissionMode
        self.workspaceKind = workspaceKind
        self.workspaceStrategy = workspaceStrategy
        self.grantedRoots = grantedRoots
        self.projectPath = projectPath
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case prompt
        case destination
        case targetConversationID
        case recurrence
        case timeZoneIdentifier
        case providerID
        case model
        case effort
        case permissionMode
        case workspaceKind
        case workspaceStrategy
        case grantedRoots
        case projectPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        prompt = try container.decode(String.self, forKey: .prompt)
        destination = try container.decodeIfPresent(ScheduledTaskDestination.self, forKey: .destination) ?? .newThread
        targetConversationID = try container.decodeIfPresent(String.self, forKey: .targetConversationID)
        recurrence = try container.decode(ScheduledTaskRecurrence.self, forKey: .recurrence)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        providerID = try container.decode(String.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        effort = try container.decode(String.self, forKey: .effort)
        permissionMode = try container.decode(String.self, forKey: .permissionMode)
        workspaceKind = try container.decode(ScheduledTaskWorkspaceKind.self, forKey: .workspaceKind)
        workspaceStrategy = try container.decode(ScheduledTaskWorkspaceStrategy.self, forKey: .workspaceStrategy)
        grantedRoots = try container.decode([String].self, forKey: .grantedRoots)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
    }
}

@Model
final class ScheduledTaskProposal {
    static let currentPayloadVersion = 1

    @Attribute(.unique) var id: String
    @Attribute(.unique) var sourceConversationID: String
    @Attribute(.unique) var deduplicationKey: String
    var payloadVersion: Int = ScheduledTaskProposal.currentPayloadVersion
    var actionRawValue: String
    var canonicalPayloadJSON: String
    var canonicalPayloadHash: String
    var sourceProviderID: String
    var sourceProcessToken: String
    var sourceRequestID: String
    var targetDefinitionID: String?
    var expectedDefinitionRevision: Int?
    var targetTitleSnapshot: String?
    var targetScheduleSummarySnapshot: String?
    var definitionDraftJSON: String?
    var projectPathSnapshot: String?
    var enqueueOrdinal: Int64?
    var createdAt: Date
    var sourceConversation: Conversation?
    var project: Project?

    init(
        id: String = UUID().uuidString,
        sourceConversationID: String? = nil,
        deduplicationKey: String,
        action: ScheduledTaskProposalAction,
        canonicalPayloadJSON: String,
        canonicalPayloadHash: String,
        sourceProviderID: String,
        sourceProcessToken: UUID,
        sourceRequestID: String,
        targetDefinitionID: String? = nil,
        expectedDefinitionRevision: Int? = nil,
        targetTitleSnapshot: String? = nil,
        targetScheduleSummarySnapshot: String? = nil,
        definitionDraft: ScheduledTaskProposalDefinitionDraft? = nil,
        enqueueOrdinal: Int64? = nil,
        createdAt: Date = .now,
        sourceConversation: Conversation,
        project: Project? = nil
    ) {
        let resolvedConversationID = sourceConversationID ?? sourceConversation.id
        precondition(
            resolvedConversationID == sourceConversation.id,
            "`sourceConversationID` must match `sourceConversation.id`"
        )
        self.id = id
        self.sourceConversationID = resolvedConversationID
        self.deduplicationKey = deduplicationKey
        self.actionRawValue = action.rawValue
        self.canonicalPayloadJSON = canonicalPayloadJSON
        self.canonicalPayloadHash = canonicalPayloadHash
        self.sourceProviderID = sourceProviderID
        self.sourceProcessToken = sourceProcessToken.uuidString.lowercased()
        self.sourceRequestID = sourceRequestID
        self.targetDefinitionID = targetDefinitionID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.targetTitleSnapshot = targetTitleSnapshot
        self.targetScheduleSummarySnapshot = targetScheduleSummarySnapshot
        self.definitionDraftJSON = definitionDraft.map(Self.encodeDefinitionDraft)
        self.projectPathSnapshot = definitionDraft?.projectPath
        self.enqueueOrdinal = enqueueOrdinal
        self.createdAt = createdAt
        self.sourceConversation = sourceConversation
        self.project = project
    }
}

extension ScheduledTaskProposal {
    var action: ScheduledTaskProposalAction? {
        guard payloadVersion == Self.currentPayloadVersion else {
            return nil
        }
        return ScheduledTaskProposalAction(rawValue: actionRawValue)
    }

    var definitionDraft: ScheduledTaskProposalDefinitionDraft? {
        guard payloadVersion == Self.currentPayloadVersion,
              let definitionDraftJSON,
              let data = definitionDraftJSON.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ScheduledTaskProposalDefinitionDraft.self, from: data)
    }

    var hasValidActionShape: Bool {
        guard let action else {
            return false
        }
        let draft = definitionDraft
        let hasValidDraftWorkspace = draft.map { draft in
            switch draft.destination {
            case .newThread:
                guard draft.targetConversationID == nil else { return false }
                switch draft.workspaceKind {
                case .privateWorkspace:
                    return draft.projectPath == nil
                case .project:
                    return draft.projectPath != nil
                }
            case .existingThread:
                return draft.projectPath == nil && draft.targetConversationID?.isEmpty == false
            }
        } ?? false
        switch action {
        case .create:
            return hasValidDraftWorkspace
                && projectPathSnapshot == draft?.projectPath
                && targetDefinitionID == nil
                && expectedDefinitionRevision == nil
                && targetTitleSnapshot == nil
                && targetScheduleSummarySnapshot == nil
        case .edit:
            return hasValidDraftWorkspace
                && projectPathSnapshot == draft?.projectPath
                && targetDefinitionID != nil
                && expectedDefinitionRevision != nil
                && targetTitleSnapshot != nil
                && targetScheduleSummarySnapshot != nil
        case .pause, .resume, .delete, .runNow:
            return definitionDraftJSON == nil
                && projectPathSnapshot == nil
                && targetDefinitionID != nil
                && expectedDefinitionRevision != nil
                && targetTitleSnapshot != nil
                && targetScheduleSummarySnapshot != nil
        }
    }
}

extension Conversation {
    static let maximumScheduledTaskProposalReceiptCount = 256
    static let scheduledTaskProposalReceiptRetention: TimeInterval = 7 * 24 * 60 * 60

    func scheduledTaskProposalReceipt(
        matching deduplicationKey: String,
        currentProcessToken: UUID,
        at date: Date
    ) throws -> ScheduledTaskProposalReceipt? {
        let storedReceipts = try decodedScheduledTaskProposalReceipts()
        let receipts = Self.maintainedScheduledTaskProposalReceipts(
            storedReceipts,
            currentProcessToken: currentProcessToken,
            at: date
        )
        if receipts != storedReceipts {
            try storeScheduledTaskProposalReceipts(receipts)
        }
        return receipts.first {
            $0.deduplicationKey == deduplicationKey
        }
    }

    func recordScheduledTaskProposalReceipt(
        _ receipt: ScheduledTaskProposalReceipt
    ) throws {
        let storedReceipts = try decodedScheduledTaskProposalReceipts()
        var receipts = Self.maintainedScheduledTaskProposalReceipts(
            storedReceipts,
            currentProcessToken: receipt.sourceProcessToken,
            at: receipt.createdAt
        )
        guard !receipts.contains(where: { $0.deduplicationKey == receipt.deduplicationKey }) else {
            if receipts != storedReceipts {
                try storeScheduledTaskProposalReceipts(receipts)
            }
            return
        }
        receipts.append(receipt)
        if receipts.count > Self.maximumScheduledTaskProposalReceiptCount {
            receipts = Array(receipts.suffix(Self.maximumScheduledTaskProposalReceiptCount))
        }
        try storeScheduledTaskProposalReceipts(receipts)
    }
}

private extension Conversation {
    static func maintainedScheduledTaskProposalReceipts(
        _ receipts: [ScheduledTaskProposalReceipt],
        currentProcessToken: UUID,
        at date: Date
    ) -> [ScheduledTaskProposalReceipt] {
        maintainedScheduledTaskProposalReceipts(
            receipts,
            currentProcessToken: currentProcessToken.uuidString.lowercased(),
            at: date
        )
    }

    static func maintainedScheduledTaskProposalReceipts(
        _ receipts: [ScheduledTaskProposalReceipt],
        currentProcessToken: String,
        at date: Date
    ) -> [ScheduledTaskProposalReceipt] {
        var seen = Set<String>()
        let retained = receipts.reversed().filter { receipt in
            guard receipt.sourceProcessToken == currentProcessToken,
                  date.timeIntervalSince(receipt.createdAt) <= scheduledTaskProposalReceiptRetention else {
                return false
            }
            return seen.insert(receipt.deduplicationKey).inserted
        }.reversed()
        return Array(retained.suffix(maximumScheduledTaskProposalReceiptCount))
    }

    func storeScheduledTaskProposalReceipts(
        _ receipts: [ScheduledTaskProposalReceipt]
    ) throws {
        guard !receipts.isEmpty else {
            scheduledTaskProposalReceiptsJSON = nil
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipts)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw ScheduledTaskProposalReceiptError.encodingFailed
        }
        scheduledTaskProposalReceiptsJSON = encoded
    }
}

private extension ScheduledTaskProposal {
    static func encodeDefinitionDraft(_ draft: ScheduledTaskProposalDefinitionDraft) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(draft),
              let encoded = String(data: data, encoding: .utf8) else {
            preconditionFailure("Scheduled task proposal draft could not be encoded")
        }
        return encoded
    }
}

private extension Conversation {
    func decodedScheduledTaskProposalReceipts() throws -> [ScheduledTaskProposalReceipt] {
        guard let scheduledTaskProposalReceiptsJSON else {
            return []
        }
        guard let data = scheduledTaskProposalReceiptsJSON.data(using: .utf8) else {
            throw ScheduledTaskProposalReceiptError.invalidPayload
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ScheduledTaskProposalReceipt].self, from: data)
    }
}

private enum ScheduledTaskProposalReceiptError: Error {
    case invalidPayload
    case encodingFailed
}
