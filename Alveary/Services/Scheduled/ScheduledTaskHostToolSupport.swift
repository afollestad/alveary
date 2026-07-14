import CryptoKit
import Foundation

struct ScheduledTaskHostToolProposalIdentity {
    let requestID: String
    let deduplicationKey: String
    let createdAt: Date
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
        let value = [
            sourceConversationID,
            processToken.uuidString.lowercased(),
            requestID,
            canonicalPayloadHash
        ].joined(separator: "\u{0}")
        return SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func scheduleSummary(for definition: ScheduledTask) -> String {
        guard let recurrence = definition.recurrence else {
            return "invalid schedule [\(definition.timeZoneIdentifier)]"
        }
        let timeZone = "[\(definition.timeZoneIdentifier)]"
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

    init(
        targetDefinitionID: String? = nil,
        expectedDefinitionRevision: Int? = nil,
        targetTitleSnapshot: String? = nil,
        targetScheduleSummarySnapshot: String? = nil,
        definitionDraft: ScheduledTaskProposalDefinitionDraft? = nil,
        project: Project? = nil
    ) {
        self.targetDefinitionID = targetDefinitionID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.targetTitleSnapshot = targetTitleSnapshot
        self.targetScheduleSummarySnapshot = targetScheduleSummarySnapshot
        self.definitionDraft = definitionDraft
        self.project = project
    }
}

struct ScheduledTaskHostToolSourceWorkspace {
    let kind: ScheduledTaskWorkspaceKind
    let strategy: ScheduledTaskWorkspaceStrategy
    let grantedRoots: [String]
    let project: Project?
}

struct ScheduledTaskHostToolSource {
    let conversation: Conversation
    let thread: AgentThread
}

enum ScheduledTaskHostToolServiceError: LocalizedError {
    case unsupportedTool
    case listDoesNotAcceptArguments
    case missingRequestIdentity
    case sourceConversationUnavailable
    case sourceProviderMismatch
    case automatedRunCannotSchedule
    case workspaceUnavailable
    case workspaceRootsChanged
    case definitionNotFound
    case revisionConflict(expected: Int, actual: Int)
    case pauseRequiresActiveDefinition
    case resumeRequiresPausedDefinition
    case runNowBlockedByActiveRun
    case invalidStoredSchedule
    case persistenceFailure

    var errorDescription: String? {
        switch self {
        case .unsupportedTool:
            "This Alveary host tool is not available."
        case .listDoesNotAcceptArguments:
            "list_scheduled_tasks does not accept arguments."
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
        case .invalidStoredSchedule:
            "The scheduled task has an invalid stored schedule and cannot be edited through a proposal."
        case .persistenceFailure:
            "Alveary could not read or save scheduling state."
        }
    }
}
