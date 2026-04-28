import AppKit
import Foundation
import SwiftData
import SwiftUI

private let transcriptTopInset: CGFloat = 20
private let transcriptBottomInset: CGFloat = 14
private let transcriptProgrammaticScrollTimeout: TimeInterval = 0.4

/// Distance from bottom at which the `jumpToLatest` path switches from a
/// single `scrollTo(edge: .bottom)` (fast, for short distances) to a
/// progressive stepped scroll (slower, gives `LazyVStack` frames to
/// materialize rows as the viewport passes through).
private let transcriptProgressiveScrollThreshold: CGFloat = 400

/// Per-step offset jump for the progressive scroll. Sized below a typical
/// viewport height so each step materializes a fresh slice of content.
private let transcriptProgressiveScrollStep: CGFloat = 300

/// Delay between progressive scroll steps. Long enough for a `LazyVStack`
/// render pass to materialize the current visible range before we advance.
private let transcriptProgressiveScrollStepDelay: TimeInterval = 0.04

/// Safety cap on the number of progressive steps for a single scroll
/// sequence. With a 300pt step this covers ~9000pt of content (far beyond
/// any realistic transcript), but guarantees the recursion terminates even
/// if content keeps growing faster than we step through it or the scroll
/// refuses to advance. Once the cap is hit we finish with a single
/// `scrollTo(edge: .bottom)` and let the reissue predicates converge.
private let transcriptProgressiveScrollMaxSteps: Int = 30

private enum ScrollToBottomRetries {
    /// Immediate `scrollTo` only. Used by the container-change preserve-follow path
    /// where continued layout shifts are re-issued via `shouldReissuePendingPreserveFollow`
    /// on subsequent `onScrollGeometryChange` frames, so the deferred retries would be
    /// redundant.
    case single
    /// Immediate + next-runloop + 150ms retries. Used for `jumpToLatest` (thread entry
    /// with async composer layout shifts) and for content-growth preserve-follow paths
    /// (new-message / streaming-chunk onChange handlers) where async bubble layout may
    /// shift the bottom after the initial scrollTo lands.
    case triple
}

struct ChatTranscriptView: View {
    let viewModel: ConversationViewModel
    let events: [ConversationEventRecord]
    let workingDirectory: String?

    @Binding var lastScrollTime: Date
    @Binding var isFollowing: Bool
    @Binding var scrollToBottomRequest: Int

    @State private var pendingProgrammaticScrollMode: PendingProgrammaticScrollMode?
    @State private var pendingProgrammaticScrollTimeoutToken: UUID?
    @State var latestMetrics: ChatTranscriptScrollMetrics?
    @State var scrollPosition = ScrollPosition()
    @State private var transcriptContentWidth: CGFloat = 0
    @State var expandedTranscriptRows: Set<String> = []
    @State var topLevelToolHeaderFrames: [String: CGRect] = [:]
    @State var pendingExpandedHeaderRevealID: String?
    @State var pendingExpandedHeaderRevealToken: UUID?
    @State var expandedHeaderRevealScrollToken: UUID?
    @State private var isProgressiveScrolling = false

    private var shouldShowTransientInterruptedNote: Bool {
        !viewModel.state.grouper.items.hasInterruptedNoteAfterLatestUserMessage
    }

