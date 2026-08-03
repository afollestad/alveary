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
        }
    }

    /// Secondary detail line; `nil` when the summary already says everything.
    static func detail(for entry: HostToolWidgetEntry) -> String? {
        guard case .scheduledTaskProposal(let content) = entry.content,
              content.action == .create || content.action == .edit else {
            return nil
        }
        return content.scheduleSummary
    }
}

private extension HostToolWidgetSummary {
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
