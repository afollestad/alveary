import Foundation
import Observation
import SwiftData

/// Owns the pending review proposals a transcript can confirm, and performs the submission.
///
/// Unlike `ScheduledTaskProposalQueueCoordinator`, confirming here awaits GitHub, so the card needs
/// an in-flight state and confirmation has to stay re-entrancy guarded across that suspension.
@MainActor
@Observable
final class PullRequestReviewProposalCoordinator {
    /// Shared with the persistence companion for its container and outcome records.
    @ObservationIgnored let modelContext: ModelContext
    @ObservationIgnored private let pullRequestsService: any PullRequestsService
    /// Internal rather than private so `+Submission.swift` can announce the submitting span on the
    /// same bus this coordinator observes. Immutable, so nothing is loosened by widening it.
    @ObservationIgnored let notificationCenter: NotificationCenter
    @ObservationIgnored private let now: () -> Date
    /// Hunks a card can paint before any network runs, seeded at propose time. Optional because
    /// tests build the coordinator without one, in which case every card loads as it always did.
    @ObservationIgnored let previewCache: PullRequestReviewProposalPreviewCache?
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var remoteChangeTask: Task<Void, Never>?
    @ObservationIgnored private var bodyChangeTask: Task<Void, Never>?
    @ObservationIgnored var previewCacheTask: Task<Void, Never>?
    @ObservationIgnored var previewWarmTask: Task<Void, Never>?
    /// How long `scheduleRemoteReload` waits before reloading what an announcement invalidated.
    /// Mirrors `PullRequestsViewModel.remoteRefreshDelay`, which coalesces the same burst.
    @ObservationIgnored let remoteReloadDelay: Duration
    @ObservationIgnored var remoteReloadTask: Task<Void, Never>?
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

    /// The conversation each in-flight submission publishes from, keyed by proposal id.
    /// Kept when `reload()` clears a presentation so activity remains visible through submission.
    /// Its setter is internal only for the paired transitions in `+Submission.swift`.
    var submittingConversationIDsByProposalID: [String: String] = [:]

    /// Every conversation inside `confirm`'s network span. Thread status reads this to raise the
    /// working ring over the waiting dot for exactly that long; see `ConversationWorkActivity`.
    var submittingSourceConversationIDs: Set<String> {
        Set(submittingConversationIDsByProposalID.values)
    }

    private var sharedSubmittingProposalIDs: Set<String> = []
    private(set) var errorMessages: [String: String] = [:]
    /// The diff-with-comments preview each card renders, painted from cache and refreshed behind.
    ///
    /// Internal rather than `private(set)` because `+PreviewCache.swift` owns every transition it
    /// goes through; Swift cannot scope a setter to two files. Nothing outside this type's own
    /// files may write it.
    var previews: [String: PullRequestReviewProposalPreviewState] = [:]
    /// The verdict the card's picker holds. The user may submit something other than what the
    /// model proposed, so this lives here rather than in the AppKit row, which is rebuilt freely.
    private(set) var selectedEvents: [String: PullRequestReviewEvent] = [:]
    @ObservationIgnored var previewTasks: [String: Task<Void, Never>] = [:]
    /// Proposals whose diff has been refreshed from GitHub this session.
    ///
    /// Separate from `previews` because a cache paint fills that dictionary without having talked
    /// to GitHub; gating `ensurePreview` on `previews[id] == nil` would read a painted card as an
    /// already-refreshed one and suppress the refresh forever. Whoever invalidates a preview clears
    /// this too, or the reload it wants never runs.
    @ObservationIgnored var refreshedProposalIDs: Set<String> = []

    init(
        modelContext: ModelContext,
        pullRequestsService: any PullRequestsService,
        avatarLoader: GitHubAvatarLoader? = nil,
        previewCache: PullRequestReviewProposalPreviewCache? = nil,
        notificationCenter: NotificationCenter = .default,
        remoteReloadDelay: Duration = .milliseconds(750),
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.pullRequestsService = pullRequestsService
        self.avatarLoader = avatarLoader
        self.previewCache = previewCache
        self.notificationCenter = notificationCenter
        self.remoteReloadDelay = remoteReloadDelay
        self.now = now
        reload()
        observeChanges()
    }

    deinit {
        observationTask?.cancel()
        remoteChangeTask?.cancel()
        bodyChangeTask?.cancel()
        previewCacheTask?.cancel()
        previewWarmTask?.cancel()
        remoteReloadTask?.cancel()
        for task in previewTasks.values {
            task.cancel()
        }
    }

    /// The extensions in this file's companions cannot reach `now`, and a preview entry has to be
    /// stamped where it is built. Mirrors the `service` accessor below.
    var currentDate: Date {
        now()
    }

    /// The lightweight signal for state only the card renders — picked verdict, preview,
    /// submitting, errors. The lifecycle notification is deliberately not reused here: its
    /// transcript observer also rebuilds chat items, which a picker click must not pay for.
    func notifyChanged() {
        notificationCenter.post(name: .reviewProposalCardStateChanged, object: self)
    }

