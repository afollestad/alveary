import SwiftData
import SwiftUI

private let chatBubbleHorizontalPadding: CGFloat = 12
private let chatBubbleCornerRadius: CGFloat = 12
private let projectTrustPromptMessageMaxWidth: CGFloat = 760

struct ProjectTrustPrompt: Equatable {
    let threadID: PersistentIdentifier
    let canonicalProjectPath: String
    let projectName: String
    let providerID: String

    var displayProjectPath: String {
        CanonicalPath.abbreviateHomeDirectory(canonicalProjectPath)
    }
}

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

    init(
        id: String? = nil,
        text: String,
        showsRetry: Bool,
        onRetry: (() -> Void)?
    ) {
        self.id = id
        self.text = text
        self.showsRetry = showsRetry
        self.onRetry = onRetry
    }

    var body: some View {
        HStack {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 6) {
                AppMarkdownText(
                    markdown: text,
                    foregroundColor: .primary,
                    inlineCodeStyle: .userBubble,
                    composerChipProvider: ChatInputFieldTextSupport.composerTextChips(in:),
                    taskStateScope: id
                )
                .padding(.horizontal, chatBubbleHorizontalPadding)
                .padding(.vertical, chatVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: chatBubbleCornerRadius, style: .continuous)
                        .fill(AppAccentFill.primary)
                )
                // Keeps rendered text moving with the bubble chrome during transcript
                // reflow from tool-row expand/collapse.
                .geometryGroup()

                if showsRetry, let onRetry {
                    HStack(spacing: 8) {
                        Text("Not sent")
                            .font(.caption)
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

    init(
        id: String? = nil,
        markdown: String
    ) {
        self.id = id
        self.markdown = markdown
    }

    var body: some View {
        AppMarkdownText(markdown: markdown, taskStateScope: id)
            .padding(.horizontal, chatBubbleHorizontalPadding)
            .padding(.vertical, chatVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: chatBubbleCornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            // See the matching user-bubble comment above.
            .geometryGroup()
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
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
        .font(.body.weight(.medium))
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

struct StagedContextBanner: View {
    let context: String
    let onDismiss: () -> Void

    private var summary: String {
        let singleLine = context.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count > 140 {
            return String(singleLine.prefix(137)) + "..."
        }
        return singleLine
    }

    var body: some View {
        HStack(spacing: 12) {
            Label("Including context", systemImage: "paperclip")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
