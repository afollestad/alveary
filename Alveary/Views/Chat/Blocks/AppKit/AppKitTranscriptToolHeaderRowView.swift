@preconcurrency import AppKit
import Foundation

private let appKitToolGroupStatusIndicatorDebounce: Duration = .milliseconds(250)
private let appKitToolStatusSpinnerSize: CGFloat = 12

@MainActor
final class AppKitTranscriptToolHeaderRowView: NSView {
    struct Configuration: Equatable {
        let summary: String
        let leadingIcon: TranscriptToolLeadingIconKind
        let phase: ToolStatusPhase
        let debounceStatus: Bool
        let typography: TranscriptTypography
        let bottomPadding: CGFloat

        init(
            summary: String,
            leadingIcon: TranscriptToolLeadingIconKind,
            phase: ToolStatusPhase,
            debounceStatus: Bool = false,
            typography: TranscriptTypography = TranscriptTypography(),
            bottomPadding: CGFloat = transcriptToolRowVerticalPadding
        ) {
            self.summary = summary
            self.leadingIcon = leadingIcon
            self.phase = phase
            self.debounceStatus = debounceStatus
            self.typography = typography
            self.bottomPadding = bottomPadding
        }
    }

    var onToggle: (() -> Void)?
    var onHeightInvalidated: (() -> Void)?

