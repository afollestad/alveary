import SwiftUI

struct ToolGroupBlock: View {
    let tools: [ToolEntry]
    @State private var isExpanded = false
    // The single-entry branch owns its own `@State` on this type rather than letting
    // a child view hold it. The `ForEach` in the transcript keys `ToolGroupBlock` on
    // `ChatItem.id`, and the group id is stable across stream re-emits (see
    // `ChatItemGrouper.ensureCurrentGroupId`). A child-owned `@State` inside the
    // `tools.count <= 1` branch would reset on some stream updates because its
    // structural identity inside the conditional is fragile.
    @State private var singleEntryExpanded = false

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

    var body: some View {
        if tools.count <= 1, let only = tools.first {
            // Single-entry groups render the tool directly inside the standard pill chrome
            // — the "group" concept is only visually meaningful when folding 2+ entries.
            // The `Button`'s label absorbs the bubble's chrome-side padding so the click
            // zone covers the *entire* header band of the bubble (not just the narrow
            // HStack of chevron + icon + summary). The expanded `ToolDetails` is a
            // sibling in the outer VStack — leaving it outside the Button preserves
            // text selection inside `DetailCodeBlock` and avoids the click-vs-text-
            // selection freeze that a bubble-wide gesture hit.
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    singleEntryExpanded.toggle()
                } label: {
                    ToolHeaderRow(tool: only, isExpanded: singleEntryExpanded)
                        .padding(.horizontal, chatBlockPadding)
                        .padding(.vertical, chatVerticalPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if singleEntryExpanded {
                    // No `.padding(.top)` here: the Button's label already pads on all
                    // sides, so its bottom padding provides the visual gap between the
                    // header and the expanded details. Adding another top pad would
                    // stack the two into a too-open bubble.
                    ToolDetails(tool: only)
                        .padding(.leading, toolDetailLeadingInset + chatBlockPadding)
                        .padding(.trailing, chatBlockPadding)
                        .padding(.bottom, chatVerticalPadding)
                }
            }
            .bubbleBackground(maxWidth: bubbleMaxWidth)
            .toolAnimationOverride(value: singleEntryExpanded)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    isExpanded.toggle()
                } label: {
                    // No trailing `Spacer` here — Spacer makes the HStack greedy, which
                    // defeats the hug-to-content behavior we want for the bubble. With the
                    // Spacer removed, `N failed` sits right after the summary and the
                    // whole bubble hugs its widest child (capped by `bubbleMaxWidth`).
                    HStack(spacing: 10) {
                        DisclosureChevron(isExpanded: isExpanded)

                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if failureCount > 0 {
                            Text("\(failureCount) failed")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(tools) { tool in
                            InlineToolRow(tool: tool)
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, chatBlockPadding)
            .padding(.vertical, chatVerticalPadding)
            .bubbleBackground(maxWidth: bubbleMaxWidth)
            // Both state changes (new tools streaming in, user-driven expansion) need
            // to override the transcript's active-turn `disablesAnimations = true`
            // for the bubble's hug-width / height reflow to ease.
            .toolAnimationOverride(value: tools)
            .toolAnimationOverride(value: isExpanded)
        }
    }

    private var summary: String {
        // Capitalize the first bucket only — "Reading 3 files, searching for 2 patterns"
        // reads like a sentence, whereas "Reading 3 files, Searching for 2 patterns"
        // looks like stuttered headings.
        let summaries = categorySummaries
        guard let first = summaries.first else {
            return ""
        }
        let tail = summaries.dropFirst().map(Self.lowercasedFirstLetter)
        return ([first] + tail).joined(separator: ", ")
    }

    static func lowercasedFirstLetter(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return first.lowercased() + text.dropFirst()
    }

    private var failureCount: Int {
        tools.filter(\.isError).count
    }

    /// Group tools by their category-level bucket (so Grep and Glob fold together), then
    /// emit a natural-language phrase per bucket — "Reading 3 files" rather than
    /// "Reading ×3". Buckets preserve insertion order so the surface reads chronologically.
    private var categorySummaries: [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for tool in tools {
            let key = Self.toolCategoryKey(for: tool.name)
            if counts[key] == nil {
                order.append(key)
            }
            counts[key, default: 0] += 1
        }
        return order.map { key in
            Self.toolCategorySummary(for: key, count: counts[key] ?? 0)
        }
    }

    /// Bucket key used to merge tools with a shared verb (e.g. Grep and Glob both land in
    /// `Search`). Not for display — display runs through `toolCategorySummary(for:count:)`.
    static func toolCategoryKey(for toolName: String) -> String {
        switch toolName {
        case "Read":
            return "Read"
        case "Grep", "Glob":
            return "Search"
        case "WebFetch":
            return "WebFetch"
        case "WebSearch":
            return "WebSearch"
        case "ToolSearch":
            return "ToolSearch"
        default:
            return toolName.hasPrefix("mcp__") ? "MCP" : toolName
        }
    }

    /// Display-facing phrasing for a category bucket. `WebFetch` / `WebSearch` intentionally
    /// ignore their count — "Fetching from the web ×3" reads awkwardly, and the expanded
    /// group already lists the individual calls.
    static func toolCategorySummary(for categoryKey: String, count: Int) -> String {
        switch categoryKey {
        case "Read":
            return count == 1 ? "Reading 1 file" : "Reading \(count) files"
        case "Search":
            return count == 1 ? "Searching for 1 pattern" : "Searching for \(count) patterns"
        case "ToolSearch":
            return count == 1 ? "Searching for 1 tool" : "Searching for \(count) tools"
        case "WebFetch":
            return "Fetching from the web"
        case "WebSearch":
            return "Searching the web"
        case "MCP":
            return count == 1 ? "MCP call" : "\(count) MCP calls"
        default:
            return count == 1 ? categoryKey : "\(categoryKey) ×\(count)"
        }
    }
}
