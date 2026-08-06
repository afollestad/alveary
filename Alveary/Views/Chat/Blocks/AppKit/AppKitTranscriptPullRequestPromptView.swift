@preconcurrency import AppKit

/// Which action each split control will run when its primary half is clicked.
/// The menus only ever change this — they never act, matching the split-button
/// rule in `Views/Components/AGENTS.md`.
struct PullRequestLinkPromptSelection: Equatable {
    var acceptsAlways = false
    var declinesForever = false
}

/// Asks whether a pull request found in the message above should be linked to the
/// thread. Rendered as its own row beneath that message's bubble, aligned with it.
@MainActor
final class AppKitTranscriptPullRequestPromptView: NSView {
    enum Alignment: Equatable {
        case leading
        case trailing
    }

    struct Configuration: Equatable {
        let promptID: String
        let displayKey: String
        let alignment: Alignment
        let selection: PullRequestLinkPromptSelection
        let maxWidth: CGFloat
        let typography: TranscriptTypography
    }

    var onAccept: ((_ always: Bool) -> Void)?
    var onDecline: ((_ never: Bool) -> Void)?
    var onSelectionChanged: ((PullRequestLinkPromptSelection) -> Void)?
    var onHeightInvalidated: (() -> Void)?

    private let promptLabel = NSTextField(labelWithString: "")
    private let acceptControl = AppKitTranscriptApprovalSplitControl()
    private let declineControl = AppKitTranscriptApprovalSplitControl()
    private var configuration: Configuration?
    private var lastMeasuredHeight: CGFloat = -1

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
        updateAppearance()
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
        updateAppearance()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        promptLabel.translatesAutoresizingMaskIntoConstraints = true
        promptLabel.lineBreakMode = .byTruncatingMiddle
        promptLabel.maximumNumberOfLines = 1
        addSubview(promptLabel)

