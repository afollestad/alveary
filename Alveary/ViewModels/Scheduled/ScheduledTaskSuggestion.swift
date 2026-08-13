import Foundation

/// A ready-made starting point offered in the Scheduled screen's empty state. Picking one
/// opens the ordinary create pane pre-filled, so the user still reviews workspace and agent
/// before anything is saved.
struct ScheduledTaskSuggestion: Identifiable, Equatable {
    let id: String
    let icon: ActionIcon
    let title: String
    /// Human phrasing of `schedule` for the card face. A literal rather than
    /// `ScheduledTaskPresentationFormatting.recurrenceSummary(_:timeZoneIdentifier:locale:)`,
    /// which spells an interval as "Every 360 minutes from <date>" — accurate, but neither
    /// short enough for a card nor how anyone describes a six-hour cadence.
    let scheduleCaption: String
    let prompt: String
    let schedule: Schedule

    /// Recurrence without a time origin, so the roster stays a value that compares equal
    /// across body passes. A `ScheduledTaskRecurrence` would have to carry an interval
    /// anchor, and anchoring it at construction would make every rebuild produce a
    /// different roster — the cards render inside the screen's `GeometryReader`, so that
    /// difference would land on every frame of a resize. `ScheduledTasksViewModel`
    /// resolves the anchor when a card is actually clicked.
    enum Schedule: Equatable {
        case everyMinutes(Int)
        case daily(hour: Int, minute: Int)
        case weekdays(hour: Int, minute: Int)
        case weekly(weekday: Int, hour: Int, minute: Int)
    }
}
