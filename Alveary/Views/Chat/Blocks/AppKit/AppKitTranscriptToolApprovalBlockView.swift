@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptToolApprovalBlockView: NSView {
    struct Configuration: Equatable {
        let approval: ToolApprovalRequest
        let approvals: [ToolApprovalRequest]
        let status: ToolApprovalStatus?
        let isBlocked: Bool
        let selectedApprovalSelection: ToolApprovalSelection
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            approval: ToolApprovalRequest,
            approvals: [ToolApprovalRequest]? = nil,
            status: ToolApprovalStatus?,
            isBlocked: Bool = false,
            selectedApprovalSelection: ToolApprovalSelection = .once,
            bubbleMaxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.approval = approval
            self.approvals = approvals ?? [approval]
            self.status = status
            self.isBlocked = isBlocked
            self.selectedApprovalSelection = selectedApprovalSelection
            self.bubbleMaxWidth = bubbleMaxWidth
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onApprove: (() -> Void)?
    var onApproveForSession: ((ToolApprovalSessionScope) -> Void)?
    var onDeny: (() -> Void)?
    var onSelectApprovalSelection: ((ToolApprovalSelection) -> Void)?

    let bubbleView = AppKitFlippedDynamicColorView()
    let iconView = AppKitDynamicTintImageView()
    let titleField = NSTextField(labelWithString: "")
    let approvalSplitControl = AppKitTranscriptApprovalSplitControl()
    let approveButton = AppKitTranscriptApprovalButton()
    let denyButton = AppKitTranscriptApprovalButton()
    var summaryViews: [AppKitTranscriptApprovalSummaryLineView] = []
    var configuration: Configuration?
    var selectedApprovalSelection: ToolApprovalSelection = .once
    var showsDenyInPrimarySlot = false
    var shouldAnimateActionsOnNextLayout = false
    var lastActionAnimationID: String?
    var pendingDenySlotAnimationStartFrame: NSRect?
    var pendingApprovePlaceholderFrame: NSRect?
    var activeDenySlotAnimationTargetFrame: NSRect?
    var activeApprovePlaceholderTargetFrame: NSRect?
    var denySlotAnimationGeneration = 0
    var approvePlaceholderAnimationGeneration = 0
    var lastMeasuredHeight: CGFloat = -1
#if DEBUG
    var lastDenySlotAnimationFrames: (from: NSRect, to: NSRect)?
    var lastApprovePlaceholderFrames: (from: NSRect, to: NSRect)?
    var didDeferDenySlotAnimation = false
    var didDeferPlaceholderAnimation = false
#endif

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
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
        let newActionAnimationID = configuration.status?.rawValue ?? "pending"
        let previousActionAnimationID = lastActionAnimationID
        shouldAnimateActionsOnNextLayout = previousActionAnimationID != nil && previousActionAnimationID != newActionAnimationID
        if shouldAnimateActionsOnNextLayout {
            denySlotAnimationGeneration += 1
            approvePlaceholderAnimationGeneration += 1
            activeDenySlotAnimationTargetFrame = nil
            activeApprovePlaceholderTargetFrame = nil
        }
        captureDenySlotAnimationStartFrameIfNeeded(
            previousActionAnimationID: previousActionAnimationID,
            newActionAnimationID: newActionAnimationID
        )
        lastActionAnimationID = newActionAnimationID
        selectedApprovalSelection = configuration.selectedApprovalSelection.normalized(for: sessionApprovalScopes(for: configuration))
        rebuildSummaryViews()
        updateHeader()
        updateActions()
        updateBubbleAppearance()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBubbleAppearance()
        updateSummaryAppearance()
    }
}

extension AppKitTranscriptToolApprovalBlockView {
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = chatBlockCornerRadius
        addSubview(bubbleView)

        iconView.translatesAutoresizingMaskIntoConstraints = true
        iconView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        iconView.setDynamicContentTintColor(.labelColor)
        titleField.translatesAutoresizingMaskIntoConstraints = true
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        bubbleView.addSubview(iconView)
        bubbleView.addSubview(titleField)

        configure(button: approveButton, action: #selector(handleApprove))
        approveButton.actionStyle = .primary
        configure(button: denyButton, action: #selector(handleDeny))
        denyButton.actionStyle = .secondary
        approvalSplitControl.translatesAutoresizingMaskIntoConstraints = true
        approvalSplitControl.trackingMode = .momentary
        approvalSplitControl.segmentCount = 2
        approvalSplitControl.target = self
        approvalSplitControl.action = #selector(handleApprovalSplitControl)
        approvalSplitControl.controlSize = .small
        bubbleView.addSubview(approvalSplitControl)
        bubbleView.addSubview(approveButton)
        bubbleView.addSubview(denyButton)
    }

    private func configure(button: NSButton, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = true
        button.isBordered = false
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.target = self
        button.action = action
    }

    private func rebuildSummaryViews() {
        summaryViews.forEach { $0.removeFromSuperview() }
        guard let configuration else {
            summaryViews = []
            return
        }
        summaryViews = summaryItems(for: configuration).map { item in
            let view = AppKitTranscriptApprovalSummaryLineView()
            view.configure(item, typography: configuration.typography)
            bubbleView.addSubview(view)
            return view
        }
    }

    private func updateHeader() {
        guard let configuration else {
            return
        }
        titleField.font = configuration.typography.nsFont(.toolSummary)
        titleField.textColor = .labelColor
        titleField.stringValue = ToolApprovalRequest.approvalPromptTitle(for: configuration.approvals)
        iconView.symbolConfiguration = .init(pointSize: configuration.typography.size(for: .toolIcon), weight: .regular)
    }

    private func updateActions() {
        guard let configuration else {
            return
        }
        let scopes = sessionApprovalScopes(for: configuration)
        selectedApprovalSelection = selectedApprovalSelection.normalized(for: scopes)
        updateApprovalSplitControl(scopes: scopes)
        let state = actionState(for: configuration, scopes: scopes)
        apply(state: state)
    }

    private func apply(state: ApprovalActionState) {
        approveButton.title = state.approveTitle
        approveButton.symbolName = state.approveSymbol
        approveButton.imagePosition = .imageLeading
        approveButton.imageHugsTitle = true
        approveButton.isEnabled = state.approveEnabled
        approveButton.isHidden = state.showSplitApproval
        approveButton.alphaValue = state.approvePlaceholder ? 0 : 1
        approveButton.setAccessibilityElement(!state.approvePlaceholder)
        approvalSplitControl.isHidden = !state.showSplitApproval
        approvalSplitControl.isEnabled = state.approveEnabled
        approvalSplitControl.alphaValue = state.approvePlaceholder ? 0 : 1
        approvalSplitControl.setAccessibilityElement(!state.approvePlaceholder)
        denyButton.title = state.denyTitle
        denyButton.symbolName = state.denySymbol
        denyButton.imagePosition = .imageLeading
        denyButton.imageHugsTitle = true
        denyButton.isEnabled = state.denyEnabled
        denyButton.isHidden = false
        denyButton.alphaValue = state.denyPlaceholder ? 0 : 1
        denyButton.setAccessibilityElement(!state.denyPlaceholder)
        showsDenyInPrimarySlot = state.showDenyInPrimarySlot
        approveButton.needsDisplay = true
        denyButton.needsDisplay = true
        approvalSplitControl.needsDisplay = true
    }

}
