import SwiftUI

private let chatBubbleHorizontalPadding: CGFloat = 12
private let chatBubbleVerticalPadding: CGFloat = 10
private let chatBubbleCornerRadius: CGFloat = 12

struct EmptyThreadState: View {
    let showsRetryState: Bool
    let setupPhase: SetupPhase?
    let isCancellingInitialSetup: Bool
    let error: String?
    let onRetry: () -> Void

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
            } else if showsRetryState {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.orange)

                    VStack(spacing: 8) {
                        Text("Initial setup failed")
                            .font(.title3.weight(.semibold))

                        if let error {
                            Text(error)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 460)
                        }
                    }

                    Button("Retry", action: onRetry)
                        .primaryActionButtonStyle()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
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
    let text: String
    let showsRetry: Bool
    let onRetry: (() -> Void)?

    private var containsMarkdownCode: Bool {
        AppMarkdownCodeBlockParser.containsCode(in: text)
    }

    var body: some View {
        HStack {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 6) {
                Group {
                    if containsMarkdownCode {
                        AppMarkdownText(
                            markdown: text,
                            foregroundColor: .white,
                            inlineCodeStyle: .userBubble
                        )
                    } else {
                        Text(text)
                            .textSelection(.enabled)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, chatBubbleHorizontalPadding)
                .padding(.vertical, chatBubbleVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: chatBubbleCornerRadius, style: .continuous)
                        .fill(Color.accentColor)
                )

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
    let markdown: String

    var body: some View {
        AppMarkdownText(markdown: markdown)
            .padding(.horizontal, chatBubbleHorizontalPadding)
            .padding(.vertical, chatBubbleVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: chatBubbleCornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .frame(maxWidth: 720, alignment: .leading)
    }
}

struct StreamingBubble: View {
    let text: String
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Text(text)
                .textSelection(.enabled)

            Rectangle()
                .fill(.primary.opacity(cursorVisible ? 0.65 : 0))
                .frame(width: 2, height: 16)
        }
        .padding(.horizontal, chatBubbleHorizontalPadding)
        .padding(.vertical, chatBubbleVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: chatBubbleCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .frame(maxWidth: 720, alignment: .leading)
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
        .padding(.vertical, chatBubbleVerticalPadding)
        .frame(maxWidth: 720, alignment: .leading)
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

    var body: some View {
        InlineBanner(message: message, severity: .error, autoDismissAfter: nil) {}
            .frame(maxWidth: 720, alignment: .leading)
    }
}

struct TurnInterruptedNote: View {
    var body: some View {
        Text("Interrupted")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
    }
}

struct ReconfigureStatusBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
    }
}

struct PermissionBanner: View {
    let canEscalate: Bool
    let isActionDisabled: Bool
    let escalationLabel: String
    let onDismiss: () -> Void
    let onEscalate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.slash.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 10) {
                Text("The last turn hit a permission denial.")
                    .font(.subheadline.weight(.medium))

                if canEscalate {
                    HStack(spacing: 10) {
                        Button(escalationLabel, action: onEscalate)
                            .primaryActionButtonStyle()
                            .disabled(isActionDisabled)

                        Button("Dismiss", action: onDismiss)
                            .secondaryActionButtonStyle()
                    }
                } else {
                    Button("Dismiss", action: onDismiss)
                        .secondaryActionButtonStyle()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
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

struct ChangedFilesStrip: View {
    let files: [FileStatus]
    let onOpenDiff: (FileStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Changed files")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(files.prefix(8)) { file in
                        HStack(spacing: 8) {
                            Text(symbol(for: file))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(file.isStaged ? .green : .secondary)

                            Text(displayName(for: file))
                                .lineLimit(1)
                                .font(.caption)

                            Divider()
                                .frame(height: 14)

                            Button("Diff") {
                                onOpenDiff(file)
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
            }
        }
    }

    private func displayName(for file: FileStatus) -> String {
        if let originalPath = file.originalPath,
           originalPath != file.path {
            return "\(originalPath) → \(file.path)"
        }
        return file.path
    }

    private func symbol(for file: FileStatus) -> String {
        switch file.status {
        case .modified:
            return "●"
        case .added, .untracked:
            return "+"
        case .deleted:
            return "−"
        case .renamed:
            return "→"
        case .copied:
            return "⧉"
        case .unmerged:
            return "!"
        }
    }
}
