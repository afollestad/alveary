import Foundation
import SwiftUI

let transcriptTopInset: CGFloat = 20
let transcriptBottomInset: CGFloat = 14
private let transcriptProgrammaticScrollTimeout: TimeInterval = 0.4
/// Minimum gap between follow-scrolls while text streams in, so each delta does not issue its own scroll.
private let transcriptStreamingScrollInterval: TimeInterval = 0.1

private enum ScrollToBottomRetries {
    /// Immediate scroll only. Container-change preserve-follow reissues via
    /// `handleScrollMetricsChange`, so deferred retries would be redundant.
    case single
    /// Immediate + next-runloop + 150ms retries for async row/layout settling.
    case triple
}

struct ChatTranscriptView: View {
    let viewModel: ConversationViewModel
    let appState: AppState
    let events: [ConversationEventRecord]
    let workingDirectory: String?

    @Binding var lastScrollTime: Date
    @Binding var isFollowing: Bool
    @Binding var scrollToBottomRequest: Int

    @Environment(\.transcriptTypography) var transcriptTypography
    // Scheduling proposals are confirmed inside transcript widgets; both are optional so
    // snapshot hosts can render the transcript without the scheduling stack.
    @Environment(ScheduledTaskProposalQueueCoordinator.self) var scheduledTaskProposalQueueCoordinator: ScheduledTaskProposalQueueCoordinator?
    @Environment(ScheduledTasksViewModel.self) var scheduledTasksViewModel: ScheduledTasksViewModel?
    /// Review submissions are confirmed inside transcript widgets too; optional for the same
    /// reason, so a snapshot host can render without the pull request stack.
    @Environment(PullRequestReviewProposalCoordinator.self) var pullRequestReviewProposalCoordinator: PullRequestReviewProposalCoordinator?
    @State private var pendingProgrammaticScrollMode: PendingProgrammaticScrollMode?
    @State private var pendingProgrammaticScrollTimeoutToken: UUID?
    @State var latestMetrics: ChatTranscriptScrollMetrics?
    @State var appKitScrollToBottomRequest = 0
    @State var transcriptContentWidth: CGFloat = 0
    @State var expandedTranscriptRows: Set<String> = []
    @State var appKitToolApprovalSelectionsBySessionID: [String: ToolApprovalSelection] = [:]
    @State var appKitPullRequestPromptSelections: [String: PullRequestLinkPromptSelection] = [:]
    @State var scheduledProposalRevision = 0
    @State var reviewProposalRevision = 0

    var shouldShowTransientInterruptedNote: Bool {
        !viewModel.state.grouper.items.hasInterruptedNoteAfterLatestUserMessage
    }

    /// Observers are grouped into wrapper functions rather than chained inline.
    ///
    /// Swift type-checks an expression as a whole, so eleven `onChange`/`task`/`overlay` modifiers
    /// on one chain resolved their generic overloads together and pushed this body toward the
    /// compiler's per-expression time budget — a wall-clock limit, so it fails on slow machines
    /// while building clean on fast ones. Keep new observers inside a group.
    var body: some View {
        transcriptScrollToLatestOverlay(
            transcriptLifecycleObservers(
                transcriptStreamingObservers(
                    transcriptContentObservers(appKitTranscriptSurface())
                )
            )
        )
    }

