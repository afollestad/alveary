import SwiftUI

private let longBubbleCollapsedMaxContentHeight: CGFloat = 260
private let longBubbleCollapseFadeHeight: CGFloat = 56
private let longBubbleControlClearance: CGFloat = 8
private let longBubbleControlSpacing: CGFloat = 4
private let longBubbleToggleMinHeight: CGFloat = 24
private let longBubbleLikelyOverflowCharacterCount = 900
private let longBubbleLikelyOverflowLineCount = 9
private let longBubbleCollapsedPreviewCharacterCount = 1_400

enum LongMarkdownBubbleSizing {
    static func isLikelyOverflowing(_ markdown: String) -> Bool {
        markdown.count > longBubbleLikelyOverflowCharacterCount ||
            markdown.filter(\.isNewline).count >= longBubbleLikelyOverflowLineCount
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
            Spacer(minLength: userBubbleLeadingClearance)

            VStack(alignment: .trailing, spacing: 6) {
                LongMarkdownBubbleContent(
                    id: id,
                    markdown: text,
                    inlineCodeStyle: .userBubble,
                    foregroundColor: .primary,
                    composerChipProvider: ChatInputFieldTextSupport.composerTextChips(in:),
                    initiallyExpanded: initiallyExpanded
                )
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
            .frame(maxWidth: userBubbleMaxWidth, alignment: .trailing)
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
        LongMarkdownBubbleContent(
            id: id,
            markdown: markdown,
            initiallyExpanded: initiallyExpanded
        )
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

private struct LongMarkdownBubbleContent: View {
    let id: String?
    let markdown: String
    var inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard
    var foregroundColor: Color?
    var composerChipProvider: ((String) -> [AppTextEditorChip])?
    let initiallyExpanded: Bool

    @State private var isExpanded: Bool
    @State private var contentHeight: CGFloat = 0

    init(
        id: String?,
        markdown: String,
        inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard,
        foregroundColor: Color? = nil,
        composerChipProvider: ((String) -> [AppTextEditorChip])? = nil,
        initiallyExpanded: Bool = false
    ) {
        self.id = id
        self.markdown = markdown
        self.inlineCodeStyle = inlineCodeStyle
        self.foregroundColor = foregroundColor
        self.composerChipProvider = composerChipProvider
        self.initiallyExpanded = initiallyExpanded
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: longBubbleControlSpacing) {
            visibleContent

            if isOverflowing {
                expansionToggle
            }
        }
    }

    private var isLikelyOverflowing: Bool {
        Self.isLikelyOverflowing(markdown)
    }

    private var isOverflowing: Bool {
        isLikelyOverflowing || contentHeight > longBubbleCollapsedMaxContentHeight + 1
    }

    private var isCollapsed: Bool {
        isOverflowing && !isExpanded
    }

    private var visibleContent: some View {
        Group {
            if isCollapsed {
                collapsedContent
                    .frame(height: longBubbleCollapsedMaxContentHeight, alignment: .top)
                    .contentShape(Rectangle())
                    .clipped()
                    .mask(alignment: .bottom) {
                        collapsedFadeMask
                    }
            } else {
                measuredFullContent
            }
        }
            .padding(.bottom, isOverflowing ? longBubbleControlClearance : 0)
            .id(isCollapsed)
            .animation(appExpansionAnimation, value: isCollapsed)
    }

    @ViewBuilder
    private var collapsedContent: some View {
        DeferredAppMarkdownText(
            markdown: markdown,
            foregroundColor: foregroundColor,
            inlineCodeStyle: inlineCodeStyle,
            composerChipMode: composerChipProvider == nil ? .none : .composer,
            taskStateScope: id,
            placeholder: collapsedMarkdownPreview
        )
    }

    private var measuredFullContent: some View {
        markdownContent(markdown)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newValue in
                Task { @MainActor in
                    await Task.yield()
                    guard contentHeight != newValue else {
                        return
                    }
                    contentHeight = newValue
                }
            }
    }

    private func markdownContent(_ markdown: String) -> some View {
        AppMarkdownText(
            markdown: markdown,
            foregroundColor: foregroundColor,
            inlineCodeStyle: inlineCodeStyle,
            composerChipProvider: composerChipProvider,
            taskStateScope: id
        )
    }

    private var collapsedMarkdownPreview: String {
        guard markdown.count > longBubbleCollapsedPreviewCharacterCount else {
            return markdown
        }

        let endIndex = markdown.index(markdown.startIndex, offsetBy: longBubbleCollapsedPreviewCharacterCount)
        return String(markdown[..<endIndex])
    }

    private var expansionToggle: some View {
        AppHeaderToggle(fillsWidth: false, action: toggleExpansion) {
            Label(isExpanded ? "Show less" : "Show more", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                .frame(minHeight: longBubbleToggleMinHeight, alignment: .center)
        }
        .transcriptFont(.caption, weight: .medium)
        .foregroundStyle(.secondary)
        .accessibilityLabel(isExpanded ? "Show less" : "Show more")
    }

    private func toggleExpansion() {
        let newValue = !isExpanded
        withAnimation(appExpansionAnimation) {
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

    private static func isLikelyOverflowing(_ markdown: String) -> Bool {
        LongMarkdownBubbleSizing.isLikelyOverflowing(markdown)
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
