import Foundation
import Observation
import SwiftData

/// What a review-proposal card renders and acts on, resolved from the stored envelope.
struct PullRequestReviewProposalPresentation: Identifiable, Equatable {
    let id: String
    let sourceConversationID: String
    let identifier: PullRequestIdentifier
    let title: String
    /// What the model asked for. The user may confirm a different verdict.
    let proposedEvent: PullRequestReviewEvent
    let body: String?
    /// The review's staged inline comments, held in the envelope until the user confirms.
    let comments: [PullRequestReviewProposalRecord.Comment]
    /// The user's own already-pending draft comments on GitHub, distinct from `comments`.
    let pendingCommentCount: Int
    let createdAt: Date

    var displayKey: String {
        identifier.displayKey
    }
}

/// Confirm-time failures of the proposal flow itself, beside the service's own errors.
enum PullRequestReviewProposalSubmissionError: LocalizedError {
    case missingNodeID

    var errorDescription: String? {
        "Alveary could not read the pull request's GitHub node ID to stage the review's comments. Try again."
    }
}

/// Owns the pending review proposals a transcript can confirm, and performs the submission.
///
/// Unlike `ScheduledTaskProposalQueueCoordinator`, confirming here awaits GitHub, so the card needs
/// an in-flight state and confirmation has to stay re-entrancy guarded across that suspension.
@MainActor
@Observable
final class PullRequestReviewProposalCoordinator {
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let pullRequestsService: any PullRequestsService
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    /// Handed to the transcript so a card's comment avatars come from the same cache the
    /// pull-request pane fills. Optional because tests build the coordinator without one.
    @ObservationIgnored let avatarLoader: GitHubAvatarLoader?

    /// Keyed by proposal id: a transcript widget acts on the proposal its own conversation opened,
    /// not on a queue head.
    private(set) var presentations: [String: PullRequestReviewProposalPresentation] = [:]
    /// Every conversation holding a pending review submission. `presentations` only ever holds
    /// pending proposals, so it needs no stored mirror. Thread status reads this to show the
    /// waiting dot; see `ConversationDecisionAttention`.
    var pendingSourceConversationIDs: Set<String> {
        Set(presentations.values.map(\.sourceConversationID))
    }

    private(set) var submittingProposalIDs: Set<String> = []
    private(set) var errorMessages: [String: String] = [:]
    /// The diff-with-comments preview each card renders, loaded on demand.
    private(set) var previews: [String: PullRequestReviewProposalPreviewState] = [:]
    /// The verdict the card's picker holds. The user may submit something other than what the
    /// model proposed, so this lives here rather than in the AppKit row, which is rebuilt freely.
    private(set) var selectedEvents: [String: PullRequestReviewEvent] = [:]
    @ObservationIgnored private var previewTasks: [String: Task<Void, Never>] = [:]

    init(
        modelContext: ModelContext,
        pullRequestsService: any PullRequestsService,
        avatarLoader: GitHubAvatarLoader? = nil,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.pullRequestsService = pullRequestsService
        self.avatarLoader = avatarLoader
        self.notificationCenter = notificationCenter
        self.now = now
        reload()
        observeChanges()
    }

    deinit {
        observationTask?.cancel()
        for task in previewTasks.values {
            task.cancel()
        }
    }

    func presentation(forProposalID proposalID: String) -> PullRequestReviewProposalPresentation? {
        presentations[proposalID]
    }

    func isSubmitting(proposalID: String) -> Bool {
        submittingProposalIDs.contains(proposalID)
    }

    func errorMessage(forProposalID proposalID: String) -> String? {
        errorMessages[proposalID]
    }

