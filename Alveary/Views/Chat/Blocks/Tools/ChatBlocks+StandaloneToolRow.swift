import SwiftUI

struct StandaloneToolRow: View {
    let tool: ToolEntry
    let initiallyExpanded: Bool
    let headerFrameID: String?
    private let externalIsExpanded: Binding<Bool>?

    init(
        tool: ToolEntry,
        initiallyExpanded: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        headerFrameID: String? = nil
    ) {
        self.tool = tool
        self.initiallyExpanded = initiallyExpanded
        self.externalIsExpanded = isExpanded
        self.headerFrameID = headerFrameID
    }

    var body: some View {
        InlineToolRow(
            tool: tool,
            initiallyExpanded: initiallyExpanded,
            isExpanded: externalIsExpanded,
            headerFrameID: headerFrameID
        )
    }
}
