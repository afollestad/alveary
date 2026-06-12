@preconcurrency import AppKit

@MainActor
final class AppKitTranscriptPromptUsageDetailsView: NSView {
    struct Configuration: Equatable {
        let prompt: PromptEntry
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?

    private let connectorView = AppKitTranscriptElbowConnectorView()
    private var responseRows: [AppKitTranscriptPromptUsageResponseView] = []
    private var fallbackField: NSTextField?
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
        rebuild()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    private func rebuild() {
        responseRows.forEach { $0.removeFromSuperview() }
        fallbackField?.removeFromSuperview()
        responseRows = []
        fallbackField = nil

        guard let configuration,
              let summary = configuration.prompt.submittedSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else {
            return
        }

        let responses = SubmittedPromptResponse.parse(from: summary)
        if responses.isEmpty {
            let field = NSTextField(labelWithString: summary)
            field.translatesAutoresizingMaskIntoConstraints = true
            field.lineBreakMode = .byWordWrapping
            field.maximumNumberOfLines = 0
            field.font = configuration.typography.nsFont(.body)
            field.textColor = .tertiaryLabelColor
            addSubview(field)
            fallbackField = field
            connectorView.isHidden = true
        } else {
            connectorView.isHidden = false
            responseRows = responses.map { response in
                let row = AppKitTranscriptPromptUsageResponseView()
                row.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
                row.configure(.init(response: response, typography: configuration.typography))
                addSubview(row)
                return row
            }
        }
    }

    private func layoutContent() {
        let metrics = transcriptInlineToolRowMetrics(for: configuration?.typography ?? TranscriptTypography())
        connectorView.metrics = metrics
        connectorView.frame = bounds

        if let fallbackField {
            fallbackField.frame = NSRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: appKitPromptWrappedTextHeight(for: fallbackField, width: bounds.width)
            )
            connectorView.centers = []
            return
        }

        let rowLeadingInset = metrics.detailLeadingInset
        let rowWidth = max(bounds.width - rowLeadingInset, 0)
        var currentY = transcriptToolNestedTopSpacing
        for row in responseRows {
            row.frame = NSRect(
                x: rowLeadingInset,
                y: currentY,
                width: rowWidth,
                height: CGFloat.greatestFiniteMagnitude / 2
            )
            row.layoutSubtreeIfNeeded()
            row.frame.size.height = row.intrinsicContentSize.height
            currentY = row.frame.maxY + promptSubmittedPairSpacing
        }
        connectorView.centers = responseRows.map { $0.frame.minY + $0.questionCenterY }
    }

    private func measuredHeight() -> CGFloat {
        if let fallbackField {
            let width = fallbackField.frame.width > 0 ? fallbackField.frame.width : bounds.width
            return ceil(appKitPromptWrappedTextHeight(for: fallbackField, width: width))
        }
        guard !responseRows.isEmpty else {
            return 0
        }
        let rowsHeight = responseRows.reduce(CGFloat.zero) { $0 + ceil($1.intrinsicContentSize.height) }
        return transcriptToolNestedTopSpacing + rowsHeight + CGFloat(responseRows.count - 1) * promptSubmittedPairSpacing
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
private final class AppKitTranscriptPromptUsageResponseView: NSView {
    struct Configuration: Equatable {
        let response: SubmittedPromptResponse
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?

    private let questionField = NSTextField(labelWithString: "")
    private let answerField = NSTextField(labelWithString: "")
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

    var questionCenterY: CGFloat {
        questionField.frame.midY
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        questionField.stringValue = configuration.response.question
        questionField.font = configuration.typography.nsFont(.subheadline)
        questionField.textColor = .secondaryLabelColor
        answerField.stringValue = configuration.response.answer
        answerField.font = configuration.typography.nsFont(.body)
        answerField.textColor = .tertiaryLabelColor
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        let questionHeight = appKitPromptWrappedTextHeight(for: questionField, width: bounds.width)
        questionField.frame = NSRect(x: 0, y: 0, width: bounds.width, height: questionHeight)
        let answerHeight = appKitPromptWrappedTextHeight(for: answerField, width: bounds.width)
        answerField.frame = NSRect(x: 0, y: questionField.frame.maxY + 2, width: bounds.width, height: answerHeight)
        frame.size.height = measuredHeight()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        [questionField, answerField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            $0.lineBreakMode = .byWordWrapping
            $0.maximumNumberOfLines = 0
            addSubview($0)
        }
    }

    private func measuredHeight() -> CGFloat {
        let width = bounds.width > 0 ? bounds.width : 320
        return ceil(
            appKitPromptWrappedTextHeight(for: questionField, width: width)
                + 2
                + appKitPromptWrappedTextHeight(for: answerField, width: width)
        )
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
}
