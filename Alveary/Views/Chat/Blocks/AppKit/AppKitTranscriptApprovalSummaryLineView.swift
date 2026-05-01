@preconcurrency import AppKit
import Foundation

struct AppKitTranscriptApprovalSummaryItem: Equatable {
    let summary: String
    let isCommand: Bool
}

@MainActor
final class AppKitTranscriptApprovalSummaryLineView: NSView {
    private let field = AppKitDynamicColorTextField(labelWithString: "")
    private var item: AppKitTranscriptApprovalSummaryItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = true
        field.lineBreakMode = .byTruncatingMiddle
        field.maximumNumberOfLines = 1
        field.wantsLayer = true
        addSubview(field)
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

    var naturalWidth: CGFloat {
        guard let item else {
            return 0
        }
        let horizontalPadding = item.isCommand ? approvalCommandChipHPadding : 0
        return ceil(field.fittingSize.width + (horizontalPadding * 2))
    }

    func configure(_ item: AppKitTranscriptApprovalSummaryItem, typography: TranscriptTypography) {
        self.item = item
        field.stringValue = item.summary
        field.textColor = .secondaryLabelColor
        field.font = item.isCommand ? typography.codeNSFont : typography.nsFont(.approvalBody)
        field.layer?.cornerRadius = item.isCommand ? approvalCommandChipCornerRadius : 0
        field.setLayerFillColor(item.isCommand ? .secondaryLabelColor : nil, alpha: 0.16)
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        guard let item else {
            return
        }
        let horizontalPadding = item.isCommand ? approvalCommandChipHPadding : 0
        let verticalPadding = item.isCommand ? approvalCommandChipVPadding : 0
        let height = measuredHeight()
        field.frame = NSRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: max(bounds.width - (horizontalPadding * 2), 0),
            height: max(height - (verticalPadding * 2), 0)
        )
    }

    private func measuredHeight() -> CGFloat {
        guard let item else {
            return 0
        }
        let verticalPadding = item.isCommand ? approvalCommandChipVPadding : 0
        return ceil(field.fittingSize.height + (verticalPadding * 2))
    }
}
