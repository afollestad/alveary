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
    @ObservationIgnored private let modelContext: ModelContext
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
    ///
    /// Internal rather than `private(set)` because `+Submission.swift`'s `beginSubmitting` and
    /// `endSubmitting` own both of its transitions; Swift cannot scope a setter to two files, and
    /// pairing them there is what keeps this map and the app-scoped announcement from drifting.
    /// Nothing outside this type's own files may write it.
    ///
    /// It stores the conversation rather than re-deriving it from `presentations`, because
    /// `reload()` can empty that dictionary mid-flight — another window rejecting the proposal, an
    /// archive clearing the envelope, a thread delete announcing — while this submit is still
    /// inside GitHub. A derived read would drop the working ring there while the archive guard
    /// still refuses the thread.
    var submittingConversationIDsByProposalID: [String: String] = [:]

    /// Every conversation inside `confirm`'s network span. Thread status reads this to raise the
    /// working ring over the waiting dot for exactly that long; see `ConversationWorkActivity`.
    var submittingSourceConversationIDs: Set<String> {
        Set(submittingConversationIDsByProposalID.values)
    }

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
    }

    func errorMessage(forProposalID proposalID: String) -> String? {
        errorMessages[proposalID]
    }

    func reload() {
        var loaded: [String: PullRequestReviewProposalPresentation] = [:]
        guard let conversations = try? modelContext.fetch(
            PullRequestReviewProposalLookup.proposalHoldingConversations
        ) else {
            return
        }
        for owner in PullRequestReviewProposalLookup.proposals(in: conversations) {
            guard let presentation = Self.presentation(
                for: owner.record,
                conversationID: owner.conversationID
            ) else {
                continue
            }
            loaded[owner.record.id] = presentation
        }
        presentations = loaded
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
        guard submittingConversationIDsByProposalID[proposalID] == nil,
              let presentation = presentations[proposalID] else {
            return false
        }
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
        guard submittingConversationIDsByProposalID[proposalID] == nil,
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
