import Foundation
import SwiftData

/// Pane entry points used by transcript host-tool widgets, scoped to the thread that
/// opened them so a pane cannot follow the user onto another surface.
extension ScheduledTasksViewModel {
    /// Opens a definition for editing from a transcript widget, scoped to that thread.
    ///
    /// Returns `false` when the definition is gone, so the caller can fall back rather
    /// than leave the card's action doing nothing.
    @discardableResult
    func requestEditFromTranscript(definitionID: String, originThreadID: PersistentIdentifier?) -> Bool {
        guard requestEdit(definitionID: definitionID) else {
            return false
        }
        proposalPaneOriginThreadID = originThreadID
        return true
    }

    /// A transcript-opened pane belongs to the thread that opened it, mirroring how a
    /// pull-request pane is scoped to its origin surface.
    func activeTranscriptPaneTarget(forThreadID threadID: PersistentIdentifier) -> ScheduledTaskPaneTarget? {
        guard let activePaneTarget, activePaneTarget != .create,
              proposalPaneOriginThreadID == threadID else {
            return nil
        }
        return activePaneTarget
    }
}

extension ScheduledTasksViewModel {
    /// Current definitions in the shape the list tool's expanded detail renders.
    var transcriptScheduledTaskRows: [ScheduledTaskListRow] {
        tasks.map { task in
            ScheduledTaskListRow(
                id: task.id,
                title: task.title,
                state: task.state,
                scheduleSummary: ScheduledTaskPresentationFormatting.recurrenceSummary(
                    task.recurrence,
                    timeZoneIdentifier: task.timeZoneIdentifier
                ),
                hasActiveRun: task.hasActiveRun
            )
        }
    }
}
