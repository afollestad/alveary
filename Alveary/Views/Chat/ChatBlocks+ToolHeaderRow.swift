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

            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 18, alignment: .center)

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

    private var statusIcon: String {
        if tool.isError {
            return "xmark.circle.fill"
        }
        if !tool.isComplete {
            return "circle.dotted"
        }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if tool.isError {
            return .red
        }
        if !tool.isComplete {
            return .secondary
        }
        return .green
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
