import SwiftUI

struct StandaloneToolRow: View {
    let tool: ToolEntry
    @State private var isExpanded: Bool

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

    init(tool: ToolEntry, initiallyExpanded: Bool = false) {
        self.tool = tool
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        // The `Button`'s label absorbs the bubble's chrome-side padding so the click
        // zone covers the entire header band of the bubble, not just the narrow
        // HStack of chevron + icon + summary (short tool summaries like
        // `ToolSearch` "Searching for tool `X`" / "Searching for tools `X` and `Y`"
        // were easy to miss otherwise). The
        // expanded `ToolDetails` is a sibling in the outer VStack — leaving it
        // outside the Button preserves text selection inside `DetailCodeBlock` and
        // avoids the tap/text-selection contention that a bubble-wide gesture had.
        VStack(alignment: .leading, spacing: 0) {
            Button {
                // `withAnimation` is load-bearing for sibling layout: `.toolAnimationOverride`
                // only scopes the transaction to this bubble's subtree, so the enclosing
                // `LazyVStack`'s sibling positions would snap to their new locations while
                // this bubble's frame was still shrinking, briefly overlapping the next item.
                // `withAnimation` sets the animation on the transaction globally for this
                // state change so the LazyVStack's reflow eases in lockstep with the bubble.
                withAnimation(toolExpansionAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                ToolHeaderRow(tool: tool, isExpanded: isExpanded)
                    .padding(.horizontal, chatBlockPadding)
                    .padding(.vertical, chatVerticalPadding)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                // See matching comment in `ToolGroupBlock`'s single-entry branch —
                // the Button's label already pads on all sides, so we rely on its
                // bottom padding for the header-to-details gap.
                ToolDetails(tool: tool)
                    .padding(.leading, toolDetailLeadingInset + chatBlockPadding)
                    .padding(.trailing, chatBlockPadding)
                    .padding(.bottom, chatVerticalPadding)
            }
        }
        .bubbleBackground(maxWidth: bubbleMaxWidth)
        .toolAnimationOverride(value: isExpanded)
    }
}
