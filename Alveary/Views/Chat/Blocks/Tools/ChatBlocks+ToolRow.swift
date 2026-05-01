import SwiftUI

/// Inline tool row with self-managed expansion state. The toggle `Button` wraps *only*
/// `ToolHeaderRow`; expanded `ToolDetails` renders as a sibling below so its text
/// selection and horizontal scroll don't contend with a bubble-wide gesture — that
/// contention was observed to freeze expand/collapse taps.
struct InlineToolRow: View {
    let tool: ToolEntry
    var headerPreferenceID: String?
    private let externalIsExpanded: Binding<Bool>?
    @State private var localIsExpanded: Bool

    init(
        tool: ToolEntry,
        initiallyExpanded: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        headerPreferenceID: String? = nil
    ) {
        self.tool = tool
        self.headerPreferenceID = headerPreferenceID
        self.externalIsExpanded = isExpanded
        _localIsExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        if tool.name == "Skill" {
            ToolHeaderRow(
                tool: tool,
                isExpanded: false,
                bottomPadding: transcriptToolRowVerticalPadding
            )
                .background {
                    headerCenterPreference(bottomPadding: transcriptToolRowVerticalPadding)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            expandableToolRow
        }
    }

    @ViewBuilder
    private var expandableToolRow: some View {
        let expansion = expansionBinding
        let headerBottomPadding = expansion.wrappedValue ? 0 : transcriptToolRowVerticalPadding
        let toggleExpansion = {
            // See note in `StandaloneToolRow`: `withAnimation` propagates the
            // animation to the surrounding layout (the expanded `ToolGroupBlock`
            // list or a `SubAgentBlock`) so nested sibling rows reflow in step
            // with this row's expansion instead of snapping.
            withAnimation(appExpansionAnimation) {
                expansion.wrappedValue.toggle()
            }
        }
        VStack(alignment: .leading, spacing: 0) {
            AppHeaderToggle(action: toggleExpansion) {
                ToolHeaderRow(
                    tool: tool,
                    isExpanded: expansion.wrappedValue,
                    bottomPadding: headerBottomPadding
                )
                    .background {
                        headerCenterPreference(bottomPadding: headerBottomPadding)
                    }
            }

            if expansion.wrappedValue {
                ToolDetails(tool: tool)
                    .padding(.top, transcriptToolExpandedContentTopSpacing)
                    .padding(.bottom, toolExpandedContentBottomSpacing)
                    .padding(.leading, transcriptToolDetailLeadingInset)
                    .padding(.trailing, transcriptToolDetailTrailingInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appExpansionAnimationOverride(value: expansion.wrappedValue)
    }

    private var expansionBinding: Binding<Bool> {
        externalIsExpanded ?? $localIsExpanded
    }

    @ViewBuilder
    private func headerCenterPreference(bottomPadding: CGFloat) -> some View {
        if let headerPreferenceID {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TranscriptNestedRowCenterPreferenceKey.self,
                    value: [
                        headerPreferenceID: transcriptToolHeaderVisualCenter(
                            in: proxy.frame(in: .named(transcriptNestedRowsCoordinateSpace)),
                            bottomPadding: bottomPadding
                        )
                    ]
                )
            }
        }
    }
}

func transcriptToolHeaderVisualCenter(in frame: CGRect, bottomPadding: CGFloat) -> CGFloat {
    frame.midY + (transcriptToolRowVerticalPadding - bottomPadding) / 2
}

let transcriptNestedRowsCoordinateSpace = "TranscriptNestedRowsCoordinateSpace"

struct TranscriptNestedRowCenterPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

struct TranscriptNestedToolRows: View {
    let tools: [ToolEntry]

    var body: some View {
        TranscriptElbowStack(rowIDs: tools.map(\.id)) {
            ForEach(tools) { tool in
                InlineToolRow(tool: tool, headerPreferenceID: tool.id)
            }
        }
    }
}

struct TranscriptElbowStack<Content: View>: View {
    let rowIDs: [String]
    let content: Content

    init(rowIDs: [String], @ViewBuilder content: () -> Content) {
        self.rowIDs = rowIDs
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: transcriptToolNestedRowSpacing) {
            content
        }
        .padding(.top, transcriptToolNestedTopSpacing)
        .padding(.leading, transcriptToolNestedRowLeadingInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: transcriptNestedRowsCoordinateSpace)
        .overlayPreferenceValue(TranscriptNestedRowCenterPreferenceKey.self) { centersByID in
            TranscriptElbowConnector(rowIDs: rowIDs, centersByID: centersByID)
        }
    }
}

private struct TranscriptElbowConnector: View {
    let rowIDs: [String]
    let centersByID: [String: CGFloat]

    var body: some View {
        Path { path in
            let centers = rowIDs.compactMap { centersByID[$0] }
            guard !centers.isEmpty,
                  let lastCenter = centers.last else {
                return
            }

            let verticalX = transcriptToolIconFrameSize / 2
            let horizontalEndX = transcriptToolNestedRowLeadingInset - transcriptToolElbowGap
            path.move(to: CGPoint(x: verticalX, y: transcriptToolNestedTopSpacing))
            path.addLine(to: CGPoint(x: verticalX, y: lastCenter))

            for center in centers {
                path.move(to: CGPoint(x: verticalX, y: center))
                path.addLine(to: CGPoint(x: horizontalEndX, y: center))
            }
        }
        .stroke(Color.secondary.opacity(transcriptToolConnectorOpacity), lineWidth: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
