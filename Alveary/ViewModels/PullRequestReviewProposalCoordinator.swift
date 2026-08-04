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
    let pendingCommentCount: Int
    let createdAt: Date

    var displayKey: String {
        identifier.displayKey
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
    @discardableResult
    func confirm(
        proposalID: String,
        event: PullRequestReviewEvent
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
            let body = presentation.body ?? ""
            if let reviewNodeID = detail.pendingReviewNodeID {
                // Finish the existing draft rather than opening a second review beside it.
                try await pullRequestsService.submitPendingReview(
                    reviewNodeID: reviewNodeID,
                    event: event,
                    body: body
                )
            } else {
                try await pullRequestsService.submitReview(
                    presentation.identifier,
                    event: event,
                    body: body
                )
            }
        } catch {
            errorMessages[proposalID] = Self.message(for: error)
            return false
        }

        // Submitted. From here a failure may leave the card unresolved, never wrongly resolved.
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
        previewTasks[proposalID] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            previews[proposalID] = .loading
            let state = await loadPreview(for: presentation)
            previewTasks[proposalID] = nil
            guard !Task.isCancelled, presentations[proposalID] != nil else {
                return
            }
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
        return PullRequestsViewModel.canSubmitReview(
            event: event,
            draft: draft,
            pendingCommentCount: presentation.pendingCommentCount
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
            pendingCommentCount: record.pendingCommentCountSnapshot,
            createdAt: record.createdAt
        )
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
