import CryptoKit
import Foundation

struct ScheduledTaskHostToolProposalIdentity {
    let requestID: String
    let deduplicationKey: String
    let createdAt: Date
}

/// Everything an edit's draft builders need, resolved once so the destination branches take one
/// parameter each.
struct ScheduledTaskHostToolEditContext {
    let definition: ScheduledTask
    let changes: ScheduledTaskProposalEditChanges
    /// The destination already stored on the definition, kept when the request names none.
    let storedDestination: ScheduledTaskDestination
    let recurrence: ScheduledTaskRecurrence
    let timeZoneIdentifier: String
    let settings: ScheduledTaskProposalAgentSettings

    var title: String { changes.title ?? definition.title }
    var prompt: String { changes.prompt ?? definition.prompt }
}

/// What an edit resolved to: the proposed definition, the Project that definition would use, and
/// the sentence disclosing any requested placement.
///
/// `project` is the *draft's* Project, which an edit may have pointed at a different one than the
/// definition currently uses. The proposal has to store that one, because the confirmation pane
/// reads a proposal whose trusted Project disagrees with its draft as a vanished Project and
/// refuses to apply it.
struct ScheduledTaskHostToolEditedDraft {
    let draft: ScheduledTaskProposalDefinitionDraft
    let project: Project?
    let placementSummary: String?
}

/// The calling thread a create proposal inherits from, paired with the settings it contributes.
struct ScheduledTaskHostToolCreateSource {
    let thread: AgentThread
    let settings: ScheduledTaskProposalAgentSettings
}

/// Agent settings a proposed definition carries, all bound from trusted host state — the model
/// never supplies any of them. Grouped so draft builders take one parameter instead of four.
struct ScheduledTaskProposalAgentSettings {
    let providerID: String
    let model: String?
    let effort: String
    let permissionMode: String

    init(sourceThread: AgentThread, providerID: String) {
        self.providerID = providerID
        model = sourceThread.model
        effort = sourceThread.effort
        permissionMode = sourceThread.permissionMode
    }

    init(definition: ScheduledTask) {
        providerID = definition.providerID
        model = definition.model
        effort = definition.effort
        permissionMode = definition.permissionMode
    }
}

enum ScheduledTaskHostToolSupport {
    static func validatedStoredGrantedRoots(_ grantedRoots: [String]) throws -> [String] {
        guard ScheduledTask.normalizedUniquePaths(grantedRoots) == grantedRoots else {
            throw ScheduledTaskHostToolServiceError.workspaceRootsChanged
        }
        return grantedRoots
    }

    static func validateStoredCanonicalPath(_ path: String) throws {
        guard CanonicalPath.normalize(path) == path else {
            throw ScheduledTaskHostToolServiceError.workspaceRootsChanged
        }
    }

    static func deduplicationKey(
        sourceConversationID: String,
        processToken: UUID,
        requestID: String,
        canonicalPayloadHash: String
    ) -> String {
        HostToolDeduplication.key(
            sourceConversationID: sourceConversationID,
            processToken: processToken,
            requestID: requestID,
            canonicalPayloadHash: canonicalPayloadHash
        )
    }

    static func scheduleSummary(
        for definition: ScheduledTask,
        timeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier
    ) -> String {
        guard let recurrence = definition.recurrence else {
            return "invalid schedule [\(timeZoneIdentifier)]"
        }
        let timeZone = "[\(timeZoneIdentifier)]"
        switch recurrence {
        case .once(let occurrence):
            return "once at \(canonicalDate(occurrence)) \(timeZone)"
        case let .interval(minutes, anchor):
            let unit = minutes == 1 ? "minute" : "minutes"
            return "every \(minutes) \(unit) from \(canonicalDate(anchor)) \(timeZone)"
        case let .daily(hour, minute):
            return "daily at \(wallClock(hour: hour, minute: minute)) \(timeZone)"
        case let .weekdays(days, hour, minute):
            let schedule = days == ScheduledTaskRecurrence.standardWeekdays
                ? "weekdays"
                : "every \(days.map(weekdayName).joined(separator: ", "))"
            return "\(schedule) at \(wallClock(hour: hour, minute: minute)) \(timeZone)"
        case let .weekly(weekday, hour, minute):
            return "weekly on \(weekdayName(weekday)) at \(wallClock(hour: hour, minute: minute)) \(timeZone)"
        case let .monthly(day, hour, minute):
            return "monthly on day \(day) at \(wallClock(hour: hour, minute: minute)) \(timeZone)"
        }
    }
}

private extension ScheduledTaskHostToolSupport {
    static func canonicalDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func wallClock(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard names.indices.contains(weekday - 1) else {
            return "day \(weekday)"
        }
        return names[weekday - 1]
    }
}