    private func transcriptContentObservers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: events.count) {
                if !viewModel.turnState.isActive {
                    viewModel.rebuildChatItemsFromConversationRecords(fallbackEvents: events)
                }
                if shouldForceBottomScroll(for: events) {
                    scrollToBottom(forceFollow: true)
                } else if isFollowing {
                    scrollToBottom()
                }
            }
            .onChange(of: viewModel.messageQueue.pending.count) { oldCount, newCount in
                guard newCount > oldCount else {
                    return
                }
                scrollToBottom(forceFollow: true)
            }
            .onChange(of: viewModel.state.grouper.items.last?.id) {
                guard isFollowing else {
                    return
                }
                scrollToBottom(forceFollow: true)
            }
    }

    private func transcriptStreamingObservers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: viewModel.streamingText) {
                scrollToBottomForStreamingGrowth()
            }
            .onChange(of: viewModel.thoughtText) {
                scrollToBottomForStreamingGrowth()
            }
            .onChange(of: viewModel.completedThoughtText) {
                scrollToBottomForStreamingGrowth()
            }
    }

    private func transcriptLifecycleObservers<Content: View>(_ content: Content) -> some View {
        content
            // Proposal confirmation happens outside the provider turn, so the widget's
            // live state needs its own invalidation signal.
            // Editing or pausing a task elsewhere changes what the list tool's row renders.
            .onReceive(NotificationCenter.default.publisher(for: .scheduledTasksChanged)) { _ in
                scheduledProposalRevision &+= 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduledTaskProposalsChanged)) { _ in
                // The widget's live confirmation state is closure-resolved, so bumping the
                // revision is enough to re-render it. Regrouping is only for picking up an
                // outcome marker, and must stay off the active turn — a proposal opens
                // mid-turn, and full rebuilds there starve streaming and composer work.
                scheduledProposalRevision &+= 1
                guard !viewModel.turnState.isActive else {
                    return
                }
                viewModel.rebuildChatItemsFromConversationRecords(fallbackEvents: events)
            }
            .onReceive(NotificationCenter.default.publisher(for: .pullRequestReviewProposalsChanged)) { _ in
                // Same shape as the scheduling proposal above: the card's live state is
                // closure-resolved, and the rebuild is only for its outcome marker.
                reviewProposalRevision &+= 1
                guard !viewModel.turnState.isActive else {
                    return
                }
                viewModel.rebuildChatItemsFromConversationRecords(fallbackEvents: events)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .reviewProposalCardStateChanged)
            ) { _ in
                // Verdict picks, the loading diff preview, and submitting transitions re-render
                // the card but change no persisted records, so they skip the rebuild.
                reviewProposalRevision &+= 1
            }
            .onAppear {
                viewModel.rebuildChatItemsFromConversationRecords(fallbackEvents: events)
                scrollToBottom(forceFollow: true)
            }
            .onChange(of: viewModel.turnState.isActive) { _, isActive in
                if isActive {
                    isFollowing = true
                    scrollToBottom(forceFollow: true)
                } else {
                    // Background services can insert transcript records before `@Query` publishes
                    // its next snapshot. Re-fetch here so a stale view snapshot cannot erase them;
                    // if that fetch fails, preserve the live grouper instead of forcing stale rows.
                    viewModel.rebuildChatItemsFromConversationRecords(forceFullRebuild: true)
                    // `forceFullRebuild` can swap transient rows for persisted rows and publish
                    // a sequence of AppKit document-height changes, so a fresh jump-to-latest
                    // scroll lands against the settled baseline and keeps reissuing for any
                    // remaining content-size shifts.
                    if isFollowing {
                        scrollToBottom(forceFollow: true)
                    }
                }
            }
            .onChange(of: scrollToBottomRequest) { _, _ in
                scrollToBottom(forceFollow: true)
            }
            .task(id: appKitApprovalSelectionLoadID) {
                await loadAppKitApprovalSelectionsIfNeeded()
            }
    }

    private func transcriptScrollToLatestOverlay<Content: View>(_ content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ScrollToLatestButton {
                    scrollToBottom(forceFollow: true)
                }
                .opacity(isFollowing ? 0 : 1)
                .allowsHitTesting(!isFollowing)
                .accessibilityHidden(isFollowing)
                .padding(.bottom, 12)
                .animation(.easeInOut(duration: 0.18), value: isFollowing)
            }
    }

    /// Streamed text, live thinking, and completed thinking all grow the transcript the same way,
    /// so they share one throttled follow-scroll instead of three identical closures.
    private func scrollToBottomForStreamingGrowth() {
        guard isFollowing else {
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastScrollTime) >= transcriptStreamingScrollInterval {
            scrollToBottom(at: now)
        }
    }
}
extension ChatTranscriptView {
    func handleScrollMetricsChange(
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics
    ) {
        latestMetrics = newMetrics
        if let pendingProgrammaticScrollMode {
            let action = ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: pendingProgrammaticScrollMode,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
            switch action {
            case .settleFollowingAndClear:
                isFollowing = true
                self.pendingProgrammaticScrollMode = nil
            case .followWithoutClearing:
                isFollowing = true
            case .cancelled:
                self.pendingProgrammaticScrollMode = nil
                isFollowing = false
            case .reissue:
                issueImmediateBottomScroll()
                schedulePendingProgrammaticScrollTimeout()
            case .noop:
                break
            }
            return
        }
        if ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
            oldMetrics: oldMetrics,
            newMetrics: newMetrics
        ) {
            isFollowing = true
            scrollToBottom(retries: .single)
            return
        }
        isFollowing = ChatTranscriptScrollBehavior.nextFollowingState(
            currentIsFollowing: isFollowing,
            oldMetrics: oldMetrics,
            newMetrics: newMetrics
        )
    }

    func cancelPendingScrollForUserLocalHeightChange() {
        pendingProgrammaticScrollMode = nil
        pendingProgrammaticScrollTimeoutToken = nil
    }
}
private extension ChatTranscriptView {
    func issueImmediateBottomScroll() {
        appKitScrollToBottomRequest += 1
    }

