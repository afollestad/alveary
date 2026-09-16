import Foundation

struct ScheduledTaskProposalSchedule: Codable, Equatable, Sendable {
    let recurrence: ScheduledTaskRecurrence?
    let timeZoneIdentifier: String
    let afterSeconds: Int?

    init(recurrence: ScheduledTaskRecurrence, timeZoneIdentifier: String) {
        self.recurrence = recurrence
        self.timeZoneIdentifier = timeZoneIdentifier
        afterSeconds = nil
    }

    init(afterSeconds: Int, timeZoneIdentifier: String) {
        recurrence = nil
        self.timeZoneIdentifier = timeZoneIdentifier
        self.afterSeconds = afterSeconds
    }

    var isOneOff: Bool { afterSeconds != nil || recurrence?.kind == .once }

    /// Resolve only at host acceptance; parsing and retry hashing must never read the clock.
    func resolved(at date: Date) throws -> ScheduledTaskRecurrence {
        if let recurrence { return recurrence }
        guard let afterSeconds, afterSeconds > 0 else {
            throw HostToolRequestError.invalidArguments("The scheduled delay must be a positive number of seconds.")
        }
        let occurrence = date.addingTimeInterval(Double(afterSeconds))
        guard occurrence > date, occurrence.timeIntervalSince1970.isFinite,
              occurrence.timeIntervalSince1970 < 253_402_300_800 else {
            throw HostToolRequestError.invalidArguments("The scheduled delay is outside the supported date range.")
        }
        return .once(occurrence)
    }
}

struct ScheduledTaskProposalEditChanges: Equatable, Sendable {
    let title: String?
    let prompt: String?
    let schedule: ScheduledTaskProposalSchedule?
    let placement: ScheduledTaskProposalPlacement?

    init(
        title: String? = nil,
        prompt: String? = nil,
        schedule: ScheduledTaskProposalSchedule? = nil,
        placement: ScheduledTaskProposalPlacement? = nil
    ) {
        self.title = title
        self.prompt = prompt
        self.schedule = schedule
        self.placement = placement
    }
}

enum ScheduledTaskProposalRequest: Equatable, Sendable {
    case create(
        title: String,
        prompt: String,
        schedule: ScheduledTaskProposalSchedule,
        placement: ScheduledTaskProposalPlacement?
    )
    case edit(definitionID: String, expectedRevision: Int, changes: ScheduledTaskProposalEditChanges)
    case pause(definitionID: String, expectedRevision: Int)
    case resume(definitionID: String, expectedRevision: Int)
    case delete(definitionID: String, expectedRevision: Int)
    case runNow(definitionID: String, expectedRevision: Int)

    var isImmediateCreate: Bool {
        if case .create(_, _, let schedule, _) = self { return schedule.isOneOff }
        return false
    }

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

    /// Existing definition the request targets; `nil` for create.
    var targetDefinitionID: String? {
        switch self {
        case .create:
            nil
        case let .edit(definitionID, _, _),
             let .pause(definitionID, _),
             let .resume(definitionID, _),
             let .delete(definitionID, _),
             let .runNow(definitionID, _):
            definitionID
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
    /// Target task name, echoed into the tool result so the transcript widget can name
    /// the task durably after the proposal row is consumed. Optional for older receipts.
    var title: String?
    /// `"applied"` when the action ran without confirmation; `nil` means the legacy
    /// pending-confirmation receipt.
    var outcomeStatus: String?
    let message: String
    let sourceProcessToken: String
    let createdAt: Date
    var workspaceSnapshot: WorkspaceSnapshot?
    var projectID: String?
    var definitionID: String?
    /// Preserve the exact returned timestamp; the ledger's legacy Date codec drops fractional seconds.
    var scheduledAt: String?
    var destination: String?
}
