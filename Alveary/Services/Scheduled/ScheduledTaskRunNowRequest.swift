import Foundation

enum ScheduledTaskRunNowOccurrenceSource: Equatable, Sendable {
    case scheduled
    case pending
    case manual
}

struct ScheduledTaskRunNowRequest: Equatable, Sendable {
    let definitionID: String
    let definitionRevision: Int
    let occurrenceAt: Date
    let triggeredAt: Date
    let occurrenceSource: ScheduledTaskRunNowOccurrenceSource
    let idempotencyKey: String?

    init(
        definitionID: String,
        definitionRevision: Int,
        occurrenceAt: Date,
        triggeredAt: Date,
        occurrenceSource: ScheduledTaskRunNowOccurrenceSource,
        idempotencyKey: String? = nil
    ) {
        self.definitionID = definitionID
        self.definitionRevision = definitionRevision
        self.occurrenceAt = occurrenceAt
        self.triggeredAt = triggeredAt
        self.occurrenceSource = occurrenceSource
        self.idempotencyKey = idempotencyKey
    }

    var consumesScheduledOccurrence: Bool {
        occurrenceSource != .manual
    }

    @MainActor
    static func prepare(
        definition: ScheduledTask,
        triggeredAt: Date,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator,
        idempotencyKey: String? = nil
    ) -> Self {
        let scheduledOccurrence = latestScheduledOccurrence(
            definition: definition,
            through: triggeredAt,
            recurrenceCalculator: recurrenceCalculator
        )
        let pendingOccurrence = definition.pendingOccurrenceAt.flatMap { occurrence in
            occurrence <= triggeredAt ? occurrence : nil
        }

        let occurrenceAt: Date
        let occurrenceSource: ScheduledTaskRunNowOccurrenceSource
        switch (scheduledOccurrence, pendingOccurrence) {
        case let (scheduled?, pending?) where pending > scheduled:
            occurrenceAt = pending
            occurrenceSource = .pending
        case let (scheduled?, _):
            occurrenceAt = scheduled
            occurrenceSource = .scheduled
        case let (nil, pending?):
            occurrenceAt = pending
            occurrenceSource = .pending
        case (nil, nil):
            occurrenceAt = triggeredAt
            occurrenceSource = .manual
        }

        return Self(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: occurrenceAt,
            triggeredAt: triggeredAt,
            occurrenceSource: occurrenceSource,
            idempotencyKey: idempotencyKey
        )
    }

    @MainActor
    private static func latestScheduledOccurrence(
        definition: ScheduledTask,
        through actionDate: Date,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator
    ) -> Date? {
        guard let firstOccurrence = definition.nextOccurrenceAt,
              firstOccurrence <= actionDate else {
            return nil
        }
        guard let recurrence = definition.recurrence,
              let window = try? recurrenceCalculator.coalescedOccurrences(
                  startingAt: firstOccurrence,
                  through: actionDate,
                  recurrence: recurrence,
                  timeZoneIdentifier: definition.timeZoneIdentifier
              ) else {
            // Let scheduler preflight pause malformed definitions instead of
            // turning Run now preparation into a separate validation path.
            return firstOccurrence
        }
        return window.latestDueOccurrence ?? firstOccurrence
    }
}
