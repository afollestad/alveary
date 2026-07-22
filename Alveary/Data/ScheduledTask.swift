import Foundation
import SwiftData

enum ScheduledTaskState: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case completed
}

enum ScheduledTaskDestination: String, Codable, CaseIterable, Sendable {
    case newThread
    case existingThread
}

enum ScheduledTaskWorkspaceKind: String, Codable, CaseIterable, Sendable {
    case privateWorkspace
    case project
}

enum ScheduledTaskWorkspaceStrategy: String, Codable, CaseIterable, Sendable {
    case localCheckout
    case worktree
}

@Model
final class ScheduledTask {
    @Attribute(.unique) var id: String
    var title: String
    var prompt: String
    var destinationRawValue: String = ScheduledTaskDestination.newThread.rawValue
    var revision: Int
    var stateRawValue: String
    var recurrenceKindRawValue: String
    var recurrenceAnchorAt: Date?
    var intervalMinutes: Int?
    var wallClockHour: Int?
    var wallClockMinute: Int?
    var selectedWeekdays: [Int] = ScheduledTaskRecurrence.standardWeekdays
    var weeklyWeekday: Int?
    var monthlyDay: Int?
    var timeZoneIdentifier: String
    var providerID: String
    var model: String?
    var effort: String
    var permissionMode: String
    var workspaceKindRawValue: String
    var workspaceStrategyRawValue: String
    var grantedRoots: [String]
    var nextOccurrenceAt: Date?
    var pendingOccurrenceAt: Date?
    var targetWaitStartedAt: Date?
    var pauseReason: String?
    var lastError: String?
    var createdAt: Date
    var modifiedAt: Date
    var project: Project?
    var targetThread: AgentThread?
    @Relationship(deleteRule: .nullify, inverse: \ScheduledTaskRun.scheduledTask) var runs: [ScheduledTaskRun]

    init(
        id: String = UUID().uuidString,
        title: String,
        prompt: String,
        destination: ScheduledTaskDestination = .newThread,
        revision: Int = 1,
        state: ScheduledTaskState = .active,
        recurrence: ScheduledTaskRecurrence,
        timeZoneIdentifier: String,
        providerID: String,
        model: String? = nil,
        effort: String = AppSettings.defaultEffortLevel,
        permissionMode: String = "default",
        workspaceKind: ScheduledTaskWorkspaceKind = .privateWorkspace,
        workspaceStrategy: ScheduledTaskWorkspaceStrategy = .worktree,
        grantedRoots: [String] = [],
        project: Project? = nil,
        nextOccurrenceAt: Date? = nil,
        pendingOccurrenceAt: Date? = nil,
        targetWaitStartedAt: Date? = nil,
        pauseReason: String? = nil,
        lastError: String? = nil,
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        targetThread: AgentThread? = nil,
        runs: [ScheduledTaskRun] = []
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.destinationRawValue = destination.rawValue
        self.revision = revision
        self.stateRawValue = state.rawValue
        self.recurrenceKindRawValue = recurrence.kind.rawValue
        self.timeZoneIdentifier = timeZoneIdentifier
        self.providerID = providerID
        self.model = model
        self.effort = effort
        self.permissionMode = permissionMode
        self.workspaceKindRawValue = workspaceKind.rawValue
        self.workspaceStrategyRawValue = workspaceStrategy.rawValue
        self.grantedRoots = Self.normalizedUniquePaths(grantedRoots)
        self.project = project
        self.nextOccurrenceAt = nextOccurrenceAt
        self.pendingOccurrenceAt = pendingOccurrenceAt
        self.targetWaitStartedAt = targetWaitStartedAt
        self.pauseReason = pauseReason
        self.lastError = lastError
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.targetThread = targetThread
        self.runs = runs

        recurrenceAnchorAt = nil
        intervalMinutes = nil
        wallClockHour = nil
        wallClockMinute = nil
        weeklyWeekday = nil
        monthlyDay = nil
        apply(recurrence)
    }
}