struct ScheduledTaskHostToolProposalResolution {
    let targetDefinitionID: String?
    let expectedDefinitionRevision: Int?
    let targetTitleSnapshot: String?
    let targetScheduleSummarySnapshot: String?
    let definitionDraft: ScheduledTaskProposalDefinitionDraft?
    let project: Project?
    /// Names a destination or workspace the request asked for, so the tool result discloses it
    /// before the user opens the confirmation pane. `nil` when everything was inherited.
    let placementSummary: String?

    init(
        targetDefinitionID: String? = nil,
        expectedDefinitionRevision: Int? = nil,
        targetTitleSnapshot: String? = nil,
        targetScheduleSummarySnapshot: String? = nil,
        definitionDraft: ScheduledTaskProposalDefinitionDraft? = nil,
        project: Project? = nil,
        placementSummary: String? = nil
    ) {
        self.targetDefinitionID = targetDefinitionID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.targetTitleSnapshot = targetTitleSnapshot
        self.targetScheduleSummarySnapshot = targetScheduleSummarySnapshot
        self.definitionDraft = definitionDraft
        self.project = project
        self.placementSummary = placementSummary
    }
}

struct ScheduledTaskHostToolSourceWorkspace {
    let kind: ScheduledTaskWorkspaceKind
    let strategy: ScheduledTaskWorkspaceStrategy
    let grantedRoots: [String]
    let project: Project?
}

typealias ScheduledTaskHostToolSource = HostToolCallSource

enum ScheduledTaskHostToolServiceError: LocalizedError {
    case unsupportedTool
    case listDoesNotAcceptArguments(toolName: String)
    case missingRequestIdentity
    case sourceConversationUnavailable
    case sourceProviderMismatch
    case automatedRunCannotSchedule
    case workspaceUnavailable
    case workspaceRootsChanged
    case projectNotRegistered(path: String)
    case grantRootUnavailable(path: String)
    case targetThreadNotFound
    case targetThreadIneligible
    case definitionNotFound
    case revisionConflict(expected: Int, actual: Int)
    case pauseRequiresActiveDefinition
    case resumeRequiresPausedDefinition
    case runNowBlockedByActiveRun
    case runNowUnavailable
    case invalidStoredSchedule
    case persistenceFailure

    var errorDescription: String? {
        switch self {
        case .unsupportedTool:
            "This Alveary host tool is not available."
        case .listDoesNotAcceptArguments(let toolName):
            "\(toolName) does not accept arguments."
        case .missingRequestIdentity:
            "Alveary could not verify this scheduling request for safe retry handling."
        case .sourceConversationUnavailable:
            "Scheduling proposals require an active, saved Project or Task conversation."
        case .sourceProviderMismatch:
            "The scheduling request provider does not match its source conversation."
        case .automatedRunCannotSchedule:
            "Automated scheduled runs cannot open scheduling proposals."
        case .workspaceUnavailable:
            "The trusted workspace for this scheduling proposal is no longer available."
        case .workspaceRootsChanged:
            "The trusted workspace or folder grants changed and must be reviewed before scheduling."
        case .projectNotRegistered(let path):
            "\(path) is not a Project in Alveary. Call list_projects and use one of its paths."
        case .grantRootUnavailable(let path):
            "\(path) is not an absolute path to an existing folder. granted_roots entries must be absolute paths to " +
                "folders that already exist; each one is shown to the user for confirmation."
        case .targetThreadNotFound:
            "That thread no longer exists. Call list_threads again before proposing an existing-thread schedule."
        case .targetThreadIneligible:
            "That thread cannot receive scheduled runs. It may have been archived, forked, or left mid-cleanup since " +
                "it was listed. Call list_threads and pick another one."
        case .definitionNotFound:
            "The scheduled task no longer exists. List scheduled tasks again before proposing a change."
        case let .revisionConflict(expected, actual):
            "The scheduled task changed from revision \(expected) to \(actual). List scheduled tasks again before proposing a change."
        case .pauseRequiresActiveDefinition:
            "Only an active scheduled task can be paused."
        case .resumeRequiresPausedDefinition:
            "Only a paused scheduled task can be resumed."
        case .runNowBlockedByActiveRun:
            "The scheduled task is already running or waiting for input."
        case .runNowUnavailable:
            "The scheduler could not start a run right now. Try again shortly."
        case .invalidStoredSchedule:
            "The scheduled task has an invalid stored schedule and cannot be edited through a proposal."
        case .persistenceFailure:
            "Alveary could not read or save scheduling state."
        }
    }
}
