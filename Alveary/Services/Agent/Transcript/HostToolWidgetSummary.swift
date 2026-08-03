import Foundation

/// One-line status copy for host-tool widgets, in the transcript's usual
/// present-tense-while-running, past-tense-when-done voice.
enum HostToolWidgetSummary {
    /// `isTargetRunInFlight` is the live signal for run-now tense: present while the
    /// launched run is still going, past once it finishes (and for restored history).
    static func text(for entry: HostToolWidgetEntry, isTargetRunInFlight: Bool = false) -> String {
        switch entry.content {
        case .scheduledTaskProposal(let content):
            proposalText(content, entry: entry, isTargetRunInFlight: isTargetRunInFlight)
        case .pullRequestLink(let content):
            pullRequestLinkText(content, entry: entry)
        case .threadAction(let content):
            threadActionText(content, entry: entry)
        }
    }

    /// Secondary detail line; `nil` when the summary already says everything.
    static func detail(for entry: HostToolWidgetEntry) -> String? {
        switch entry.content {
        case .scheduledTaskProposal(let content):
            guard content.action == .create || content.action == .edit else {
                return nil
            }
            return content.scheduleSummary
        case .pullRequestLink(let content):
            // A refusal has no snapshot to name, so the reason takes the line instead.
            return content.status == .failed ? content.message : content.title
        case .threadAction(let content):
            // Only a created Project thread has a path to show; the rest say everything in
            // the summary, and a refusal puts its reason here.
            return content.status == .failed ? content.message : content.projectPath
        }
    }
}

private extension HostToolWidgetSummary {
    /// The link tools apply immediately, so there is no pending or rejected voice here — a
    /// landed call is past tense, and `already_linked` / `not_linked` say the state was
    /// already what was asked for rather than that the request did nothing useful.
    static func pullRequestLinkText(
        _ content: PullRequestLinkWidgetContent,
        entry: HostToolWidgetEntry
    ) -> String {
        let isLink = content.action == .link
        guard content.status != .running, !entry.isInterrupted else {
            return isLink ? "Linking pull request…" : "Unlinking pull request…"
        }
        guard content.status != .failed else {
            return isLink ? "Could not link the pull request" : "Could not unlink the pull request"
        }
        let phrase: String
        switch (content.action, content.status) {
        case (.link, .unchanged):
            phrase = "PR already linked to thread"
        case (.link, _):
            phrase = "PR linked to thread"
        case (.unlink, .unchanged):
            // A thread carrying no links echoes no snapshot, so this is the one case with no
            // pull request to name — and the only one that may drop the key from its copy.
            phrase = content.identifier == nil
                ? "No pull request was linked to the thread"
                : "PR was not linked to thread"
        case (.unlink, _):
            phrase = "PR unlinked from thread"
        }
        return append(content.identifier?.displayKey, to: phrase)
    }

    /// Thread mutations apply immediately too, so there is no pending or rejected voice — a
    /// landed call is past tense, and an `already_*` status says the thread was already in the
    /// requested state rather than that the request did nothing useful.
    static func threadActionText(
        _ content: ThreadActionWidgetContent,
        entry: HostToolWidgetEntry
    ) -> String {
        let phrases = threadPhrases(for: content.action)
        guard content.status != .running, !entry.isInterrupted else {
            return "\(phrases.running)…"
        }
        guard content.status != .failed else {
            return phrases.failed
        }
        return append(content.name, to: content.status == .unchanged ? phrases.unchanged : phrases.applied)
    }

    struct ThreadPhrases {
        let running: String
        let applied: String
        let unchanged: String
        let failed: String
    }

    static func threadPhrases(for action: ThreadActionWidgetContent.Action) -> ThreadPhrases {
        switch action {
        case .create:
            ThreadPhrases(
                running: "Creating thread",
                applied: "Thread created",
                // `create_thread` reports no unchanged status; a replayed receipt is still a
                // thread that now exists.
                unchanged: "Thread created",
                failed: "Could not create the thread"
            )
        case .pin:
            ThreadPhrases(
                running: "Pinning thread",
                applied: "Thread pinned",
                unchanged: "Thread already pinned",
                failed: "Could not pin the thread"
            )
        case .unpin:
            ThreadPhrases(
                running: "Unpinning thread",
                applied: "Thread unpinned",
                unchanged: "Thread was not pinned",
                failed: "Could not unpin the thread"
            )
        case .archive:
            ThreadPhrases(
                running: "Archiving thread",
                applied: "Thread archived",
                unchanged: "Thread was already archived",
                failed: "Could not archive the thread"
            )
        }
    }

