import SwiftUI

let chatBlockPadding: CGFloat = 14
/// Shared vertical rhythm for chat surfaces — tool bubble headers *and* plain
/// user/assistant text bubbles. Having tool rows match this keeps a collapsed
/// tool bubble visually the same height as its neighboring text bubble (the
/// 14pt all-sides default used to make tool rows ~8pt taller).
let chatVerticalPadding: CGFloat = 10
let chatBlockCornerRadius: CGFloat = 12
let toolDetailLeadingInset: CGFloat = 42

/// Shared expand/collapse easing for tool bubbles. Centralized here so all bubbles
/// ease at the same speed and a future tuning happens in one place.
let toolExpansionAnimation: Animation = .easeInOut(duration: 0.22)

/// Propagates the transcript's current content width down to tool bubbles so they can
/// cap their growth near the window edge instead of a fixed 720pt ceiling.
/// `ChatTranscriptView` sets this via `.environment(\.transcriptBubbleMaxWidth, ...)`
/// after measuring its scroll container. A value of `.infinity` means "unbounded" and
/// is used as the fallback when the transcript hasn't yet reported a size.
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
    /// `.padding(chatBlockPadding)` around the bubble's content *before* this
    /// modifier when the whole bubble wants outer padding (multi-entry
    /// `ToolGroupBlock`, `SubAgentBlock`, `TaskListBlock`). Variants whose
    /// Button label absorbs the padding (`StandaloneToolRow`, single-entry
    /// `ToolGroupBlock`) skip the outer padding — the label's own
    /// `.padding(chatBlockPadding)` provides the inner spacing there.
    func bubbleBackground(maxWidth: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: chatBlockCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    /// Re-enable expand/collapse animation for a specific state transition while
    /// the transcript's active-turn `.transaction { $0.disablesAnimations = true }`
    /// is in effect. Without this override the bubble would snap to its new
    /// height/width during streaming turns — the one time the animation matters.
    /// Pair `value:` with whatever drives the layout shape (e.g. `isExpanded`,
    /// the tool list).
    func toolAnimationOverride<Value: Equatable>(value: Value) -> some View {
        transaction(value: value) { transaction in
            transaction.disablesAnimations = false
            transaction.animation = toolExpansionAnimation
        }
    }
}

struct DisclosureChevron: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
            .frame(width: 12, alignment: .center)
            .foregroundStyle(.secondary)
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
