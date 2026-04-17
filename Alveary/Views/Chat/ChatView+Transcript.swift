import Foundation
import SwiftData
import SwiftUI

private let transcriptTopInset: CGFloat = 20
private let transcriptBottomInset: CGFloat = 8
private let transcriptBottomSnapThreshold: CGFloat = 6
private let transcriptFollowScrollDebounce: TimeInterval = 0.15
private let transcriptProgrammaticScrollTimeout: TimeInterval = 0.4

struct ChatTranscriptScrollMetrics: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat

    var distanceFromBottom: CGFloat {
        contentHeight - (offsetY + containerHeight)
    }

    var isNearBottom: Bool {
        return distanceFromBottom < 60
    }

    var isAtBottom: Bool {
        return distanceFromBottom < transcriptBottomSnapThreshold
    }
}

enum ChatTranscriptScrollBehavior {
    static func shouldPreserveFollowMode(
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics
    ) -> Bool {
        let contentGrew = newMetrics.contentHeight > oldMetrics.contentHeight + 0.5
        let containerChanged = abs(newMetrics.containerHeight - oldMetrics.containerHeight) > 0.5
        let offsetChanged = abs(newMetrics.offsetY - oldMetrics.offsetY) > 0.5
        return oldMetrics.isNearBottom && (contentGrew || containerChanged) && !offsetChanged
    }

    static func shouldCancelProgrammaticScroll(
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics
    ) -> Bool {
        let offsetChanged = abs(newMetrics.offsetY - oldMetrics.offsetY) > 0.5
        let movedFurtherFromBottom = newMetrics.distanceFromBottom > oldMetrics.distanceFromBottom + 0.5
        return offsetChanged && movedFurtherFromBottom
    }

    /// While a `jumpToLatest` scroll is still pending, composer-area changes that shrink the
    /// transcript viewport (e.g. the changed-files strip appearing after an async diff load)
    /// or content that grows below the current bottom move the real bottom out from under the
    /// pending scroll. Re-issue `scrollTo` so we land at the new bottom instead of timing out.
    static func shouldReissuePendingJumpToLatest(
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics
    ) -> Bool {
        let containerShrunk = newMetrics.containerHeight < oldMetrics.containerHeight - 0.5
        let contentGrew = newMetrics.contentHeight > oldMetrics.contentHeight + 0.5
        return containerShrunk || contentGrew
    }

    /// Once `shouldPreserveFollowMode` has fired, decide whether to actually re-scroll.
    /// Container-size changes (e.g. composer banners or the changed-files strip appearing)
    /// are rare and visually noticeable, so they bypass the streaming debounce; other
    /// growth-driven re-scrolls still respect it to avoid fighting streaming cadence.
    static func shouldReScrollOnPreserveFollow(
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics,
        timeSinceLastScroll: TimeInterval,
        debounce: TimeInterval
    ) -> Bool {
        let containerChanged = abs(newMetrics.containerHeight - oldMetrics.containerHeight) > 0.5
        return containerChanged || timeSinceLastScroll >= debounce
    }
}

private enum PendingProgrammaticScrollMode {
    case preserveFollow
    case jumpToLatest
}

struct ChatTranscriptView: View {
    let viewModel: ConversationViewModel
    let events: [ConversationEventRecord]
    let promptSubmissionIsBusy: Bool

    @Binding var lastScrollTime: Date
    @Binding var isFollowing: Bool
    @Binding var scrollToBottomRequest: Int

