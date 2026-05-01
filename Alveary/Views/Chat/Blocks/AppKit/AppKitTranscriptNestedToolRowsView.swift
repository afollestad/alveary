@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptNestedToolRowsView: NSView {
    struct Configuration: Equatable {
        let tools: [ToolEntry]
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            rowViews.forEach { $0.onOpenMarkdownLink = onOpenMarkdownLink }
        }
    }

    private let connectorView = AppKitTranscriptElbowConnectorView()
    private var rowViews: [AppKitTranscriptInlineToolRowView] = []
    private var rowViewsByToolID: [String: AppKitTranscriptInlineToolRowView] = [:]
    private var configuration: Configuration?
    private var lastMeasuredHeight: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(connectorView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight())
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        let liveToolIDs = Set(configuration.tools.map(\.id))
        rowViewsByToolID = rowViewsByToolID.filter { toolID, row in
            if liveToolIDs.contains(toolID) {
                return true
            }
            row.removeFromSuperview()
            return false
        }
        // Keep child views keyed by tool id so local child expansion survives
        // parent group refreshes while tool output or status streams in.
        rowViews = configuration.tools.map { tool in
            let row = rowViewsByToolID[tool.id] ?? AppKitTranscriptInlineToolRowView()
            rowViewsByToolID[tool.id] = row
            row.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
            row.onOpenMarkdownLink = onOpenMarkdownLink
            row.configure(.init(tool: tool, typography: configuration.typography))
            if row.superview == nil {
                addSubview(row)
            }
            return row
        }
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        var currentY = transcriptToolNestedTopSpacing
        let rowWidth = max(bounds.width - transcriptToolNestedRowLeadingInset, 0)
        for row in rowViews {
            row.frame = NSRect(
                x: transcriptToolNestedRowLeadingInset,
                y: currentY,
                width: rowWidth,
                height: CGFloat.greatestFiniteMagnitude / 2
            )
            row.layoutSubtreeIfNeeded()
            row.frame.size.height = row.intrinsicContentSize.height
            currentY = row.frame.maxY + transcriptToolNestedRowSpacing
        }
        connectorView.frame = bounds
        connectorView.centers = rowViews.map { $0.frame.minY + $0.headerVisualCenterY }
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    private func measuredHeight() -> CGFloat {
        guard !rowViews.isEmpty else {
            return 0
        }
        let rowHeights = rowViews.reduce(CGFloat.zero) { partialResult, row in
            partialResult + ceil(row.frame.height > 0 ? row.frame.height : row.intrinsicContentSize.height)
        }
        return transcriptToolNestedTopSpacing + rowHeights + CGFloat(rowViews.count - 1) * transcriptToolNestedRowSpacing
    }

    private func invalidateTranscriptHeight(force: Bool) {
        let newHeight = measuredHeight()
        guard force || abs(newHeight - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = newHeight
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    private func childHeightInvalidated() {
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }
}

@MainActor
private final class AppKitTranscriptElbowConnectorView: NSView {
    var centers: [CGFloat] = [] {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let lastCenter = centers.last else {
            return
        }

        NSColor.secondaryLabelColor.withAlphaComponent(transcriptToolConnectorOpacity).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        let verticalX = transcriptToolIconFrameSize / 2
        let horizontalEndX = transcriptToolNestedRowLeadingInset - transcriptToolElbowGap
        path.move(to: CGPoint(x: verticalX, y: transcriptToolNestedTopSpacing))
        path.line(to: CGPoint(x: verticalX, y: lastCenter))
        for center in centers {
            path.move(to: CGPoint(x: verticalX, y: center))
            path.line(to: CGPoint(x: horizontalEndX, y: center))
        }
        path.stroke()
    }
}
