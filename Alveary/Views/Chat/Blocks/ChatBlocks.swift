import SwiftUI

let chatBlockPadding: CGFloat = 14
/// Shared vertical rhythm for bubble-style chat surfaces.
let chatVerticalPadding: CGFloat = 10
let chatBlockCornerRadius: CGFloat = 12
let transcriptToolIconFrameSize: CGFloat = 16
let transcriptToolStatusFrameSize = transcriptToolIconFrameSize
let transcriptToolIconTextSpacing: CGFloat = 24
let transcriptToolLeadingTextSpacing = transcriptToolIconTextSpacing - transcriptToolIconFrameSize
let transcriptToolTextStatusSpacing = transcriptToolLeadingTextSpacing
let transcriptToolSummaryFontSize: CGFloat = 13
let transcriptToolApprovalBodyFontSize: CGFloat = 12
let approvalCommandChipCornerRadius: CGFloat = 4
let approvalCommandChipHPadding: CGFloat = 3
let approvalCommandChipVPadding: CGFloat = 1
let toolApprovalSummaryTopSpacing: CGFloat = 8
let toolApprovalActionsTopSpacing: CGFloat = 12
let transcriptToolIconFontSize: CGFloat = 11
let transcriptToolStatusIconFontSize: CGFloat = 11
let transcriptToolStatusSpinnerScale: CGFloat = 0.72
let transcriptToolPressedOpacity = 0.78
let transcriptToolRowVerticalPadding: CGFloat = 4
let transcriptToolExpandedContentTopSpacing: CGFloat = 8
let toolExpandedContentBottomSpacing: CGFloat = 8
let transcriptToolNestedTopSpacing: CGFloat = 8
let transcriptToolNestedRowSpacing: CGFloat = 6
let transcriptToolElbowGap: CGFloat = 10
let transcriptToolNestedRowLeadingInset = transcriptToolIconFrameSize + transcriptToolLeadingTextSpacing
let transcriptToolConnectorOpacity: Double = 0.45
let transcriptToolDetailLeadingInset = transcriptToolIconFrameSize + transcriptToolLeadingTextSpacing
let transcriptBubblePreferredWidthRatio: CGFloat = 2 / 3
let transcriptBubbleMinimumPreferredWidth: CGFloat = 640
let transcriptBubbleCompactTrailingInset: CGFloat = 24

/// Shared expand/collapse easing for tool bubbles. Centralized here so all bubbles
/// ease at the same speed and a future tuning happens in one place.
let toolExpansionAnimation: Animation = .easeInOut(duration: 0.22)

/// Wide transcripts look better when inbound bubbles stop around two-thirds of the
/// available width, but once that cap would squeeze below a comfortable reading width
/// we stop shrinking and only yield when the window itself gets tighter. On compact
/// windows the cap bottoms out at the previous "near the trailing edge" behavior by
/// leaving a 24pt gutter.
func adaptiveTranscriptBubbleMaxWidth(for transcriptContentWidth: CGFloat) -> CGFloat {
    guard transcriptContentWidth > 0 else {
        return .infinity
    }

    let preferredWidth = transcriptContentWidth * transcriptBubblePreferredWidthRatio
    let compactWidth = max(transcriptContentWidth - transcriptBubbleCompactTrailingInset, 0)
    return min(compactWidth, max(preferredWidth, transcriptBubbleMinimumPreferredWidth))
}

/// Propagates the transcript's current width cap down to transcript bubbles.
/// `ChatTranscriptView` computes it with `adaptiveTranscriptBubbleMaxWidth(for:)`
/// after measuring the scroll container. A value of `.infinity` means "unbounded"
/// and is used as the fallback when the transcript hasn't yet reported a size.
private struct TranscriptBubbleMaxWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = .infinity
}

extension EnvironmentValues {
    var transcriptBubbleMaxWidth: CGFloat {
        get { self[TranscriptBubbleMaxWidthKey.self] }
        set { self[TranscriptBubbleMaxWidthKey.self] = newValue }
    }
}

extension View {
    /// Standard transcript-bubble chrome: rounded fill + width cap. Apply
    /// `.padding(chatBlockPadding)` around the bubble's content before this
    /// modifier. Inline tool rows intentionally do not use this chrome.
    func bubbleBackground(maxWidth: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: chatBlockCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    /// Pins tool-row subtree reflow to the shared expansion easing for a specific
    /// value change. The per-toggle `withAnimation(toolExpansionAnimation)` drives
    /// the surrounding `LazyVStack`; this keeps the row's own inserted details and
    /// status/list changes on the same timing.
    func toolAnimationOverride<Value: Equatable>(value: Value) -> some View {
        transaction(value: value) { transaction in
            transaction.animation = toolExpansionAnimation
        }
    }
}

struct DetailCodeBlock: View {
    let title: String
    let content: String
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            // Neither the trailing `Spacer` nor the `.frame(maxWidth: .infinity)` belong
            // here: Spacer makes the HStack greedy, and the infinity-cap on the ScrollView
            // forces the enclosing bubble to grow to `bubbleMaxWidth` every time a short
            // Input/Output snippet appears. Let ScrollView hug its content width; the
            // parent bubble's own `.frame(maxWidth: bubbleMaxWidth)` still caps the outer
            // width and makes oversized content scroll inside the bubble.
            ScrollView(.horizontal) {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
        }
    }
}