    static func proposalText(
        _ content: ScheduledTaskProposalWidgetContent,
        entry: HostToolWidgetEntry,
        isTargetRunInFlight: Bool
    ) -> String {
        let phrases = phrases(for: content.action)
        guard content.status != .running, !entry.isInterrupted else {
            return "\(phrases.running)…"
        }
        if content.status == .failed {
            return phrases.failed
        }

        let name = displayName(for: content, entry: entry)
        let confirmed = confirmedPhrase(phrases, content: content, isTargetRunInFlight: isTargetRunInFlight)
        switch entry.outcome {
        case .confirmed:
            return append(name, to: confirmed)
        case .rejected:
            return append(name, to: phrases.rejected)
        case nil:
            // An applied action needs no decision, so it reads in the past tense already.
            return append(name, to: content.status == .applied ? confirmed : phrases.pending)
        }
    }

    /// Run-now's confirmation only starts the run, so its resolved copy follows the
    /// run's own lifecycle rather than staying frozen at the moment of confirmation.
    static func confirmedPhrase(
        _ phrases: Phrases,
        content: ScheduledTaskProposalWidgetContent,
        isTargetRunInFlight: Bool
    ) -> String {
        guard content.action == .runNow, !isTargetRunInFlight else {
            return phrases.confirmed
        }
        return "Ran scheduled task"
    }

    static func append(_ name: String?, to phrase: String) -> String {
        guard let name, !name.isEmpty else {
            return phrase
        }
        return "\(phrase): \(name)"
    }

    static func displayName(
        for content: ScheduledTaskProposalWidgetContent,
        entry: HostToolWidgetEntry
    ) -> String? {
        // State-change requests carry no title, and a plain-text fallback result loses
        // the receipt's echo; the outcome marker is the only durable name then.
        content.proposedTitle ?? entry.outcomeTitle
    }

    struct Phrases {
        let running: String
        let pending: String
        let confirmed: String
        let rejected: String
        let failed: String
    }

    static func phrases(for action: ScheduledTaskProposalAction?) -> Phrases {
        switch action {
        case .create, .edit:
            definitionPhrases(for: action)
        default:
            stateChangePhrases(for: action)
        }
    }

    static func definitionPhrases(for action: ScheduledTaskProposalAction?) -> Phrases {
        guard action == .edit else {
            return Phrases(
                running: "Creating new scheduled task",
                pending: "Create new scheduled task",
                confirmed: "Created new scheduled task",
                rejected: "Discarded new scheduled task",
                failed: "Could not create a scheduled task"
            )
        }
        return Phrases(
            running: "Updating scheduled task",
            pending: "Update scheduled task",
            confirmed: "Updated scheduled task",
            rejected: "Discarded changes to scheduled task",
            failed: "Could not update the scheduled task"
        )
    }

    static func stateChangePhrases(for action: ScheduledTaskProposalAction?) -> Phrases {
        switch action {
        case .pause:
            Phrases(
                running: "Pausing scheduled task",
                pending: "Pause scheduled task",
                confirmed: "Scheduled task paused",
                rejected: "Left scheduled task running",
                failed: "Could not pause the scheduled task"
            )
        case .resume:
            Phrases(
                running: "Resuming scheduled task",
                pending: "Resume scheduled task",
                confirmed: "Scheduled task resumed",
                rejected: "Left scheduled task paused",
                failed: "Could not resume the scheduled task"
            )
        case .delete:
            Phrases(
                running: "Deleting scheduled task",
                pending: "Delete scheduled task",
                confirmed: "Deleted scheduled task",
                rejected: "Kept scheduled task",
                failed: "Could not delete the scheduled task"
            )
        case .runNow:
            Phrases(
                running: "Starting scheduled task run",
                pending: "Run scheduled task now",
                confirmed: "Running scheduled task now",
                rejected: "Did not start scheduled task run",
                failed: "Could not start the scheduled task run"
            )
        default:
            Phrases(
                running: "Opening scheduling proposal",
                pending: "Scheduling proposal unavailable",
                confirmed: "Scheduling proposal applied",
                rejected: "Scheduling proposal discarded",
                failed: "Scheduling proposal could not be read"
            )
        }
    }
}