    func scrollToBottom(
        forceFollow: Bool = false,
        retries: ScrollToBottomRetries = .triple,
        at time: Date = Date()
    ) {
        pendingProgrammaticScrollMode = forceFollow ? .jumpToLatest : .preserveFollow
        if forceFollow {
            isFollowing = true
        }
        lastScrollTime = time
        issueImmediateBottomScroll()
        if retries == .triple {
            // Re-issue after layout settles so AppKit row height callbacks and
            // footer chrome changes still pin the transcript at the bottom.
            DispatchQueue.main.async {
                guard pendingProgrammaticScrollMode != nil else {
                    return
                }
                issueImmediateBottomScroll()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard pendingProgrammaticScrollMode != nil else {
                    return
                }
                issueImmediateBottomScroll()
            }
        }
        schedulePendingProgrammaticScrollTimeout()
    }

    /// Schedule — or reschedule — the watchdog that clears a pending programmatic
    /// scroll after `transcriptProgrammaticScrollTimeout` of no further progress.
    /// Each call stamps a fresh token and only fires if the token is still current
    /// when the deadline lands, so a reissued `scrollTo` (from the jump-to-latest /
    /// preserve-follow branches in `handleScrollMetricsChange`) pushes the deadline
    /// out while AppKit row heights settle.
    func schedulePendingProgrammaticScrollTimeout() {
        let token = UUID()
        pendingProgrammaticScrollTimeoutToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + transcriptProgrammaticScrollTimeout) {
            guard pendingProgrammaticScrollTimeoutToken == token else {
                return
            }
            pendingProgrammaticScrollTimeoutToken = nil
            guard pendingProgrammaticScrollMode != nil else {
                return
            }

            // Clear the pending mode. Do NOT overwrite `isFollowing` here:
            //   - It was set to `true` at `scrollToBottom(forceFollow:)` kickoff.
            //   - `.cancelled` is the only path that flips it to `false` during the
            //     pending window, and that clears `pendingProgrammaticScrollMode`
            //     early, so we wouldn't have made it here.
            //   - A raw `isFollowing = latestMetrics?.isNearBottom ?? false` fallback
            //     caused the jump-to-latest button to flash briefly on app launch to
            //     a preselected thread: AppKit metrics had not been forwarded yet
            //     when the watchdog landed (`latestMetrics` was nil → `?? false`),
            //     so `isFollowing` flipped to `false` for one frame until a later
            //     metrics tick restored it via `nextFollowingState`.
            pendingProgrammaticScrollMode = nil
        }
    }

    func shouldForceBottomScroll(for events: [ConversationEventRecord]) -> Bool {
        guard let lastEvent = events.last else {
            return false
        }

        return lastEvent.type == ConversationEventRecord.messageType && lastEvent.role == ConversationEventRecord.userRole
    }

}
