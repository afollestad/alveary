import AppKit
import Foundation
import SwiftData
import SwiftUI

private let transcriptTopInset: CGFloat = 20
private let transcriptBottomInset: CGFloat = 14
private let transcriptProgrammaticScrollTimeout: TimeInterval = 0.4

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
    let promptSubmissionIsBusy: Bool
    let workingDirectory: String?

    @Binding var lastScrollTime: Date
    @Binding var isFollowing: Bool
    @Binding var scrollToBottomRequest: Int

    @State private var pendingProgrammaticScrollMode: PendingProgrammaticScrollMode?
    @State private var pendingProgrammaticScrollTimeoutToken: UUID?
    @State private var latestMetrics: ChatTranscriptScrollMetrics?
    @State private var scrollPosition = ScrollPosition()
    @State private var transcriptContentWidth: CGFloat = 0

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
                    case .toolGroup(_, let tools):
                        ToolGroupBlock(tools: tools)
                    case .standaloneTool(_, let tool):
                        StandaloneToolRow(tool: tool)
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
                    case .error(_, let message):
                        ErrorBanner(message: message)
                    }
                }

                if viewModel.turnState.isActive,
                   viewModel.streamingText == nil {
                    ActiveTurnThinkingIndicator()
                }

                if let streamingText = viewModel.streamingText {
                    StreamingBubble(text: streamingText)
                        .id("streaming")
                }

                if viewModel.state.lastTurnInterrupted,
                   !viewModel.turnState.isActive {
                    TurnInterruptedNote()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, transcriptTopInset)
            .padding(.bottom, transcriptBottomInset)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newValue in
                transcriptContentWidth = newValue
            }
            .scrollTargetLayout()
        }
        .environment(\.transcriptBubbleMaxWidth, transcriptContentWidth > 0 ? transcriptContentWidth : .infinity)
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
                    scrollPosition.scrollTo(edge: .bottom)
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

    // Foundation's markdown parser preserves schemeless links like `[text](Alveary/DI/AGENTS.md)`
    // or `[text](~/Desktop/file.png)` as relative URLs (scheme == nil). SwiftUI's default
    // `openURL` hands those straight to `NSWorkspace.shared.open(_:)`, which silently no-ops
    // without a `file://` scheme — so the link does nothing. Handle both shapes here:
    // `~`/`~user` prefixes expand via `NSString.expandingTildeInPath` (URLs don't know about
    // shell home-directory shortcuts), and other relative paths resolve against the thread's
    // working directory. Absolute URLs (https, file, mailto, etc.) pass through unchanged.
    static func resolveMarkdownLinkURL(_ url: URL, workingDirectory: String?) -> URL {
        guard url.scheme == nil else {
            return url
        }
        let relativePath = url.relativeString
        // Fragment-only references (`[top](#section)`) have no path to resolve. Naively
        // feeding them into the workingDirectory branch produces `file:///.../cwd/#section`,
        // which opens the cwd in Finder. Pass through unchanged so NSWorkspace no-ops.
        if relativePath.hasPrefix("#") {
            return url
        }
        if relativePath.hasPrefix("~") {
            // The markdown parser percent-encodes path characters (e.g. spaces → `%20`).
            // `expandingTildeInPath` operates literally, so decode first or filenames with
            // spaces land on disk as `foo%20bar` and the file lookup misses.
            let decoded = relativePath.removingPercentEncoding ?? relativePath
            let expanded = (decoded as NSString).expandingTildeInPath
            guard expanded != decoded else {
                return url
            }
            return URL(fileURLWithPath: expanded)
        }
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return url
        }
        let baseURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        return URL(string: relativePath, relativeTo: baseURL)?.absoluteURL ?? url
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
        scrollPosition.scrollTo(edge: .bottom)

        if retries == .triple {
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
                .foregroundStyle(Color.onAccent)
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