    var body: some View {
        let horizontalInset = transcriptScrollLeadingInset + transcriptScrollTrailingInset
        let toolRowWidth: CGFloat? = transcriptContentWidth > horizontalInset ? transcriptContentWidth - horizontalInset : nil
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.state.grouper.items) { item in
                    switch item {
                    case .userMessage(let id, let text):
                        UserBubble(
                            id: id,
                            text: text,
                            showsRetry: viewModel.state.retryableFailedMessageIDs.contains(id),
                            onRetry: retryAction(
                                for: id,
                                isRetryable: viewModel.state.retryableFailedMessageIDs.contains(id)
                            )
                        )
                    case .assistantMessage(let id, let text):
                        AssistantBubble(id: id, markdown: text)
                    case .toolGroup(let id, let tools):
                        ToolGroupBlock(
                            tools: tools,
                            isExpanded: transcriptRowExpansionBinding(for: id),
                            headerFrameID: id
                        )
                            .frame(width: toolRowWidth, alignment: .leading)
                    case .standaloneTool(let id, let tool):
                        StandaloneToolRow(
                            tool: tool,
                            isExpanded: transcriptRowExpansionBinding(for: id),
                            headerFrameID: id
                        )
                            .frame(width: toolRowWidth, alignment: .leading)
                    case .subAgentBlock(let id, let agents):
                        SubAgentBlock(
                            agents: agents,
                            isExpanded: transcriptRowExpansionBinding(for: id),
                            headerFrameID: id
                        )
                            .frame(width: toolRowWidth, alignment: .leading)
                    case .taskListBlock(_, let tasks):
                        TaskListBlock(tasks: tasks)
                    case .promptBlock(_, let prompt):
                        PromptBlock(prompt: prompt, isBusy: !viewModel.canSubmitPromptAnswer(promptId: prompt.id)) { answers in
                            do {
                                return try await viewModel.answerPrompt(promptId: prompt.id, answers: answers)
                            } catch {
                                if viewModel.lastTurnError == nil {
                                    viewModel.lastTurnError = "Failed to send answer: \(error.localizedDescription)"
                                }
                                return nil
                            }
                        }
                    case .toolApproval(_, let approval, let status):
                        toolApprovalBlock(approval, persistedStatus: status)
                    case .toolApprovalBatch(_, let approvals, let status):
                        toolApprovalBlock(approvals, persistedStatus: status)
                    case .error(_, let message):
                        ErrorBanner(message: message)
                    case .centeredNote(_, let kind):
                        CenteredTranscriptNote(kind: kind)
                    }
                }

                if viewModel.turnState.isActive,
                   viewModel.streamingText == nil {
                    ActiveTurnThinkingIndicator()
                }

                if let streamingText = viewModel.streamingText,
                   !viewModel.state.isHandingOffSession {
                    StreamingBubble(text: streamingText)
                        .id("streaming")
                }

                if viewModel.state.lastTurnInterrupted,
                   !viewModel.turnState.isActive,
                   shouldShowTransientInterruptedNote {
                    CenteredTranscriptNote(kind: .interrupted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, transcriptScrollLeadingInset)
            .padding(.trailing, transcriptScrollTrailingInset)
            .padding(.top, transcriptTopInset)
            .padding(.bottom, transcriptBottomInset)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newValue in
                transcriptContentWidth = newValue
            }
            .onPreferenceChange(TranscriptToolHeaderFramePreferenceKey.self) { frames in
                topLevelToolHeaderFrames = frames
            }
            // `.scrollTargetLayout()` is intentionally omitted. That modifier
            // marks the stack's children as scroll targets, which causes
            // `.scrollPosition` and `.defaultScrollAnchor` to anchor on "the
            // last scroll target's bottom = viewport bottom". That alignment
            // ignores the outer `.padding(.bottom, ...)` (outside the targets)
            // and silently drifts offsetY up by 14pt a few frames after a
            // scroll lands — rendering the transcript with the bottom padding
            // partially cut off. We don't use `scrollTargetBehavior(.viewAligned)`
            // so `.scrollTargetLayout()` provides no benefit here; removing it
            // eliminates the drift. Don't add it back.
        }
        .coordinateSpace(name: transcriptScrollCoordinateSpace)
        .environment(\.transcriptBubbleMaxWidth, adaptiveTranscriptBubbleMaxWidth(for: transcriptContentWidth))
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(isFollowing ? .bottom : nil, for: .sizeChanges)
        .scrollPosition($scrollPosition, anchor: .bottom)
        .onScrollGeometryChange(for: ChatTranscriptScrollMetrics.self) { geometry in
            ChatTranscriptScrollMetrics(
                offsetY: geometry.contentOffset.y,
                contentHeight: geometry.contentSize.height,
                containerHeight: geometry.containerSize.height
            )
        } action: { oldMetrics, newMetrics in
            latestMetrics = newMetrics

            // Expansion reveal owns this brief geometry window; do not reinterpret it as follow-mode intent.
            if expandedHeaderRevealScrollToken != nil {
                return
            }

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
                    // Suppress reissue's `scrollTo(edge: .bottom)` while the
                    // progressive-scroll scheduler is running. Its stepped
                    // `scrollTo(y:)` calls and the reissue's edge-scroll race
                    // each other and prevent `LazyVStack` from materializing
                    // rows at the intermediate viewport positions. Still
                    // refresh the watchdog so pending stays alive through the
                    // progressive sequence.
                    if !isProgressiveScrolling {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
                    // Refresh the timeout so slow-materializing `LazyVStack` content
                    // (large threads on entry) can keep pinning to the growing bottom
                    // instead of timing out and leaving the viewport above the true
                    // content end.
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
                // Must re-pin after the rebuild even though `onChange(of: events.count)` also
                // fires an `scrollToBottom()` at turn end — that earlier scroll gets neutered:
                // the `forceFullRebuild` regenerates unstable item identities (e.g. tool-group
                // UUIDs) and the streaming bubble (`id("streaming")`) unmounts as `streamingText`
                // goes nil, producing geometry churn that either trips `shouldCancelProgrammaticScroll`
                // (offset momentarily moves away from bottom) or transiently hits `isAtBottom`,
                // either of which clears `pendingProgrammaticScrollMode` and disarms the
                // remaining triple-fire retries. A fresh scroll after the rebuild lands against
                // a settled baseline. Use `forceFollow: true` (jumpToLatest) so the wider
                // `shouldReissuePendingJumpToLatest` predicate tracks the rebuild's content-size
                // shifts — preserveFollow's container-only reissue would miss them.
                if isFollowing {
                    scrollToBottom(forceFollow: true)
                }
            }
        }
        .onChange(of: scrollToBottomRequest) { _, _ in
            scrollToBottom(forceFollow: true)
        }
        .overlay(alignment: .bottom) {
            if !isFollowing {
                ScrollToLatestButton {
                    scrollToBottom(forceFollow: true)
                }
                .transition(.opacity)
                .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isFollowing)
        .environment(\.openURL, OpenURLAction { url in
            let resolved = Self.resolveMarkdownLinkURL(url, workingDirectory: workingDirectory)
            NSWorkspace.shared.open(resolved)
            return .handled
        })
    }

}
private extension ChatTranscriptView {
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

