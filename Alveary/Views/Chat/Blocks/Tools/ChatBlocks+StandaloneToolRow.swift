import SwiftUI

struct StandaloneToolRow: View {
    let tool: ToolEntry
    let initiallyExpanded: Bool
    private let externalIsExpanded: Binding<Bool>?

    init(
        tool: ToolEntry,
        initiallyExpanded: Bool = false,
        isExpanded: Binding<Bool>? = nil
    ) {
        self.tool = tool
        self.initiallyExpanded = initiallyExpanded
        self.externalIsExpanded = isExpanded
    }

    var body: some View {
        InlineToolRow(
            tool: tool,
            initiallyExpanded: initiallyExpanded,
            isExpanded: externalIsExpanded
        )
    }
}