    func presentation(forProposalID proposalID: String) -> PullRequestReviewProposalPresentation? {
        presentations[proposalID]
    }

    func isSubmitting(proposalID: String) -> Bool {
        submittingConversationIDsByProposalID[proposalID] != nil
            || sharedSubmittingProposalIDs.contains(proposalID)
            || PullRequestReviewProposalEditState.current(proposalID: proposalID)?.isSubmitting == true
    }

    func errorMessage(forProposalID proposalID: String) -> String? {
        errorMessages[proposalID]
    }

    func reload() {
        var loaded: [String: PullRequestReviewProposalPresentation] = [:]
        let reader = ModelContext(modelContext.container)
        guard let conversations = try? reader.fetch(
            PullRequestReviewProposalLookup.proposalHoldingConversations
        ) else {
            return
        }
        let conversationsByID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        for owner in PullRequestReviewProposalLookup.proposals(in: conversations) {
            guard let conversation = conversationsByID[owner.conversationID] else { continue }
            guard let presentation = Self.presentation(
                for: owner.record,
                conversation: conversation
            ) else {
                continue
            }
            loaded[owner.record.id] = presentation
        }
        presentations = loaded
        refreshSharedSubmissionState()
        // Drop preview and error state for proposals that are gone, so a confirmed card cannot
        // keep a stale banner or hold its diff in memory.
        let liveIDs = Set(loaded.keys)
        previews = previews.filter { liveIDs.contains($0.key) }
        errorMessages = errorMessages.filter { liveIDs.contains($0.key) }
        selectedEvents = selectedEvents.filter { liveIDs.contains($0.key) }
        refreshedProposalIDs.formIntersection(liveIDs)
        for (proposalID, task) in previewTasks where !liveIDs.contains(proposalID) {
            task.cancel()
            previewTasks[proposalID] = nil
        }
        // A resolved proposal's hunks would otherwise outlive it on disk.
        if let previewCache {
            Task {
                await previewCache.prune(keepingProposalIDs: liveIDs)
            }
        }
        // After the prune task is spawned, not before: the paint skips entries with no live
        // presentation either way, but this ordering keeps a re-read from resurrecting one.
        loadCachedPreviews()
    }

    /// Publishes the saved proposal, including an intentionally empty top-level comment.
    @discardableResult
    func confirm(proposalID: String, event: PullRequestReviewEvent) async -> Bool {
        guard !isSubmitting(proposalID: proposalID),
              refreshSavedProposal(proposalID: proposalID),
              let presentation = presentations[proposalID] else { return false }
        beginSubmitting(proposalID, conversationID: presentation.sourceConversationID)
        errorMessages[proposalID] = nil
        // Entering and leaving the submitting state both re-render the card; the transcript
        // only re-reads this coordinator on the change notification.
        notifyChanged()
        defer {
            endSubmitting(proposalID, conversationID: presentation.sourceConversationID)
            notifyChanged()
        }

        do {
            // Re-read GitHub rather than trusting the snapshot: the pull request can merge, or the
            // draft review can change, between proposing and confirming.
            let detail = try await pullRequestsService.fetchDetail(presentation.identifier)
            guard validateSubmission(presentation: presentation, event: event, detail: detail) else { return false }
            try await submit(
                presentation: presentation,
                event: event,
                body: presentation.body ?? "",
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
            body: presentation.body ?? "",
            in: modelContext,
            at: now()
        )
        notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: self)
        reload()
        return true
    }