        // Progressive warmup: if `forceFollow` and we're far from bottom,
        // issue intermediate scrollTo(y:) calls so `LazyVStack` materializes
        // rows as the viewport passes through them. SwiftUI's scrollTo(edge:)
        // jumps the viewport in a single frame — bottom rows may never
        // materialize, leaving the transcript blank until the user drags.
        // Stepping through intermediate y positions mimics a user scroll,
        // giving the stack multiple rendering opportunities to realize rows.
        let usingProgressiveScroll = forceFollow
            && !isProgressiveScrolling
            && (latestMetrics?.distanceFromBottom ?? 0) > transcriptProgressiveScrollThreshold
            && (latestMetrics?.contentHeight ?? 0) > (latestMetrics?.containerHeight ?? 0)
        if usingProgressiveScroll, let metrics = latestMetrics {
            // `!isProgressiveScrolling` guard above means rapid repeat
            // forceFollow calls (double-tap jump-to-latest, send-while-mid-progressive)
            // don't start a second concurrent chain. The in-flight chain
            // reads `latestMetrics` on each step so it adapts to any content
            // growth that happened after it started — redundant chains would
            // just race each other's `scrollTo(y:)` calls.
            isProgressiveScrolling = true
            performProgressiveScrollToBottom(
                fromOffsetY: metrics.offsetY,
                stepsRemaining: transcriptProgressiveScrollMaxSteps
            )
        } else if !isProgressiveScrolling {
            // Skip edge-scroll if progressive is already driving — it owns
            // the scroll flow and its stepped calls would race with this one.
            scrollPosition.scrollTo(edge: .bottom)
        }

        // Skip the retry ladder when the progressive path is driving — its
        // own stepped scheduler replaces it. Otherwise the triple-retry
        // `scrollTo(edge: .bottom)` calls race with the progressive steps
        // and the viewport ends up jumping between targets. `isProgressiveScrolling`
        // (not just `usingProgressiveScroll`) is the right guard: a repeat
        // call during an in-flight chain has `usingProgressiveScroll == false`
        // (we skipped starting a second chain above), but the existing chain
        // is still driving the scroll — retries here would still race it.
        if retries == .triple, !isProgressiveScrolling {
            // Re-issue the bound scroll position after layout settles so lazy rows
            // and footer chrome changes still pin the transcript at the bottom.
            DispatchQueue.main.async {
                guard pendingProgrammaticScrollMode != nil else {
                    return
                }
                scrollPosition.scrollTo(edge: .bottom)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard pendingProgrammaticScrollMode != nil else {
                    return
                }
                scrollPosition.scrollTo(edge: .bottom)
            }
        }

