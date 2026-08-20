import Foundation

enum ScheduledTasksViewModelError: Error, LocalizedError {
    case titleRequired
    case promptRequired
    case projectRequired
    case projectNotFound
    case existingThreadRequired
    case existingThreadUnavailable
    case destinationNotRecognized
    case sectionNotFound
    case runNowRejected

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            "Enter a title for the scheduled task."
        case .promptRequired:
            "Enter instructions for the scheduled task."
        case .projectRequired:
            "Choose a project for this scheduled task."
        case .projectNotFound:
            "The selected project no longer exists."
        case .existingThreadRequired:
            "Choose a thread for this scheduled task."
        case .existingThreadUnavailable:
            "The selected thread is no longer available."
        case .destinationNotRecognized:
            """
            This task's destination was written by a newer version of Alveary. \
            Choose where its runs should post to repair it.
            """
        case .sectionNotFound:
            "The selected sidebar section no longer exists."
        case .runNowRejected:
            "This scheduled task could not be started. It may already be starting or the scheduler may be unavailable."
        }
    }
}

enum ScheduledTaskPaneTarget: Hashable {
    case create
    case edit(String)
    /// Reviewing a natural-language proposal. Keyed by the *source conversation*, not the
    /// proposal, so a follow-up prompt that supersedes the proposal updates this pane in
    /// place instead of replacing it with a second presentation.
    case proposal(sourceConversationID: String)
}

struct ScheduledTaskPaneSession: Equatable {
    let generation: UUID
    var draft: ScheduledTaskEditorDraft
    var errorMessage: String?
    var isSubmitting = false
    /// Proposal this session is confirming, for `.proposal` targets only.
    var proposalID: String?
}
