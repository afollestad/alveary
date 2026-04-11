import Foundation
import SwiftData
import SwiftUI

struct ChatTranscriptView: View {
    let viewModel: ConversationViewModel
    let events: [ConversationEventRecord]
    let promptSubmissionIsBusy: Bool

    @Binding var lastScrollTime: Date
    @Binding var isFollowing: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.state.grouper.items) { item in
                        switch item {
                        case .userMessage(_, let text):
                            UserBubble(text: text)
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

                    ForEach(viewModel.messageQueue.pending) { entry in
                        QueuedMessageBubble(
                            text: entry.text,
                            showsStagedContext: entry.stagedContext != nil,
                            showsRetry: viewModel.state.inFlightQueuedMessageID == nil
                                && viewModel.messageQueue.peekNext()?.id == entry.id
                                && !viewModel.state.turnState.isActive,
                            isDismissDisabled: viewModel.state.inFlightQueuedMessageID == entry.id,
                            onRetry: {
                                Task { try? await viewModel.retryNextQueuedMessage() }
                            },
                            onDismiss: {
                                viewModel.removeQueuedMessage(id: entry.id)
                            }
                        )
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .transaction { transaction in
                if viewModel.turnState.isActive {
                    transaction.disablesAnimations = true
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceFromBottom = geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
                return distanceFromBottom < 60
            } action: { _, isNearBottom in
                isFollowing = isNearBottom
            }
            .onChange(of: events.count) {
                viewModel.rebuildChatItemsIfNeeded(from: events)
                if isFollowing {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messageQueue.pending.count) {
                guard isFollowing else {
                    return
                }
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
            .onChange(of: viewModel.streamingText) {
                guard isFollowing else {
                    return
                }

                let now = Date()
                if now.timeIntervalSince(lastScrollTime) >= 0.1 {
                    lastScrollTime = now
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            .onAppear {
                viewModel.rebuildChatItemsIfNeeded(from: events)
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
            .onChange(of: viewModel.turnState.isActive) { _, isActive in
                if isActive {
                    isFollowing = true
                }
            }
            .overlay(alignment: .bottom) {
                if !isFollowing && (viewModel.turnState.isActive || viewModel.streamingText != nil) {
                    Button {
                        isFollowing = true
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
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