        schedulePendingProgrammaticScrollTimeout()
    }

    /// Step through intermediate y positions toward the bottom. Each step
    /// gives `LazyVStack` a render pass to materialize rows in the current
    /// visible range. Without this, a single `scrollTo(edge: .bottom)` from
    /// far-away lands on rows `LazyVStack` never materialized and the
    /// viewport renders blank until the user drags.
    func performProgressiveScrollToBottom(fromOffsetY startOffsetY: CGFloat, stepsRemaining: Int) {
        let nextOffsetY = startOffsetY + transcriptProgressiveScrollStep
        scrollPosition.scrollTo(y: nextOffsetY)
        // Refresh the watchdog on every step. The reissue predicate
        // (`shouldReissuePendingJumpToLatest`) only fires on container-shrink /
        // content-grow ticks, and the `.noop` path doesn't refresh — so during
        // a progressive sequence where content has already materialized enough
        // for `LazyVStack` to stop growing its reported contentHeight, the
        // watchdog would fire mid-sequence (400ms after the last reissue),
        // clear `pendingProgrammaticScrollMode`, and the next step's
        // `guard pendingProgrammaticScrollMode != nil` would exit the chain
        // partway through — leaving the transcript stranded mid-scroll.
        schedulePendingProgrammaticScrollTimeout()

        DispatchQueue.main.asyncAfter(deadline: .now() + transcriptProgressiveScrollStepDelay) {
            guard pendingProgrammaticScrollMode != nil else {
                isProgressiveScrolling = false
                return
            }
            guard let metrics = latestMetrics else {
                isProgressiveScrolling = false
                scrollPosition.scrollTo(edge: .bottom)
                return
            }
            let withinFinalHop = metrics.distanceFromBottom <= transcriptProgressiveScrollStep
            let outOfSteps = stepsRemaining <= 1
            if withinFinalHop || outOfSteps {
                // Close enough, or safety cap hit — final hop to the edge so
                // the reissue predicates take over to converge to the exact
                // bottom. The step cap guarantees termination even if content
                // keeps growing faster than we step or the scroll refuses to
                // advance.
                isProgressiveScrolling = false
                scrollPosition.scrollTo(edge: .bottom)
            } else {
                performProgressiveScrollToBottom(
                    fromOffsetY: metrics.offsetY,
                    stepsRemaining: stepsRemaining - 1
                )
            }
        }
    }

    /// Schedule — or reschedule — the watchdog that clears a pending programmatic
    /// scroll after `transcriptProgrammaticScrollTimeout` of no further progress.
    /// Each call stamps a fresh token and only fires if the token is still current
    /// when the deadline lands, so a reissued `scrollTo` (from the jump-to-latest /
    /// preserve-follow branches in `onScrollGeometryChange`) pushes the deadline
    /// out. This matters on thread entry into a large transcript: `LazyVStack` can
    /// take longer than 400ms to materialize enough rows for the real content size,
    /// so a one-shot timeout from the kickoff moment would clear the pending mode
    /// (and stop re-pinning) before the bottom had settled, leaving the viewport
    /// above the true content end and the transcript appearing blank until the user
    /// dragged up.
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
            //     a preselected thread: `onScrollGeometryChange` hadn't fired yet
            //     when the watchdog landed (`latestMetrics` was nil → `?? false`),
            //     so `isFollowing` flipped to `false` for one frame until a later
            //     geometry tick restored it via `nextFollowingState`.
            //
            // Do NOT call `scrollPosition.scrollTo(edge: .bottom)` here either. An
            // earlier iteration added a "final corrective scrollTo" for the
            // near-but-not-at-bottom case (between the snap and near-bottom thresholds), but that explicit
            // position write interacted badly with `.defaultScrollAnchor(.bottom, for: .sizeChanges)`
            // during LazyVStack calibration on app launch to large threads — the
            // transcript ended up scrolled well above the bottom with the jump-to-
            // latest button visible. The watchdog stays side-effect-free.
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