    @State private var pendingProgrammaticScrollMode: PendingProgrammaticScrollMode?
    @State private var latestMetrics: ChatTranscriptScrollMetrics?
    @State private var scrollPosition = ScrollPosition()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.state.grouper.items) { item in
                    switch item {
                    case .userMessage(let id, let text):
                        UserBubble(
                            text: text,
                            showsRetry: viewModel.state.retryableFailedMessageIDs.contains(id),
                            onRetry: viewModel.state.retryableFailedMessageIDs.contains(id)
                                ? {
                                    Task {
                                        do {
                                            try await viewModel.retryFailedUserMessage(id: id)
                                        } catch {
                                            if viewModel.lastTurnError == nil {
                                                viewModel.lastTurnError = error.localizedDescription
                                            }
                                        }
                                    }
                                }
                                : nil
                        )
                    case .assistantMessage(_, let text):
                        AssistantBubble(markdown: text)
                    case .workingBlock(_, let tools):
                        WorkingBlock(tools: tools)
                    case .subAgentBlock(_, let agents):
                        SubAgentBlock(agents: agents)
                    case .taskListBlock(_, let tasks):
                        TaskListBlock(tasks: tasks)
                    case .promptBlock(_, let prompt):
                        PromptBlock(prompt: prompt, isBusy: promptSubmissionIsBusy) { answers in
                            do {
                                return try await viewModel.answerPrompt(promptId: prompt.id, answers: answers)
                            } catch {
                                if viewModel.lastTurnError == nil {
                                    viewModel.lastTurnError = "Failed to send answer: \(error.localizedDescription)"
                                }
                                return nil
                            }
                        }
                    case .thinking(_, let text):
                        ThinkingBlock(text: text)
                    case .error(_, let message):
                        ErrorBanner(message: message)
                    }
                }

                if viewModel.turnState.isActive,
                   viewModel.streamingText == nil {
                    ActiveTurnThinkingIndicator()
                        .id("active-turn-thinking-indicator")
                }

                if let streamingText = viewModel.streamingText {
                    StreamingBubble(text: streamingText)
                        .id("streaming")
                }

                if viewModel.state.lastTurnInterrupted,
                   !viewModel.turnState.isActive {
                    TurnInterruptedNote()
                }

                Color.clear
                    .frame(height: transcriptBottomInset)
                    .id("chat-bottom")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, transcriptTopInset)
            .scrollTargetLayout()
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(isFollowing ? .bottom : nil, for: .sizeChanges)
        .scrollPosition($scrollPosition, anchor: .bottom)
        .transaction { transaction in
            if viewModel.turnState.isActive {
                transaction.disablesAnimations = true
            }
        }
        .onScrollGeometryChange(for: ChatTranscriptScrollMetrics.self) { geometry in
            ChatTranscriptScrollMetrics(
                offsetY: geometry.contentOffset.y,
                contentHeight: geometry.contentSize.height,
                containerHeight: geometry.containerSize.height
            )
        } action: { oldMetrics, newMetrics in
            latestMetrics = newMetrics

            if let pendingProgrammaticScrollMode {
                if newMetrics.isAtBottom {
                    isFollowing = true
                    self.pendingProgrammaticScrollMode = nil
                } else if ChatTranscriptScrollBehavior.shouldCancelProgrammaticScroll(
                    oldMetrics: oldMetrics,
                    newMetrics: newMetrics
                ) {
                    // A user-initiated scroll away from the bottom beats any pending
                    // programmatic scroll, including `jumpToLatest`. `scrollTo` landing
                    // moves us toward the bottom and is not caught by this check, so
                    // only a real user drag up cancels here.
                    self.pendingProgrammaticScrollMode = nil
                    isFollowing = false
                } else if pendingProgrammaticScrollMode == .jumpToLatest,
                          ChatTranscriptScrollBehavior.shouldReissuePendingJumpToLatest(
                              oldMetrics: oldMetrics,
                              newMetrics: newMetrics
                          ) {
                    scrollPosition.scrollTo(id: "chat-bottom", anchor: .bottom)
                }
                return
            }

            if ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ) {
                isFollowing = true
                let now = Date()
                if ChatTranscriptScrollBehavior.shouldReScrollOnPreserveFollow(
                    oldMetrics: oldMetrics,
                    newMetrics: newMetrics,
                    timeSinceLastScroll: now.timeIntervalSince(lastScrollTime),
                    debounce: transcriptFollowScrollDebounce
                ) {
                    scrollToBottom(at: now)
                }
                return
            }

            isFollowing = newMetrics.isNearBottom
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
            } else {
                viewModel.rebuildChatItemsIfNeeded(from: events, forceFullRebuild: true)
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
    }
}

private extension ChatTranscriptView {
    func scrollToBottom(
        forceFollow: Bool = false,
        at time: Date = Date()
    ) {
        pendingProgrammaticScrollMode = forceFollow ? .jumpToLatest : .preserveFollow
        if forceFollow {
            isFollowing = true
        }
        lastScrollTime = time
        scrollPosition.scrollTo(id: "chat-bottom", anchor: .bottom)

        // Re-issue the bound scroll position after layout settles so lazy rows
        // and footer chrome changes still pin the transcript at the bottom.
        DispatchQueue.main.async {
            guard pendingProgrammaticScrollMode != nil else {
                return
            }
            scrollPosition.scrollTo(id: "chat-bottom", anchor: .bottom)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard pendingProgrammaticScrollMode != nil else {
                return
            }
            scrollPosition.scrollTo(id: "chat-bottom", anchor: .bottom)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + transcriptProgrammaticScrollTimeout) {
            guard let pendingProgrammaticScrollMode else {
                return
            }

            self.pendingProgrammaticScrollMode = nil

            if pendingProgrammaticScrollMode == .jumpToLatest {
                isFollowing = latestMetrics?.isNearBottom ?? false
            }
        }
    }

    func shouldForceBottomScroll(for events: [ConversationEventRecord]) -> Bool {
        guard let lastEvent = events.last else {
            return false
        }

        return lastEvent.type == "message" && lastEvent.role == "user"
    }
}

private struct ScrollToLatestButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        .accessibilityLabel("Jump to latest message")
        .help("Jump to latest message")
    }
}