        configureControl(acceptControl, icon: .system("checkmark"), style: .primary, action: #selector(handleAcceptControl))
        configureControl(declineControl, icon: .system("xmark"), style: .secondary, action: #selector(handleDeclineControl))
    }

    private func configureControl(
        _ control: AppKitTranscriptApprovalSplitControl,
        icon: ActionIcon,
        style: AppKitTranscriptApprovalButtonStyle,
        action: Selector
    ) {
        control.translatesAutoresizingMaskIntoConstraints = true
        control.segmentCount = 2
        control.trackingMode = .momentary
        control.controlSize = .small
        control.primaryIcon = icon
        control.actionStyle = style
        control.target = self
        control.action = action
        addSubview(control)
    }

    private func updateAppearance() {
        guard let configuration else {
            return
        }
        promptLabel.font = configuration.typography.nsFont(.approvalBody)
        promptLabel.textColor = transcriptInlineToolRowColor
        promptLabel.stringValue = "Link \(configuration.displayKey) to this thread?"
        promptLabel.setAccessibilityLabel(promptLabel.stringValue)

        // A bare "Yes" says nothing on its own, so the spoken label names the action
        // and its pull request even though the button face stays short.
        applyControlTitle(
            acceptControl,
            title: configuration.selection.acceptsAlways ? "Always" : "Yes",
            accessibilityLabel: configuration.selection.acceptsAlways
                ? "Always link pull requests, starting with \(configuration.displayKey)"
                : "Link \(configuration.displayKey)"
        )
        applyControlTitle(
            declineControl,
            title: configuration.selection.declinesForever ? "Never" : "No",
            accessibilityLabel: configuration.selection.declinesForever
                ? "Never ask about linking pull requests"
                : "Do not link \(configuration.displayKey)"
        )
    }

    private func applyControlTitle(
        _ control: AppKitTranscriptApprovalSplitControl,
        title: String,
        accessibilityLabel: String
    ) {
        control.setLabel(title, forSegment: 0)
        control.setAccessibilityLabel(accessibilityLabel)
        control.setWidth(max(control.preferredContentWidth, 58), forSegment: 0)
        control.setWidth(AppKitTranscriptApprovalSplitControl.menuWidth, forSegment: 1)
        control.frame.size = control.fittingSize
    }

    private func layoutContent() {
        let contentWidth = min(max(bounds.width, 0), configuration?.maxWidth ?? bounds.width)
        let controlsWidth = acceptControl.frame.width + controlSpacing + declineControl.frame.width
        let labelWidth = max(min(labelNaturalWidth(), contentWidth - controlsWidth - controlSpacing), 0)
        let rowWidth = min(labelWidth + controlSpacing + controlsWidth, contentWidth)
        let originX = configuration?.alignment == .trailing ? max(bounds.width - rowWidth, 0) : 0
        let rowHeight = max(acceptControl.frame.height, declineControl.frame.height)

        promptLabel.frame = NSRect(
            x: originX,
            y: verticalPadding + ((rowHeight - promptLabel.fittingSize.height) / 2),
            width: labelWidth,
            height: promptLabel.fittingSize.height
        )
        acceptControl.frame.origin = NSPoint(x: promptLabel.frame.maxX + controlSpacing, y: verticalPadding)
        declineControl.frame.origin = NSPoint(x: acceptControl.frame.maxX + controlSpacing, y: verticalPadding)
    }

    /// Measured against unconstrained bounds, not `fittingSize`, so a pass that
    /// truncated the label cannot feed a narrower width into the next one.
    private func labelNaturalWidth() -> CGFloat {
        let unconstrainedBounds = NSRect(
            x: 0,
            y: 0,
            width: CGFloat.greatestFiniteMagnitude / 2,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        return ceil(promptLabel.cell?.cellSize(forBounds: unconstrainedBounds).width ?? promptLabel.fittingSize.width)
    }

    private func measuredHeight() -> CGFloat {
        let controlHeight = max(acceptControl.fittingSize.height, declineControl.fittingSize.height)
        return ceil((verticalPadding * 2) + max(controlHeight, promptLabel.fittingSize.height))
    }

    @objc private func handleAcceptControl() {
        switch acceptControl.selectedSegment {
        case 0:
            onAccept?(configuration?.selection.acceptsAlways == true)
        case 1:
            showAcceptMenu()
        default:
            break
        }
    }

    @objc private func handleDeclineControl() {
        switch declineControl.selectedSegment {
        case 0:
            onDecline?(configuration?.selection.declinesForever == true)
        case 1:
            showDeclineMenu()
        default:
            break
        }
    }

    private func showAcceptMenu() {
        let selection = configuration?.selection ?? PullRequestLinkPromptSelection()
        showMenu(
            anchoredTo: acceptControl,
            titles: ["Yes", "Always"],
            selectedIndex: selection.acceptsAlways ? 1 : 0,
            action: #selector(handleAcceptMenuItem(_:))
        )
    }

    private func showDeclineMenu() {
        let selection = configuration?.selection ?? PullRequestLinkPromptSelection()
        showMenu(
            anchoredTo: declineControl,
            titles: ["No", "Never"],
            selectedIndex: selection.declinesForever ? 1 : 0,
            action: #selector(handleDeclineMenuItem(_:))
        )
    }

    private func showMenu(
        anchoredTo control: NSView,
        titles: [String],
        selectedIndex: Int,
        action: Selector
    ) {
        let menu = NSMenu()
        for (index, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == selectedIndex ? .on : .off
            menu.addItem(item)
        }
        let origin = NSPoint(x: control.frame.maxX - 28, y: control.frame.maxY + 2)
        menu.popUp(positioning: nil, at: origin, in: self)
    }

    @objc private func handleAcceptMenuItem(_ item: NSMenuItem) {
        applySelectionChange { $0.acceptsAlways = item.tag == 1 }
    }

    @objc private func handleDeclineMenuItem(_ item: NSMenuItem) {
        applySelectionChange { $0.declinesForever = item.tag == 1 }
    }

    private func applySelectionChange(_ transform: (inout PullRequestLinkPromptSelection) -> Void) {
        guard let configuration else {
            return
        }
        var selection = configuration.selection
        transform(&selection)
        guard selection != configuration.selection else {
            return
        }
        self.configuration = Configuration(
            promptID: configuration.promptID,
            displayKey: configuration.displayKey,
            alignment: configuration.alignment,
            selection: selection,
            maxWidth: configuration.maxWidth,
            typography: configuration.typography
        )
        updateAppearance()
        onSelectionChanged?(selection)
        needsLayout = true
        invalidateTranscriptHeight(force: true)
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

    private var verticalPadding: CGFloat {
        transcriptToolRowVerticalPadding
    }

    private var controlSpacing: CGFloat {
        8
    }
}
