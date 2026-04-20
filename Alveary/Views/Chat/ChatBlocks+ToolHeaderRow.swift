import Foundation
import SwiftUI

/// Parse a tool summary (e.g. ``"Read `~/foo.swift`"``) as Markdown and tint any
/// inline-code runs so the backticked span visually reads as a code pill rather than
/// a bare monospaced slice. Parsing + run-walking on every body evaluation showed up
/// as the hottest path during transcript scrolling (every visible `ToolHeaderRow`
/// re-evaluates on parent state changes), so the result is memoized on the MainActor —
/// the input set is bounded by the tools in the conversation, and the cache is never
/// purged for a single session.
@MainActor
private func attributedToolSummary(_ text: String) -> AttributedString {
    AttributedSummaryCache.attributed(text)
}

@MainActor
private enum AttributedSummaryCache {
    static var cache: [String: AttributedString] = [:]

    static func attributed(_ text: String) -> AttributedString {
        if let cached = cache[text] {
            return cached
        }

        let result: AttributedString
        if var attributed = try? AttributedString(markdown: text) {
            for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
                attributed[run.range].backgroundColor = Color.secondary.opacity(0.18)
            }
            result = attributed
        } else {
            result = AttributedString(text)
        }

        cache[text] = result
        return result
    }
}

/// Collapsed-state header used by every tool-row variant (`StandaloneToolRow`,
/// `ToolGroupBlock` single-entry, `InlineToolRow`, `SubAgentToolRow`). Each variant
/// wraps `ToolHeaderRow` in a `Button` and renders `ToolDetails` as a sibling when
/// expanded, so clicks on the expanded body (which enables `.textSelection`) don't
/// contend with a bubble-wide tap gesture — that contention produced the earlier
/// expand/collapse freeze.
struct ToolHeaderRow: View {
    let tool: ToolEntry
    let isExpanded: Bool

    var body: some View {
        // No trailing `Spacer` here — Spacer makes the HStack greedy and defeats the
        // hug-to-content behavior the enclosing bubble relies on.
        HStack(alignment: .center, spacing: 10) {
            DisclosureChevron(isExpanded: isExpanded)

            ToolStatusIndicator(isError: tool.isError, isComplete: tool.isComplete)

            // Parse the summary as Markdown so backticks become inline-code runs (with a
            // tinted background pill), and so `LocalizedStringKey`-only quirks with
            // runtime strings don't silently strip the formatting.
            Text(attributedToolSummary(tool.summary))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tool.isError ? .red : .primary)

            if tool.isInterrupted {
                InterruptedTag()
            }
        }
        .contentShape(Rectangle())
    }
}

/// Status indicator shared by single-tool headers (`ToolHeaderRow`) and the aggregate
/// multi-entry `ToolGroupBlock` header. Rotation for the in-progress spinner runs on
/// Core Animation (NSProgressIndicator on macOS), so it does not re-evaluate the
/// SwiftUI view tree per frame and is safe to leave mounted during transcript scrolling.
///
/// Earlier iterations tried a custom `withAnimation(.repeatForever)` SwiftUI spinner
/// to avoid `NSProgressIndicator`'s first-frame warmup and its timing-driven rotation
/// (a potential source of snapshot flakes). That approach caused thread-open renders
/// to land with a blank transcript until the user scrolled — a never-ending SwiftUI
/// animation on a LazyVStack row interacted badly with `scrollPosition` /
/// `defaultScrollAnchor` layout coordination. `ProgressView` stays in its own AppKit
/// layer and does not disturb SwiftUI layout, so it is the more stable choice even
/// though its first-frame appearance is briefly empty.
///
/// Branch animations are explicitly suppressed: the enclosing tool bubble applies
/// `toolAnimationOverride(value: tools)` to ease its width/height reflow when tools
/// stream in, but that transaction also propagates down and would cross-fade the
/// status branches (or animate a newly-inserted `InlineToolRow` from whatever
/// transient state SwiftUI picks). The status branches should snap — a spinner
/// appearing *as* a spinner, not fading in from an ambiguous initial state.
struct ToolStatusIndicator: View {
    let isError: Bool
    let isComplete: Bool

    var body: some View {
        Group {
            if isError {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            } else if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
            }
        }
        // Width is constrained so chevron-icon-text columns line up across branches,
        // but height is left to the indicator's intrinsic size so the enclosing HStack
        // still hugs the semibold-subheadline text's line height. Pinning height to 18
        // made rows ~1pt taller than the text-driven layout this replaced.
        .frame(width: 18, alignment: .center)
        .transaction { $0.animation = nil }
    }
}

struct InterruptedTag: View {
    var body: some View {
        Text("Interrupted")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.orange.opacity(0.18)))
    }
}
