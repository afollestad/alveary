import SwiftData
import SwiftUI

private let chatBubbleHorizontalPadding: CGFloat = 12
private let chatBubbleCornerRadius: CGFloat = 12
private let projectTrustPromptMessageMaxWidth: CGFloat = 760
private let longBubbleCollapsedMaxContentHeight: CGFloat = 260
private let longBubbleCollapseFadeHeight: CGFloat = 56
private let longBubbleControlClearance: CGFloat = 8
private let longBubbleControlSpacing: CGFloat = 4
private let longBubbleToggleMinHeight: CGFloat = 24

struct ProjectTrustPrompt: Equatable {
    let threadID: PersistentIdentifier
    let canonicalProjectPath: String
    let projectName: String
    let providerID: String

    var displayProjectPath: String {
        CanonicalPath.abbreviateHomeDirectory(canonicalProjectPath)
    }
}

// swiftlint:disable transcript_font_helpers
struct ProjectTrustPromptView: View {
    let prompt: ProjectTrustPrompt
    let onTrust: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Trust this project?")
                    .font(.title3.weight(.semibold))

                Text("Claude needs this project marked as trusted before this thread can start.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: projectTrustPromptMessageMaxWidth)

                Text(prompt.displayProjectPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(prompt.canonicalProjectPath)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 12) {
                Button("No, don't trust it", role: .destructive, action: onDeny)
                    .secondaryActionButtonStyle()

                Button("Yes, trust it", action: onTrust)
                    .primaryActionButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct EmptyThreadState: View {
    let setupPhase: SetupPhase?
    let isCancellingInitialSetup: Bool

    var body: some View {
        Group {
            if isCancellingInitialSetup {
                VStack(spacing: 18) {
                    ProgressView()
                        .controlSize(.large)

                    Text("Cancelling setup")
                        .font(.title3.weight(.semibold))

                    Text("Cleaning up the partial worktree and rollback branch.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let setupPhase {
                VStack(spacing: 18) {
                    ProgressView()
                        .controlSize(.large)

                    Text(title(for: setupPhase))
                        .font(.title3.weight(.semibold))

                    Text(message(for: setupPhase))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: "sparkles",
                    heading: "Let’s build",
                    subtext: "Ask your agent to explore the project, make changes, or explain what it finds. " +
                        "Your first message will start the session.",
                    actions: []
                )
            }
        }
    }
}
// swiftlint:enable transcript_font_helpers

private extension EmptyThreadState {
    func title(for phase: SetupPhase) -> String {
        switch phase {
        case .creatingWorktree:
            return "Creating worktree"
        case .startingAgent:
            return "Starting agent"
        }
    }

    func message(for phase: SetupPhase) -> String {
        switch phase {
        case .creatingWorktree:
            return "Preparing an isolated working directory for this thread."
        case .startingAgent:
            return "Launching the conversation runtime and preparing the first turn."
        }
    }
}

struct UserBubble: View {
    let id: String?
    let text: String
    let showsRetry: Bool
    let onRetry: (() -> Void)?
    let initiallyExpanded: Bool

    init(
        id: String? = nil,
        text: String,
        showsRetry: Bool,
        onRetry: (() -> Void)?,
        initiallyExpanded: Bool = false
    ) {
        self.id = id
        self.text = text
        self.showsRetry = showsRetry
        self.onRetry = onRetry
        self.initiallyExpanded = initiallyExpanded
    }

    var body: some View {
        HStack {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 6) {
                LongTextBubbleContent(initiallyExpanded: initiallyExpanded) {
                    AppMarkdownText(
                        markdown: text,
                        foregroundColor: .primary,
                        inlineCodeStyle: .userBubble,
                        composerChipProvider: ChatInputFieldTextSupport.composerTextChips(in:),
                        taskStateScope: id
                    )
                }
                .padding(.horizontal, chatBubbleHorizontalPadding)
                .padding(.vertical, chatVerticalPadding)
                .transcriptMarkdownTypography()
                .background(
                    RoundedRectangle(cornerRadius: chatBubbleCornerRadius, style: .continuous)
                        .fill(AppAccentFill.primary)
                )
                // Keeps rendered text moving with the bubble chrome during animated
                // transcript reflow.
                .geometryGroup()

                if showsRetry, let onRetry {
                    HStack(spacing: 8) {
                        Text("Not sent")
                            .transcriptFont(.caption)
                            .foregroundStyle(.secondary)

                        Button("Retry", action: onRetry)
                            .controlSize(.small)
                            .secondaryActionButtonStyle()
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .trailing)
        }
    }
}

struct AssistantBubble: View {
    let id: String?
    let markdown: String

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth
    let initiallyExpanded: Bool

    init(
        id: String? = nil,
        markdown: String,
        initiallyExpanded: Bool = false
    ) {
        self.id = id
        self.markdown = markdown
        self.initiallyExpanded = initiallyExpanded
    }

    var body: some View {
        LongTextBubbleContent(initiallyExpanded: initiallyExpanded) {
            AppMarkdownText(
                markdown: markdown,
                taskStateScope: id
            )
        }
        .padding(.horizontal, chatBubbleHorizontalPadding)
        .padding(.vertical, chatVerticalPadding)
        .transcriptMarkdownTypography()
        .background(
            RoundedRectangle(cornerRadius: chatBubbleCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        // See the matching user-bubble comment above.
        .geometryGroup()
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
    }
}

private struct LongTextBubbleContent<Content: View>: View {
    @State private var isExpanded: Bool
    @State private var contentHeight: CGFloat = 0

    private let content: Content

    init(
        initiallyExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        _isExpanded = State(initialValue: initiallyExpanded)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: longBubbleControlSpacing) {
            visibleContent

            if isOverflowing {
                expansionToggle
            }
        }
    }

    private var isOverflowing: Bool {
        contentHeight > longBubbleCollapsedMaxContentHeight + 1
    }

    private var isCollapsed: Bool {
        isOverflowing && !isExpanded
    }

    private var visibleContent: some View {
        Group {
            if isCollapsed {
                measuredContent
                    .frame(height: longBubbleCollapsedMaxContentHeight, alignment: .top)
                    .contentShape(Rectangle())
                    .clipped()
                    .mask(alignment: .bottom) {
                        collapsedFadeMask
                    }
            } else {
                measuredContent
            }
        }
            .padding(.bottom, isOverflowing ? longBubbleControlClearance : 0)
            // Rebuild the text subtree when the cap toggles so selectable runs and
            // task controls inherit the current clipped layout.
            .id(isCollapsed)
            .animation(toolExpansionAnimation, value: isCollapsed)
    }

    private var expansionToggle: some View {
        TranscriptHeaderToggle(fillsWidth: false, action: toggleExpansion) {
            Label(isExpanded ? "Show less" : "Show more", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                .frame(minHeight: longBubbleToggleMinHeight, alignment: .center)
        }
        .transcriptFont(.caption, weight: .medium)
        .foregroundStyle(.secondary)
        .accessibilityLabel(isExpanded ? "Show less" : "Show more")
    }

    private func toggleExpansion() {
        let newValue = !isExpanded
        withAnimation(toolExpansionAnimation) {
            isExpanded = newValue
        }
    }

    private var collapsedFadeMask: some View {
        VStack(spacing: 0) {
            Rectangle()
            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: longBubbleCollapseFadeHeight)
        }
    }

    private var measuredContent: some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newValue in
                contentHeight = newValue
            }
    }
}

struct StreamingBubble: View {
    let text: String
    @State private var cursorVisible = true

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Text(text)
                .textSelection(.enabled)

            Rectangle()
                .fill(.primary.opacity(cursorVisible ? 0.65 : 0))
                .frame(width: 2, height: 16)
        }
        .padding(.horizontal, chatBubbleHorizontalPadding)
        .padding(.vertical, chatVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: chatBubbleCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .onAppear {
            cursorVisible = true
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
    }
}

struct ActiveTurnThinkingIndicator: View {
    @State private var startDate: Date?

    private let isAnimated: Bool
    private let dotCount = 3
    private let cycleDuration: Double = 1.1
    private let dotPhaseOffset: Double = 0.22

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

    init(isAnimated: Bool = true) {
        self.isAnimated = isAnimated
    }

    var body: some View {
        TimelineView(.animation(paused: startDate == nil)) { context in
            let elapsed = startDate.map { context.date.timeIntervalSince($0) } ?? 0
            HStack(spacing: 6) {
                ForEach(0..<dotCount, id: \.self) { index in
                    let progress = pulseProgress(elapsed: elapsed, index: index)
                    Circle()
                        .fill(.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(0.28 + progress * 0.57)
                        .scaleEffect(0.72 + progress * 0.28)
                }
            }
        }
        .padding(.horizontal, chatBubbleHorizontalPadding)
        .padding(.vertical, chatVerticalPadding)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant is thinking")
        .onAppear {
            // Skipping the startDate assignment keeps `TimelineView(.animation(paused:))`
            // pinned to `elapsed == 0`, which is what snapshot tests rely on for determinism.
            guard isAnimated else { return }
            startDate = Date()
        }
    }

    private func pulseProgress(elapsed: TimeInterval, index: Int) -> Double {
        let phase = (elapsed / cycleDuration - Double(index) * dotPhaseOffset) * 2 * .pi
        return (1 - cos(phase)) / 2
    }
}

struct ErrorBanner: View {
    let message: String

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

    var body: some View {
        InlineBanner(message: message, severity: .error, autoDismissAfter: nil)
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
    }
}

struct CenteredTranscriptNote: View {
    let kind: CenteredTranscriptNoteKind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")

            Text(kind.text)
        }
        .transcriptFont(.body, weight: .medium)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }
}

struct TurnInterruptedNote: View {
    var body: some View {
        CenteredTranscriptNote(kind: .interrupted)
    }
}

// swiftlint:disable transcript_font_helpers
struct StagedContextBanner: View {
    let context: String
    let onDismiss: () -> Void

    private var summary: String {
        let firstLine = context
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Context included."

        if firstLine.count > 96 {
            return String(firstLine.prefix(93)) + "..."
        }
        return firstLine
    }

    var body: some View {
        HStack(spacing: 12) {
            Label(summary, systemImage: "paperclip")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss context")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
// swiftlint:enable transcript_font_helpers
