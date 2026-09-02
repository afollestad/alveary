import Foundation

/// The actions a task's card offers: Pause, Resume, Delete, and Run now. Each routes through
/// `ScheduledTaskMutationService` with the row's captured revision, so a definition edited
/// elsewhere since the card rendered fails the revision check rather than clobbering it.
///
/// Pause and Resume also serve the editor pane's footer toggle, so on success they re-stamp
/// that pane's cached draft with the bumped revision; otherwise the user's in-progress edits
/// can never be saved.
extension ScheduledTasksViewModel {
    func pause(_ task: ScheduledTaskRowPresentation) {
        performStateMutation(on: task) {
            try mutationService.pause(
                definitionID: task.id,
                expectedRevision: task.revision,
                at: now()
            )
        }
    }

    func resume(_ task: ScheduledTaskRowPresentation) {
        performStateMutation(on: task) {
            try mutationService.resume(
                definitionID: task.id,
                expectedRevision: task.revision,
                at: now()
            )
        }
    }

    func delete(_ task: ScheduledTaskRowPresentation) {
        do {
            try mutationService.delete(definitionID: task.id, expectedRevision: task.revision)
            discardEditSession(definitionID: task.id)
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }

    func runNow(_ task: ScheduledTaskRowPresentation) {
        do {
            let request = try mutationService.prepareRunNow(
                definitionID: task.id,
                expectedRevision: task.revision,
                at: now()
            )
            guard runNowAction(request) else {
                throw ScheduledTasksViewModelError.runNowRejected
            }
            errorMessage = nil
            pendingRunNowDefinitionIDs.insert(task.id)
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }
}

private extension ScheduledTasksViewModel {
    /// Reloads on either outcome: a failed mutation may still have advanced the row's
    /// revision, so the stale presentation would fail every retry after it.
    func performStateMutation(on task: ScheduledTaskRowPresentation, _ mutation: () throws -> Void) {
        do {
            try mutation()
            errorMessage = nil
            refreshEditSessionRevision(definitionID: task.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }
}
