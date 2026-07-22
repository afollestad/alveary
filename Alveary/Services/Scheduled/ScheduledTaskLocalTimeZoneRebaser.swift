import Foundation
import SwiftData

@MainActor
struct ScheduledTaskLocalTimeZoneRebaser {
    typealias TimeZoneProvider = @MainActor () -> TimeZone

    private let modelContext: ModelContext
    private let recurrenceCalculator: ScheduledTaskRecurrenceCalculator
    private let currentTimeZone: TimeZoneProvider

    init(
        modelContext: ModelContext,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator = ScheduledTaskRecurrenceCalculator(),
        currentTimeZone: @escaping TimeZoneProvider = { .autoupdatingCurrent }
    ) {
        self.modelContext = modelContext
        self.recurrenceCalculator = recurrenceCalculator
        self.currentTimeZone = currentTimeZone
    }

    @discardableResult
    func rebaseAll(at actionDate: Date) throws -> Bool {
        if modelContext.hasChanges {
            try modelContext.save()
        }
        let definitions = try modelContext.fetch(FetchDescriptor<ScheduledTask>())
        let timeZoneIdentifier = currentTimeZone().identifier
        var changed = false
        for definition in definitions {
            changed = Self.rebase(
                definition,
                to: timeZoneIdentifier,
                at: actionDate,
                recurrenceCalculator: recurrenceCalculator
            ) || changed
        }
        guard changed else {
            return false
        }
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    static func rebase(
        _ definition: ScheduledTask,
        to timeZoneIdentifier: String,
        at actionDate: Date,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator
    ) -> Bool {
        guard definition.timeZoneIdentifier != timeZoneIdentifier else {
            return false
        }
        definition.timeZoneIdentifier = timeZoneIdentifier
        guard let recurrence = definition.recurrence,
              recurrence.followsLocalTimeZone,
              definition.state == .active || definition.state == .paused else {
            return true
        }
        definition.nextOccurrenceAt = try? recurrenceCalculator.nextOccurrence(
            strictlyAfter: actionDate,
            recurrence: recurrence,
            timeZoneIdentifier: timeZoneIdentifier
        )
        return true
    }
}

private extension ScheduledTaskRecurrence {
    var followsLocalTimeZone: Bool {
        switch self {
        case .daily, .weekdays, .weekly, .monthly:
            return true
        case .once, .interval:
            return false
        }
    }
}