    func reload() {
        var loaded: [String: PullRequestReviewProposalPresentation] = [:]
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.pullRequestReviewProposalJSON != nil }
        )
        guard let conversations = try? modelContext.fetch(descriptor) else {
            return
        }
        for conversation in conversations {
            guard let record = try? conversation.pullRequestReviewProposal(),
                  let presentation = Self.presentation(for: record, conversationID: conversation.id) else {
                continue
            }
            loaded[record.id] = presentation
        }
        presentations = loaded
        // Drop preview and error state for proposals that are gone, so a confirmed card cannot
        // keep a stale banner or hold its diff in memory.
        let liveIDs = Set(loaded.keys)
        previews = previews.filter { liveIDs.contains($0.key) }
        errorMessages = errorMessages.filter { liveIDs.contains($0.key) }
        selectedEvents = selectedEvents.filter { liveIDs.contains($0.key) }
        for (proposalID, task) in previewTasks where !liveIDs.contains(proposalID) {
            task.cancel()
            previewTasks[proposalID] = nil
        }
    }

    /// Submits the review the user confirmed. `event` is what the card's verdict picker holds,
    /// which may differ from what the model proposed.
    ///
    /// `bodyOverride` is the summary the pull request pane's footer holds when the submit came from
    /// there; the card passes none and publishes what the model wrote. Empty is the caller's to
    /// normalize away — an untouched footer must fall back to the proposal's body rather than
    /// blanking it.
    @discardableResult
    func confirm(
        proposalID: String,
        event: PullRequestReviewEvent,
        bodyOverride: String? = nil
    ) async -> Bool {
        guard !submittingProposalIDs.contains(proposalID),
              let presentation = presentations[proposalID] else {
            return false
        }
        submittingProposalIDs.insert(proposalID)
        errorMessages[proposalID] = nil
        // Entering and leaving the submitting state both re-render the card; the transcript
        // only re-reads this coordinator on the change notification.
        notifyChanged()
        defer {
            submittingProposalIDs.remove(proposalID)
            notifyChanged()
        }

        do {
            // Re-read GitHub rather than trusting the snapshot: the pull request can merge, or the
            // draft review can change, between proposing and confirming.
            let detail = try await pullRequestsService.fetchDetail(presentation.identifier)
            try await submit(
                presentation: presentation,
                event: event,
                body: bodyOverride ?? presentation.body ?? "",
                detail: detail
            )
        } catch {
            errorMessages[proposalID] = Self.message(for: error)
            return false
        }

        // Submitted. From here a failure may leave the card unresolved, never wrongly resolved.
        //
        // Announce ahead of that, because the review is live on GitHub now: the guard below returns
        // on a save failure, and a pane still showing the pre-review timeline would compound an
        // unresolved card rather than merely accompany it.
        notificationCenter.post(
            name: .pullRequestChangedOnGitHub,
            object: self,
            userInfo: [
                PullRequestChangeNotificationKey.announcement: PullRequestChangeAnnouncement(
                    identifier: presentation.identifier,
                    affectsListRow: true
                )
            ]
        )
        guard clearProposal(proposalID: proposalID, conversationID: presentation.sourceConversationID) else {
            errorMessages[proposalID] = "The review was submitted, but Alveary could not update this card."
            return false
        }
        PullRequestReviewProposalOutcomeRecorder.record(
            proposalID: proposalID,
            sourceConversationID: presentation.sourceConversationID,
            outcome: .confirmed,
            submittedEvent: PullRequestHostToolRequestParser.reviewEventName(for: event),
            in: modelContext,
            at: now()
        )
        notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: self)
        reload()
        return true
    }

    @discardableResult
    func reject(proposalID: String) -> Bool {
        guard !submittingProposalIDs.contains(proposalID),
              let presentation = presentations[proposalID] else {
            return false
        }
        guard clearProposal(proposalID: proposalID, conversationID: presentation.sourceConversationID) else {
            errorMessages[proposalID] = "Alveary could not dismiss this review proposal."
            notifyChanged()
            return false
        }
        PullRequestReviewProposalOutcomeRecorder.record(
            proposalID: proposalID,
            sourceConversationID: presentation.sourceConversationID,
            outcome: .rejected,
            in: modelContext,
            at: now()
        )
        notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: self)
        reload()
        return true
    }

    /// Drops one of the review's staged comments before it is submitted. `index` is the comment's
    /// position in `PullRequestReviewProposalPresentation.comments`, which is the only identity a
    /// staged comment has.
    ///
    /// Local by construction: a staged comment exists nowhere on GitHub until the user confirms, so
    /// this rewrites the stored envelope and prunes the loaded preview rather than calling anything.
    @discardableResult
    func removeStagedComment(proposalID: String, at index: Int) -> Bool {
        guard !submittingProposalIDs.contains(proposalID),
              let presentation = presentations[proposalID],
              presentation.comments.indices.contains(index) else {
            return false
        }
        guard let updated = rewriteProposal(presentation: presentation, { $0.removingComment(at: index) }) else {
            errorMessages[proposalID] = "Alveary could not remove this comment from the review."
            notifyChanged()
            return false
        }
        apply(updated, for: presentation)
        if case .loaded(let preview)? = previews[proposalID] {
            previews[proposalID] = .loaded(Self.preview(preview, removingProposedCommentAt: index))
        }
        errorMessages[proposalID] = nil
        // Card-only: nothing resolved and no transcript record moved, so this must not pay the
        // lifecycle notification's chat-item rebuild.
        notifyChanged()
        return true
    }

    /// Stages one more inline comment on the review, for a comment composed in the pull request
    /// pane while this proposal is pending.
    ///
    /// Local like `removeStagedComment` — the comment exists nowhere on GitHub until the review is
    /// submitted, which is the whole point of composing here rather than into the viewer's draft.
    /// The tool's `maxReviewCommentsPerProposal` deliberately does not apply: it bounds what a
    /// model may send in one call, not what a person may write by hand.
    @discardableResult
    func addStagedComment(
        proposalID: String,
        path: String,
        line: Int,
        side: PullRequestDiffSide,
        body: String
    ) -> Bool {
        guard !submittingProposalIDs.contains(proposalID),
              let presentation = presentations[proposalID] else {
            return false
        }
        let comment = PullRequestReviewProposalRecord.Comment(
            path: path,
            line: line,
            side: side.rawValue,
            body: body
        )
        guard let updated = rewriteProposal(presentation: presentation, { $0.appendingComment(comment) }) else {
            errorMessages[proposalID] = "Alveary could not add this comment to the review."
            notifyChanged()
            return false
        }
        apply(updated, for: presentation)
        // Unlike a removal, this cannot narrow the loaded preview in place: removal only subtracts,
        // while an addition may need a file or hunk the preview deliberately dropped. Invalidate
        // and let `ensurePreview` reload — the user is looking at the pane, so the reload is unseen.
        previews[proposalID] = nil
        previewTasks[proposalID]?.cancel()
        previewTasks[proposalID] = nil
        errorMessages[proposalID] = nil
        notifyChanged()
        return true
    }

    /// Loads the card's diff preview once per proposal. The card is confirmable without it, so a
    /// failure is reported in place rather than blocking the decision.
    func ensurePreview(proposalID: String) {
        guard previews[proposalID] == nil,
              previewTasks[proposalID] == nil,
              let presentation = presentations[proposalID] else {
            return
        }
        // The transcript calls this while resolving card state mid-render, so the observable
        // `.loading` write waits for the task — an absent preview already renders as loading.
        //
        // Whoever cancels this task also clears its handle, and a cancelled run touches neither:
        // `addStagedComment` cancels an in-flight load, so a task that cleared the slot on its way
        // out would clobber the handle of the reload that replaced it.
        previewTasks[proposalID] = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else {
                return
            }
            previews[proposalID] = .loading
            let state = await loadPreview(for: presentation)
            guard !Task.isCancelled, presentations[proposalID] != nil else {
                return
            }
            previewTasks[proposalID] = nil
            previews[proposalID] = state
            // The loaded diff changes the card's height and body; without the notification the
            // transcript would keep rendering the loading state until something else invalidates.
            notifyChanged()
        }
    }

    func preview(forProposalID proposalID: String) -> PullRequestReviewProposalPreviewState? {
        previews[proposalID]
    }

    /// Defaults to what the model proposed until the user picks otherwise.
    func selectedEvent(forProposalID proposalID: String) -> PullRequestReviewEvent? {
        selectedEvents[proposalID] ?? presentations[proposalID]?.proposedEvent
    }

    func selectEvent(_ event: PullRequestReviewEvent, forProposalID proposalID: String) {
        guard presentations[proposalID] != nil else {
            return
        }
        selectedEvents[proposalID] = event
        errorMessages[proposalID] = nil
        notifyChanged()
    }

    /// Whether the picker's current verdict can be submitted, using the same rules the pull
    /// request pane's footer applies.
    func canSubmit(proposalID: String, event: PullRequestReviewEvent) -> Bool {
        guard let presentation = presentations[proposalID] else {
            return false
        }
        if case .loaded(let preview) = previews[proposalID], preview.viewerIsAuthor,
           event == .approve || event == .requestChanges {
            // GitHub rejects both verdicts on the viewer's own pull request.
            return false
        }
        var draft = PendingReviewDraft()
        draft.overallComment = presentation.body ?? ""
        // Staged comments count like pending ones: confirming publishes both.
        return PullRequestsViewModel.canSubmitReview(
            event: event,
            draft: draft,
            pendingCommentCount: presentation.pendingCommentCount + presentation.comments.count
        )
    }

    var service: any PullRequestsService {
        pullRequestsService
    }
}

