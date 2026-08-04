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
        case .pullRequestReviewProposal(let content):
            reviewProposalText(content, entry: entry)
        case .pullRequestList(let content):
            pullRequestListText(content, entry: entry)
        case .threadAction(let content):
            threadActionText(content, entry: entry)
        }
    }

    /// The substring of `text(for:)` the card draws in bold: the pull request it names, which is
    /// the one part of that line that differs card to card. A card that names a thread or a task
    /// emphasizes nothing — those already carry the user's own words.
    static func emphasis(for entry: HostToolWidgetEntry) -> String? {
        switch entry.content {
        case .pullRequestReviewProposal(let content):
            content.identifier?.displayKey
        case .pullRequestLink(let content):
            content.identifier?.displayKey
        case .scheduledTaskProposal, .pullRequestList, .threadAction:
            nil
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
        case .pullRequestReviewProposal(let content):
            // The summary body is what the review would say, so it is the detail worth showing;
            // a refusal puts its reason here instead.
            return content.status == .failed ? content.message : content.body
        case .pullRequestList(let content):
            return pullRequestListDetail(content)
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

    /// The rows say everything the card needs, so the detail line carries only what they cannot:
    /// that the list is short of the real total, or incomplete because GitHub refused part of it.
    /// The message is never dumped here — it is the whole list, dozens of lines, in one slot.
    static func pullRequestListDetail(_ content: PullRequestListWidgetContent) -> String? {
        if content.status == .failed {
            return content.message
        }
        var parts: [String] = []
        if content.hiddenRowCount > 0 {
            parts.append("\(content.hiddenRowCount) more not shown")
        }
        if content.hasWarnings {
            parts.append("Some organization results were unavailable")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Names the scope that was searched, because "reviewing" and "authored" answer different
    /// questions and an unqualified count would read as the user's whole set.
    static func pullRequestListText(
        _ content: PullRequestListWidgetContent,
        entry: HostToolWidgetEntry
    ) -> String {
        guard content.status != .running, !entry.isInterrupted else {
            return "Finding pull requests…"
        }
        guard content.status != .failed else {
            return "Could not list pull requests"
        }
        guard content.status != .listedWithoutRows else {
            // The call landed but nothing was readable to list, so the copy stays neutral rather
            // than claiming a count or an empty result.
            return "Listed pull requests"
        }
        guard !content.rows.isEmpty else {
            return scopedListPhrase("No pull requests", filter: content.filter)
        }
        let count = content.rows.count == 1 ? "1 pull request" : "\(content.rows.count) pull requests"
        return scopedListPhrase(count, filter: content.filter)
    }

    static func scopedListPhrase(_ phrase: String, filter: PullRequestHostToolListFilter?) -> String {
        switch filter {
        case .authored:
            "\(phrase) you opened"
        case .reviewing:
            "\(phrase) to review"
        case .all, nil:
            "\(phrase) you are involved in"
        }
    }

    /// A review proposal always waits on the user, so the resolved copy names the verdict the
    /// user actually submitted — which the outcome marker carries, because they may confirm a
    /// different one than the model proposed.
    static func reviewProposalText(
        _ content: PullRequestReviewProposalWidgetContent,
        entry: HostToolWidgetEntry
    ) -> String {
        guard content.status != .running, !entry.isInterrupted else {
            return "Preparing review…"
        }
        guard content.status != .failed else {
            return "Could not prepare the review"
        }
        let key = content.identifier?.displayKey
        let submitted = entry.outcomeTitle
            .flatMap(PullRequestHostToolRequestParser.reviewEvent(from:)) ?? content.event
        switch entry.outcome {
        case .confirmed:
            return append(key, to: confirmedReviewPhrase(submitted))
        case .rejected:
            return append(key, to: "Review not submitted")
        case nil:
            return pendingReviewPhrase(content.event, key: key)
        }
    }

    /// The one phrase that asks rather than states, so it takes the pull request into the question
    /// itself — `append`'s colon would land after the question mark.
    ///
    /// The comment verdict's copy names the review, never "a comment": one submission publishes
    /// every pending comment attached to it, so a singular noun misreports the common case, and a
    /// comment review may carry only a summary body and no line comments at all.
    static func pendingReviewPhrase(_ event: PullRequestReviewEvent, key: String?) -> String {
        let subject = key ?? "pull request"
        switch event {
        case .approve:
            return "Approve \(subject)?"
        case .requestChanges:
            return "Request changes on \(subject)?"
        case .comment:
            return key.map { "Submit review of \($0)?" } ?? "Submit review?"
        }
    }

    static func confirmedReviewPhrase(_ event: PullRequestReviewEvent) -> String {
        switch event {
        case .approve:
            "Pull request approved"
        case .requestChanges:
            "Changes requested"
        case .comment:
            "Review submitted"
        }
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
