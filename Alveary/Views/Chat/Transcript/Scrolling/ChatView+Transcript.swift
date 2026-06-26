import Foundation
import SwiftUI

let transcriptTopInset: CGFloat = 20
let transcriptBottomInset: CGFloat = 14
private let transcriptProgrammaticScrollTimeout: TimeInterval = 0.4

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
    @State private var pendingProgrammaticScrollMode: PendingProgrammaticScrollMode?
    @State private var pendingProgrammaticScrollTimeoutToken: UUID?
    @State var latestMetrics: ChatTranscriptScrollMetrics?
    @State var appKitScrollToBottomRequest = 0
    @State var transcriptContentWidth: CGFloat = 0
    @State var expandedTranscriptRows: Set<String> = []
    @State var appKitToolApprovalSelectionsBySessionID: [String: ToolApprovalSelection] = [:]

    var shouldShowTransientInterruptedNote: Bool {
        !viewModel.state.grouper.items.hasInterruptedNoteAfterLatestUserMessage
    }

    var body: some View {
        appKitTranscriptSurface()
        .onChange(of: events.count) {
            if !viewModel.turnState.isActive {
                viewModel.rebuildChatItemsIfNeeded(from: events)
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
        .onChange(of: viewModel.streamingText) {
            guard isFollowing else {
                return
            }

            let now = Date()
            if now.timeIntervalSince(lastScrollTime) >= 0.1 {
                scrollToBottom(at: now)
            }
        }
        .onChange(of: viewModel.thoughtText) {
            guard isFollowing else {
                return
            }

            let now = Date()
            if now.timeIntervalSince(lastScrollTime) >= 0.1 {
                scrollToBottom(at: now)
            }
        }
        .onChange(of: viewModel.completedThoughtText) {
            guard isFollowing else {
                return
            }

            let now = Date()
            if now.timeIntervalSince(lastScrollTime) >= 0.1 {
                scrollToBottom(at: now)
            }
        }
        .onAppear {
            viewModel.rebuildChatItemsIfNeeded(from: events)
            scrollToBottom(forceFollow: true)
        }
        .onChange(of: viewModel.turnState.isActive) { _, isActive in
            if isActive {
                isFollowing = true
                scrollToBottom(forceFollow: true)
            } else {
                viewModel.rebuildChatItemsIfNeeded(from: events, forceFullRebuild: true)
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

        return lastEvent.type == "message" && lastEvent.role == "user"
    }

}
