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
                .foregroundStyle(.primary)

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
        // Width *and height* are pinned so the enclosing HStack doesn't reflow when
        // the branch swaps. `ProgressView().controlSize(.small)` reserves ~16pt of
        // intrinsic layout height (scaleEffect only transforms the render — it doesn't
        // shrink the layout box), while the SF Symbol at the ambient body font is
        // intrinsically ~13pt tall. Without a fixed height, the HStack grew during
        // the in-progress state and then shrank on spinner→checkmark, which caused a
        // visible vertical nudge in the enclosing bubble whenever a tool group rapidly
        // toggled between working and success as additional tool calls streamed in.
        // 16pt matches the spinner's natural layout size, so pinning there keeps rows
        // at the height they already had while the spinner was present; icons render
        // centered within that slot at their intrinsic ~13pt size.
        .frame(width: 18, height: 16, alignment: .center)
        // Snap the *branch swap* (spinner → checkmark → xmark) so it doesn't
        // cross-fade from whatever transient state SwiftUI picks. Crucially this is
        // scoped to `value: branchKey` — a bare `.transaction { $0.animation = nil }`
        // also nulled out layout-driven updates, so when a neighboring bubble expanded
        // or collapsed and the transcript's animation propagated through the
        // `LazyVStack`, this indicator snapped to its new position while the rest of
        // its row eased. Scoping to branch identity suppresses only the branch
        // transition; surrounding layout still animates at the parent's cadence.
        .transaction(value: branchKey) { $0.animation = nil }
    }

    private var branchKey: Int {
        if isError { return 0 }
        if isComplete { return 1 }
        return 2
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
