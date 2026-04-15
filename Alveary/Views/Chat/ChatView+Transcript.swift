import Foundation
import SwiftData
import SwiftUI

private let transcriptVerticalInset: CGFloat = 20

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
}

struct ChatTranscriptView: View {
    let viewModel: ConversationViewModel
    let events: [ConversationEventRecord]
    let promptSubmissionIsBusy: Bool

    @Binding var lastScrollTime: Date
    @Binding var isFollowing: Bool
    @Binding var scrollToBottomRequest: Int

    @State private var pendingProgrammaticScroll = false

    var body: some View {
        ScrollViewReader { proxy in
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

                    if let streamingText = viewModel.streamingText {
                        StreamingBubble(text: streamingText)
                            .id("streaming")
                    }

                    if viewModel.state.lastTurnInterrupted,
                       !viewModel.turnState.isActive {
                        TurnInterruptedNote()
                    }

                    Color.clear
                        .frame(height: transcriptVerticalInset)
                        .id("chat-bottom")
                }
                .padding(.horizontal, 20)
                .padding(.top, transcriptVerticalInset)
            }
            .defaultScrollAnchor(.bottom)
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
                if pendingProgrammaticScroll {
                    if newMetrics.isNearBottom {
                        pendingProgrammaticScroll = false
                        isFollowing = true
                    } else if ChatTranscriptScrollBehavior.shouldCancelProgrammaticScroll(
                        oldMetrics: oldMetrics,
                        newMetrics: newMetrics
                    ) {
                        pendingProgrammaticScroll = false
                        isFollowing = false
                    }
                    return
                }

                if ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
                    oldMetrics: oldMetrics,
                    newMetrics: newMetrics
                ) {
                    isFollowing = true
                    scrollToBottom(using: proxy)
                    return
                }

                isFollowing = newMetrics.isNearBottom
            }
            .onChange(of: events.count) {
                if !viewModel.turnState.isActive {
                    viewModel.rebuildChatItemsIfNeeded(from: events)
                }
                if shouldForceBottomScroll(for: events) {
                    scrollToBottom(using: proxy, forceFollow: true)
                } else if isFollowing {
                    scrollToBottom(using: proxy)
                }
            }
            .onChange(of: viewModel.messageQueue.pending.count) { oldCount, newCount in
                guard newCount > oldCount else {
                    return
                }
                scrollToBottom(using: proxy, forceFollow: true)
            }
            .onChange(of: viewModel.streamingText) {
                guard isFollowing else {
                    return
                }

                let now = Date()
                if now.timeIntervalSince(lastScrollTime) >= 0.1 {
                    scrollToBottom(using: proxy, at: now)
                }
            }
            .onAppear {
                viewModel.rebuildChatItemsIfNeeded(from: events)
                scrollToBottom(using: proxy, forceFollow: true)
            }
            .onChange(of: viewModel.turnState.isActive) { _, isActive in
                if isActive {
                    isFollowing = true
                } else {
                    viewModel.rebuildChatItemsIfNeeded(from: events, forceFullRebuild: true)
                }
            }
            .onChange(of: scrollToBottomRequest) { _, _ in
                scrollToBottom(using: proxy, forceFollow: true)
            }
            .overlay(alignment: .bottom) {
                if !isFollowing && (viewModel.turnState.isActive || viewModel.streamingText != nil) {
                    Button {
                        scrollToBottom(using: proxy, forceFollow: true)
                    } label: {
                        Label("Jump to bottom", systemImage: "arrow.down")
                    }
                    .primaryActionButtonStyle()
                    .padding(.bottom, 12)
                }
            }
        }
    }
}

private extension ChatTranscriptView {
    func scrollToBottom(
        using proxy: ScrollViewProxy,
        forceFollow: Bool = false,
        at time: Date = Date()
    ) {
        if forceFollow {
            isFollowing = true
        }

        pendingProgrammaticScroll = true
        lastScrollTime = time
        proxy.scrollTo("chat-bottom", anchor: .bottom)

        // Lazy transcript layout can settle after the first scroll request, so
        // issue one more scroll on the next pass to keep follow mode pinned.
        DispatchQueue.main.async {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }

    func shouldForceBottomScroll(for events: [ConversationEventRecord]) -> Bool {
        guard let lastEvent = events.last else {
            return false
        }

        return lastEvent.type == "message" && lastEvent.role == "user"
    }
}
