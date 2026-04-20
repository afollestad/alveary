import SwiftUI

/// Inline tool row with self-managed expansion state. The toggle `Button` wraps *only*
/// `ToolHeaderRow`; expanded `ToolDetails` renders as a sibling below so its text
/// selection and horizontal scroll don't contend with a bubble-wide gesture — that
/// contention was observed to freeze expand/collapse taps.
struct InlineToolRow: View {
    let tool: ToolEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                ToolHeaderRow(tool: tool, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ToolDetails(tool: tool)
                    .padding(.top, 10)
                    .padding(.leading, toolDetailLeadingInset)
            }
        }
        .toolAnimationOverride(value: isExpanded)
    }
}