    private let iconView = AppKitDynamicTintImageView()
    private let summaryField = NSTextField(labelWithString: "")
    private let statusView = AppKitTranscriptToolStatusIndicatorView()
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
        updateIcon()
        summaryField.attributedStringValue = TranscriptToolSummaryFormatter.nsAttributedString(
            configuration.summary,
            typography: configuration.typography
        )
        statusView.configure(
            phase: configuration.phase,
            debounceTerminal: configuration.debounceStatus,
            typography: configuration.typography
        )
        updateAccessibility(for: configuration)
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func mouseDown(with event: NSEvent) {
        if onToggle != nil {
            onToggle?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onToggle else {
            return false
        }
        onToggle()
        return true
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        iconView.translatesAutoresizingMaskIntoConstraints = true
        iconView.wantsLayer = true
        summaryField.translatesAutoresizingMaskIntoConstraints = true
        summaryField.lineBreakMode = .byTruncatingMiddle
        summaryField.maximumNumberOfLines = 1
        statusView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(iconView)
        addSubview(summaryField)
        addSubview(statusView)
    }

    private func updateAccessibility(for configuration: Configuration) {
        setAccessibilityRole(onToggle == nil ? .group : .button)
        setAccessibilityLabel(configuration.summary)
        setAccessibilityValue(accessibilityValue(for: configuration.leadingIcon))
    }

    private func updateIcon() {
        guard let configuration else {
            return
        }
        iconView.image = NSImage(systemSymbolName: systemSymbolName(for: configuration.leadingIcon), accessibilityDescription: nil)
        iconView.setDynamicContentTintColor(.labelColor)
        iconView.symbolConfiguration = .init(pointSize: configuration.typography.size(for: .toolIcon), weight: .regular)
        iconView.layer?.setAffineTransform(CGAffineTransform(rotationAngle: rotationRadians(for: configuration.leadingIcon)))
    }

    private func layoutContent() {
        guard let configuration else {
            return
        }
        let contentY = transcriptToolRowVerticalPadding
        let contentHeight = max(
            transcriptToolIconFrameSize,
            ceil(summaryField.fittingSize.height),
            transcriptToolStatusFrameSize
        )
        iconView.frame = NSRect(
            x: 0,
            y: contentY + ((contentHeight - transcriptToolIconFrameSize) / 2),
            width: transcriptToolIconFrameSize,
            height: transcriptToolIconFrameSize
        )

        let statusX = max(
            transcriptToolIconTextSpacing,
            min(
                transcriptToolIconTextSpacing + ceil(summaryField.fittingSize.width) + transcriptToolTextStatusSpacing,
                bounds.width - transcriptToolStatusFrameSize
            )
        )
        let summaryWidth = max(statusX - transcriptToolIconTextSpacing - transcriptToolTextStatusSpacing, 0)
        summaryField.frame = NSRect(
            x: transcriptToolIconTextSpacing,
            y: contentY + ((contentHeight - ceil(summaryField.fittingSize.height)) / 2),
            width: summaryWidth,
            height: ceil(summaryField.fittingSize.height)
        )
        statusView.frame = NSRect(
            x: statusX,
            y: contentY + ((contentHeight - transcriptToolStatusFrameSize) / 2),
            width: transcriptToolStatusFrameSize,
            height: transcriptToolStatusFrameSize
        )

        frame.size.height = measuredHeight(for: configuration)
    }

    private func measuredHeight() -> CGFloat {
        guard let configuration else {
            return 0
        }
        return measuredHeight(for: configuration)
    }

    private func measuredHeight(for configuration: Configuration) -> CGFloat {
        transcriptToolRowVerticalPadding
            + max(transcriptToolIconFrameSize, ceil(summaryField.fittingSize.height), transcriptToolStatusFrameSize)
            + configuration.bottomPadding
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

    private func systemSymbolName(for kind: TranscriptToolLeadingIconKind) -> String {
        switch kind {
        case .disclosure(let isExpanded):
            // Use the native down-chevron instead of rotating the right-chevron
            // layer. Layer rotation changes the drawn bounds and can make the
            // expanded caret appear to jump toward the transcript edge.
            return isExpanded ? "chevron.down" : "chevron.right"
        case .bash:
            return "dollarsign"
        case .symbol(let systemName):
            return systemName
        }
    }

    private func rotationRadians(for kind: TranscriptToolLeadingIconKind) -> CGFloat {
        switch kind {
        case .disclosure:
            return 0
        case .bash, .symbol:
            return 0
        }
    }

    private func accessibilityValue(for kind: TranscriptToolLeadingIconKind) -> String? {
        switch kind {
        case .disclosure(let isExpanded):
            return isExpanded ? "expanded" : "collapsed"
        case .bash, .symbol:
            return nil
        }
    }
}

@MainActor
final class AppKitTranscriptToolStatusIndicatorView: NSView {
    private let symbolView = AppKitDynamicTintImageView()
    private let spinnerView = AppKitStatusIndicatorSpinner(lineWidth: 1.5)
    private var phase: ToolStatusPhase?
    private var displayedPhase: ToolStatusPhase?
    private var typography = TranscriptTypography()
    private var pendingTask: Task<Void, Never>?
    private var pendingPhaseVersion = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    deinit {
        pendingTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        phase: ToolStatusPhase,
        debounceTerminal: Bool = false,
        typography: TranscriptTypography = TranscriptTypography()
    ) {
        let typographyChanged = self.typography != typography
        self.typography = typography
        updateSymbolConfiguration()

        guard self.phase != phase else {
            if typographyChanged {
                needsLayout = true
            }
            return
        }
        self.phase = phase
        pendingTask?.cancel()
        pendingTask = nil
        pendingPhaseVersion &+= 1
        guard displayedPhase != nil, debounceTerminal, phase.isTerminal else {
            apply(phase: phase)
            return
        }

        let phaseVersion = pendingPhaseVersion
        pendingTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: appKitToolGroupStatusIndicatorDebounce)
            } catch {
                return
            }

            guard let self,
                  phaseVersion == self.pendingPhaseVersion else {
                return
            }
            self.apply(phase: phase)
            self.pendingTask = nil
        }
    }

    private func apply(phase: ToolStatusPhase) {
        displayedPhase = phase
        switch phase {
        case .loading:
            symbolView.isHidden = true
            spinnerView.isHidden = false
        case .success:
            spinnerView.isHidden = true
            symbolView.isHidden = false
            symbolView.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
            symbolView.setDynamicContentTintColor(.systemGreen)
        case .error:
            spinnerView.isHidden = true
            symbolView.isHidden = false
            symbolView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
            symbolView.setDynamicContentTintColor(.systemRed)
        }
    }

    override func layout() {
        super.layout()
        let frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        symbolView.frame = frame
        let spinnerInsetX = max((bounds.width - appKitToolStatusSpinnerSize) / 2, 0)
        let spinnerInsetY = max((bounds.height - appKitToolStatusSpinnerSize) / 2, 0)
        spinnerView.frame = bounds.insetBy(dx: spinnerInsetX, dy: spinnerInsetY)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        symbolView.translatesAutoresizingMaskIntoConstraints = true
        spinnerView.translatesAutoresizingMaskIntoConstraints = true
        updateSymbolConfiguration()
        spinnerView.isHidden = true
        addSubview(symbolView)
        addSubview(spinnerView)
    }

    private func updateSymbolConfiguration() {
        symbolView.symbolConfiguration = .init(pointSize: typography.size(for: .toolStatusIcon), weight: .regular)
    }
}

#if DEBUG
extension AppKitTranscriptToolStatusIndicatorView {
    var statusSymbolPointSizeForTesting: CGFloat {
        typography.size(for: .toolStatusIcon)
    }
}
#endif