extension ScheduledTask {
    var destination: ScheduledTaskDestination {
        get { ScheduledTaskDestination(rawValue: destinationRawValue) ?? .newThread }
        set { destinationRawValue = newValue.rawValue }
    }

    var decodedDestination: ScheduledTaskDestination? {
        ScheduledTaskDestination(rawValue: destinationRawValue)
    }

    var state: ScheduledTaskState {
        get { ScheduledTaskState(rawValue: stateRawValue) ?? .paused }
        set { stateRawValue = newValue.rawValue }
    }

    var workspaceKind: ScheduledTaskWorkspaceKind {
        get { ScheduledTaskWorkspaceKind(rawValue: workspaceKindRawValue) ?? .privateWorkspace }
        set { workspaceKindRawValue = newValue.rawValue }
    }

    var workspaceStrategy: ScheduledTaskWorkspaceStrategy {
        get { ScheduledTaskWorkspaceStrategy(rawValue: workspaceStrategyRawValue) ?? .worktree }
        set { workspaceStrategyRawValue = newValue.rawValue }
    }

    var recurrence: ScheduledTaskRecurrence? {
        get {
            guard let kind = ScheduledTaskRecurrence.Kind(rawValue: recurrenceKindRawValue) else {
                return nil
            }

            switch kind {
            case .once:
                return recurrenceAnchorAt.map(ScheduledTaskRecurrence.once)
            case .interval:
                guard let intervalMinutes, let recurrenceAnchorAt else { return nil }
                return .interval(minutes: intervalMinutes, anchor: recurrenceAnchorAt)
            case .daily:
                guard let wallClockHour, let wallClockMinute else { return nil }
                return .daily(hour: wallClockHour, minute: wallClockMinute)
            case .weekdays:
                guard let wallClockHour, let wallClockMinute else { return nil }
                return .weekdays(days: selectedWeekdays, hour: wallClockHour, minute: wallClockMinute)
            case .weekly:
                guard let weeklyWeekday, let wallClockHour, let wallClockMinute else { return nil }
                return .weekly(weekday: weeklyWeekday, hour: wallClockHour, minute: wallClockMinute)
            case .monthly:
                guard let monthlyDay, let wallClockHour, let wallClockMinute else { return nil }
                return .monthly(day: monthlyDay, hour: wallClockHour, minute: wallClockMinute)
            }
        }
        set {
            guard let newValue else {
                recurrenceKindRawValue = ""
                clearRecurrenceFields()
                return
            }
            apply(newValue)
        }
    }

    static func normalizedUniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { path in
            let normalizedPath = CanonicalPath.normalize(path)
            return seen.insert(normalizedPath).inserted ? normalizedPath : nil
        }
    }
}

private extension ScheduledTask {
    func apply(_ recurrence: ScheduledTaskRecurrence) {
        recurrenceKindRawValue = recurrence.kind.rawValue
        clearRecurrenceFields()

        switch recurrence {
        case let .once(occurrence):
            recurrenceAnchorAt = occurrence
        case let .interval(minutes, anchor):
            recurrenceAnchorAt = anchor
            intervalMinutes = minutes
        case let .daily(hour, minute):
            wallClockHour = hour
            wallClockMinute = minute
        case let .weekdays(days, hour, minute):
            selectedWeekdays = days
            wallClockHour = hour
            wallClockMinute = minute
        case let .weekly(weekday, hour, minute):
            weeklyWeekday = weekday
            wallClockHour = hour
            wallClockMinute = minute
        case let .monthly(day, hour, minute):
            monthlyDay = day
            wallClockHour = hour
            wallClockMinute = minute
        }
    }

    func clearRecurrenceFields() {
        recurrenceAnchorAt = nil
        intervalMinutes = nil
        wallClockHour = nil
        wallClockMinute = nil
        selectedWeekdays = ScheduledTaskRecurrence.standardWeekdays
        weeklyWeekday = nil
        monthlyDay = nil
    }
}