    @discardableResult
    func reject(proposalID: String) -> Bool {
        guard !isSubmitting(proposalID: proposalID),
              refreshSavedProposal(proposalID: proposalID),
              let presentation = presentations[proposalID] else { return false }
        guard clearProposal(proposalID: proposalID, conversationID: presentation.sourceConversationID) else {
            errorMessages[proposalID] = "Alveary could not dismiss this review proposal."
            notifyChanged()
            return false
        }
        PullRequestReviewProposalOutcomeRecorder.record(
            proposalID: proposalID,
            sourceConversationID: presentation.sourceConversationID,
            outcome: .rejected,
            body: presentation.body ?? "",
            in: modelContext,
            at: now()
        )
        notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: self)
        reload()
        return true
    }

    /// Saves locally without invalidating the diff or regrouping transcript records.
    @discardableResult
    func updateBody(proposalID: String, body: String) -> Bool {
        guard !isSubmitting(proposalID: proposalID),
              let presentation = presentations[proposalID] else { return false }
        guard let updated = rewriteProposal(presentation: presentation, { $0.replacingBody(body) }) else {
            errorMessages[proposalID] = "Alveary could not save this review comment."
            notifyChanged()
            return false
        }
        apply(updated, for: presentation)
        PullRequestReviewProposalEditState.recordEdit(proposalID: proposalID)
        errorMessages[proposalID] = nil
        notifySavedBodyChanged(proposalID: proposalID)
        return true
    }

    /// Removes a staged comment by presentation index, rewriting the envelope and pruning the
    /// loaded preview locally; staged comments do not exist on GitHub until confirmation.
    @discardableResult
    func removeStagedComment(proposalID: String, at index: Int) -> Bool {
        guard submittingConversationIDsByProposalID[proposalID] == nil,
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
        PullRequestReviewProposalEditState.recordEdit(proposalID: proposalID)
        if case .loaded(let preview)? = previews[proposalID] {
            previews[proposalID] = .loaded(Self.preview(preview, removingProposedCommentAt: index))
        }
        errorMessages[proposalID] = nil
        // Card-only: nothing resolved and no transcript record moved, so this must not pay the
        // lifecycle notification's chat-item rebuild.
        notifyChanged()
        return true
    }

    /// Stages a pane-composed comment locally until the proposal is confirmed.
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
        guard submittingConversationIDsByProposalID[proposalID] == nil,
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
        PullRequestReviewProposalEditState.recordEdit(proposalID: proposalID)
        // Unlike a removal, this cannot narrow the loaded preview in place: removal only subtracts,
        // while an addition may need a file or hunk the preview deliberately dropped. Reloaded at
        // once rather than on the card's next render — the user is composing in the pane, so the
        // round trip is unseen, and one click is nothing for `scheduleRemoteReload` to coalesce.
        invalidatePreview(proposalID: proposalID)
        ensurePreview(proposalID: proposalID)
        errorMessages[proposalID] = nil
        notifyChanged()
        return true
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
        guard selectedEvent(forProposalID: proposalID) != event else {
            return
        }
        selectedEvents[proposalID] = event
        PullRequestReviewProposalEditState.recordEdit(proposalID: proposalID)
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
            pendingCommentCount: pendingCommentCount(proposalID: proposalID) + presentation.comments.count
        )
    }

    /// Refreshes only one saved envelope, retaining its diff and the other rows' state.
    @discardableResult
    func refreshSavedProposal(proposalID: String) -> Bool {
        guard let presentation = presentations[proposalID],
              let record = savedProposal(for: presentation) else {
            errorMessages[proposalID] = "This review proposal is no longer available."
            notifyChanged()
            return false
        }
        apply(record, for: presentation)
        return true
    }

    /// Mirrors app-wide activity into observable state so another window's footer disables too.
    func refreshSharedSubmissionState() {
        let submitting = Set(presentations.keys.filter {
            PullRequestReviewProposalEditState.current(proposalID: $0)?.isSubmitting == true
        })
        if sharedSubmittingProposalIDs != submitting { sharedSubmittingProposalIDs = submitting }
    }

    var service: any PullRequestsService {
        pullRequestsService
    }
}

private extension PullRequestReviewProposalCoordinator {
    func validateSubmission(
        presentation: PullRequestReviewProposalPresentation,
        event: PullRequestReviewEvent,
        detail: PullRequestDetail
    ) -> Bool {
        if detail.viewerLogin == detail.authorLogin, event == .approve || event == .requestChanges {
            errorMessages[presentation.id] = "Only Comment is available on your own pull request."
            return false
        }
        var draft = PendingReviewDraft()
        draft.overallComment = presentation.body ?? ""
        guard PullRequestsViewModel.canSubmitReview(
            event: event, draft: draft,
            pendingCommentCount: detail.pendingCommentCount + presentation.comments.count
        ) else {
            errorMessages[presentation.id] = "This review needs a top-level comment or a different review action."
            return false
        }
        return true
    }

    func pendingCommentCount(proposalID: String) -> Int {
        if case .loaded(let preview) = previews[proposalID] { return preview.pendingCommentCount }
        return presentations[proposalID]?.pendingCommentCount ?? 0
    }

    /// Republishes an edited envelope. A nil re-derivation would clear the entry, dropping a
    /// proposal that is still pending; the envelope just round-tripped through a decode, so it
    /// cannot happen, and keeping the old presentation is the safe direction.
    func apply(
        _ updated: PullRequestReviewProposalRecord,
        for presentation: PullRequestReviewProposalPresentation
    ) {
        guard let conversation = modelContext.resolveConversation(conversationID: presentation.sourceConversationID),
              let refreshed = Self.presentation(
            for: updated,
            conversation: conversation
        ) else {
            return
        }
        presentations[presentation.id] = refreshed
    }

    static func message(for error: Error) -> String {
        guard let serviceError = error as? PullRequestsServiceError else {
            return error.localizedDescription
        }
        return serviceError.errorDescription ?? serviceError.localizedDescription
    }

    func observeChanges() {
        bodyChangeTask = makeBodyChangeObservationTask()
        let notifications = notificationCenter.notifications(named: .pullRequestReviewProposalsChanged)
        observationTask = Task { @MainActor [weak self] in
            for await _ in notifications {
                guard !Task.isCancelled else {
                    return
                }
                self?.reload()
            }
        }
        let remoteChanges = notificationCenter.notifications(named: .pullRequestChangedOnGitHub)
        remoteChangeTask = Task { @MainActor [weak self] in
            for await notification in remoteChanges {
                guard !Task.isCancelled else {
                    return
                }
                self?.invalidatePreviews(for: notification)
            }
        }
    }
}