private extension PullRequestReviewProposalCoordinator {
    static func presentation(
        for record: PullRequestReviewProposalRecord,
        conversationID: String
    ) -> PullRequestReviewProposalPresentation? {
        guard let identifier = record.identifier,
              let event = PullRequestHostToolRequestParser.reviewEvent(from: record.event) else {
            return nil
        }
        return PullRequestReviewProposalPresentation(
            id: record.id,
            sourceConversationID: conversationID,
            identifier: identifier,
            title: record.titleSnapshot,
            proposedEvent: event,
            body: record.body,
            comments: record.stagedComments,
            pendingCommentCount: record.pendingCommentCountSnapshot,
            createdAt: record.createdAt
        )
    }

    /// Re-reads the envelope before editing it — the proposal may have been resolved or superseded
    /// since the surface that asked for the edit rendered — and returns the stored replacement.
    /// `edit` returns nil to refuse.
    func rewriteProposal(
        presentation: PullRequestReviewProposalPresentation,
        _ edit: (PullRequestReviewProposalRecord) -> PullRequestReviewProposalRecord?
    ) -> PullRequestReviewProposalRecord? {
        guard let conversation = modelContext.resolveConversation(
            conversationID: presentation.sourceConversationID
        ),
            let record = try? conversation.pullRequestReviewProposal(),
            record.id == presentation.id,
            let updated = edit(record) else {
            return nil
        }
        do {
            try conversation.storePullRequestReviewProposal(updated)
            try modelContext.save()
            return updated
        } catch {
            modelContext.rollback()
            return nil
        }
    }

    /// Republishes an edited envelope. A nil re-derivation would clear the entry, dropping a
    /// proposal that is still pending; the envelope just round-tripped through a decode, so it
    /// cannot happen, and keeping the old presentation is the safe direction.
    func apply(
        _ updated: PullRequestReviewProposalRecord,
        for presentation: PullRequestReviewProposalPresentation
    ) {
        guard let refreshed = Self.presentation(
            for: updated,
            conversationID: presentation.sourceConversationID
        ) else {
            return
        }
        presentations[presentation.id] = refreshed
    }

    /// Clears the envelope in its own save, ahead of the outcome marker's.
    func clearProposal(proposalID: String, conversationID: String) -> Bool {
        guard let conversation = modelContext.resolveConversation(conversationID: conversationID) else {
            // The conversation is gone, so the proposal went with it.
            return true
        }
        guard (try? conversation.pullRequestReviewProposal())??.id == proposalID else {
            // Already resolved elsewhere; whichever path did it wrote the marker.
            return true
        }
        conversation.clearPullRequestReviewProposal()
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            return false
        }
    }

    /// The lightweight signal for state only the card renders — picked verdict, preview,
    /// submitting, errors. The lifecycle notification is deliberately not reused here: its
    /// transcript observer also rebuilds chat items, which a picker click must not pay for.
    func notifyChanged() {
        notificationCenter.post(name: .reviewProposalCardStateChanged, object: self)
    }

    static func message(for error: Error) -> String {
        guard let serviceError = error as? PullRequestsServiceError else {
            return error.localizedDescription
        }
        return serviceError.errorDescription ?? serviceError.localizedDescription
    }

    func observeChanges() {
        let notifications = notificationCenter.notifications(named: .pullRequestReviewProposalsChanged)
        observationTask = Task { @MainActor [weak self] in
            for await _ in notifications {
                guard !Task.isCancelled else {
                    return
                }
                self?.reload()
            }
        }
    }
}
