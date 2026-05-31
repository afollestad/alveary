@preconcurrency import AppKit
import Foundation

/// AppKit question card used inside prompt blocks, responsible for question
/// text, answer rows, custom-response editing, and local height invalidation.
@MainActor
final class AppKitTranscriptPromptQuestionCardView: NSView {
    struct Configuration: Equatable {
        let index: Int
        let question: PromptEntry.PromptQuestion
        let selections: Set<String>
        let customResponse: String
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?
    var onToggleOption: ((Int, PromptEntry.PromptOption) -> Void)?
    var onCustomResponseChanged: ((Int, String) -> Void)?

    private let backgroundView = AppKitFlippedDynamicColorView()
    private let headerField = NSTextField(labelWithString: "")
    private let questionField = NSTextField(labelWithString: "")
    var optionRows: [AppKitPromptOptionRowView] = []
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
        self.configuration = configuration
        rebuild()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    func updateSelectionState(selections: Set<String>, customResponse: String) -> Bool {
        guard let configuration,
              optionRows.count == configuration.question.renderedOptions.count else {
            return false
        }
        self.configuration = Configuration(
            index: configuration.index,
            question: configuration.question,
            selections: selections,
            customResponse: customResponse,
            typography: configuration.typography
        )
        for (row, option) in zip(optionRows, configuration.question.renderedOptions) {
            row.updateSelectionState(
                isSelected: selections.contains(option.id),
                customResponse: customResponse
            )
        }
        needsLayout = true
        return true
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = promptBlockCornerRadius
        addSubview(backgroundView)
        [headerField, questionField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            $0.lineBreakMode = .byWordWrapping
            $0.maximumNumberOfLines = 0
            backgroundView.addSubview($0)
        }
        updateBackground()
    }

    private func rebuild() {
        guard let configuration else {
            return
        }
        headerField.stringValue = configuration.question.header ?? ""
        headerField.isHidden = (configuration.question.header ?? "").isEmpty
        headerField.font = configuration.typography.nsFont(.caption, weight: .semibold)
        headerField.textColor = .labelColor
        questionField.stringValue = configuration.question.question
        questionField.font = configuration.typography.nsFont(.subheadline, weight: .semibold)
        questionField.textColor = .labelColor

        optionRows.forEach { $0.removeFromSuperview() }
        optionRows = configuration.question.renderedOptions.map { option in
            let row = AppKitPromptOptionRowView()
            row.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
            row.onToggle = { [weak self] in
                guard let self, let configuration = self.configuration else {
                    return
                }
                self.onToggleOption?(configuration.index, option)
            }
            row.onCustomResponseChanged = { [weak self] value in
                guard let self, let configuration = self.configuration else {
                    return
                }
                self.onCustomResponseChanged?(configuration.index, value)
            }
            row.configure(
                .init(
                    question: configuration.question,
                    option: option,
                    isSelected: configuration.selections.contains(option.id),
                    customResponse: configuration.customResponse,
                    typography: configuration.typography
                )
            )
            backgroundView.addSubview(row)
            return row
        }
    }

    private func layoutContent() {
        guard configuration != nil else {
            return
        }
        backgroundView.frame = bounds
        let contentWidth = max(bounds.width - (promptQuestionCardPadding * 2), 0)
        var currentY = promptQuestionCardPadding
        if !headerField.isHidden {
            headerField.frame = wrappedHeaderFrame(originY: currentY, width: contentWidth)
            currentY = headerField.frame.maxY + 12
        }

        questionField.frame = wrappedTextFrame(for: questionField, originX: promptQuestionCardPadding, originY: currentY, width: contentWidth)
        currentY = questionField.frame.maxY + 12

        for row in optionRows {
            row.frame = NSRect(x: 0, y: currentY, width: bounds.width, height: CGFloat.greatestFiniteMagnitude / 2)
            row.layoutSubtreeIfNeeded()
            row.frame.size.height = row.intrinsicContentSize.height
            currentY = row.frame.maxY + promptOptionRowSpacing
        }
        if !optionRows.isEmpty {
            currentY -= promptOptionRowSpacing
        }
        backgroundView.frame.size.height = currentY + promptQuestionCardPadding
        frame.size.height = backgroundView.frame.height
    }

    private func measuredHeight() -> CGFloat {
        if backgroundView.frame.height > 0, backgroundView.frame.height < CGFloat.greatestFiniteMagnitude / 4 {
            return ceil(backgroundView.frame.height)
        }
        let optionHeight = optionRows.reduce(CGFloat.zero) { $0 + $1.intrinsicContentSize.height }
        let optionSpacing = optionRows.isEmpty ? 0 : CGFloat(optionRows.count - 1) * promptOptionRowSpacing
        return ceil((promptQuestionCardPadding * 2) + questionFieldHeight + 12 + optionHeight + optionSpacing)
    }

    private var questionFieldHeight: CGFloat {
        let contentWidth = max(bounds.width - (promptQuestionCardPadding * 2), 0)
        return appKitPromptWrappedTextHeight(for: questionField, width: contentWidth)
    }

    private func wrappedHeaderFrame(originY: CGFloat, width: CGFloat) -> NSRect {
        let naturalWidth = min(headerField.fittingSize.width + 16, width)
        let height = appKitPromptWrappedTextHeight(for: headerField, width: max(naturalWidth - 16, 0)) + 8
        return NSRect(x: promptQuestionCardPadding, y: originY, width: naturalWidth, height: height)
    }

    private func wrappedTextFrame(for field: NSTextField, originX: CGFloat, originY: CGFloat, width: CGFloat) -> NSRect {
        NSRect(x: originX, y: originY, width: width, height: appKitPromptWrappedTextHeight(for: field, width: width))
    }

    private func updateBackground() {
        backgroundView.setLayerFillColor(.secondaryLabelColor, alpha: 0.06)
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

/// One selectable answer row inside an AppKit prompt question card.
@MainActor
final class AppKitPromptOptionRowView: NSView, NSTextFieldDelegate {
    struct Configuration: Equatable {
        let question: PromptEntry.PromptQuestion
        let option: PromptEntry.PromptOption
        let isSelected: Bool
        let customResponse: String
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?
    var onToggle: (() -> Void)?
    var onCustomResponseChanged: ((String) -> Void)?

    let rowButton = AppKitPromptOptionHitButton()
    let button = NSButton()
    let titleField = NSTextField(labelWithString: "")
    private let descriptionField = NSTextField(labelWithString: "")
    let customField = NSTextField(string: "")
    var configuration: Configuration?
    private var lastMeasuredHeight: CGFloat = -1
    private var isPressed = false

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
        self.configuration = configuration
        button.setButtonType(configuration.question.multiSelect ? .switch : .radio)
        button.state = configuration.isSelected ? .on : .off
        button.setAccessibilityLabel(configuration.option.label)
        button.setAccessibilityHelp(configuration.option.description.isEmpty ? nil : configuration.option.description)
        let replacesTextWithCustomField = configuration.option.isCustomResponse && configuration.isSelected
        titleField.stringValue = configuration.option.label
        titleField.font = configuration.typography.nsFont(.subheadline, weight: .medium)
        titleField.isHidden = replacesTextWithCustomField
        descriptionField.stringValue = configuration.option.description
        descriptionField.font = configuration.typography.nsFont(.caption)
        descriptionField.isHidden = replacesTextWithCustomField || configuration.option.description.isEmpty
        customField.stringValue = configuration.customResponse
        customField.isHidden = !replacesTextWithCustomField
        if replacesTextWithCustomField { focusCustomFieldOnNextPass() }
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    func updateSelectionState(isSelected: Bool, customResponse: String) {
        guard let configuration else {
            return
        }
        let wasCustomFieldVisible = !customField.isHidden
        let updatedConfiguration = Configuration(
            question: configuration.question,
            option: configuration.option,
            isSelected: isSelected,
            customResponse: customResponse,
            typography: configuration.typography
        )
        self.configuration = updatedConfiguration
        button.state = isSelected ? .on : .off
        let showsCustomField = configuration.option.isCustomResponse && isSelected
        titleField.isHidden = showsCustomField
        descriptionField.isHidden = showsCustomField || configuration.option.description.isEmpty
        customField.stringValue = customResponse
        customField.isHidden = !showsCustomField
        if showsCustomField, !wasCustomFieldVisible { focusCustomFieldOnNextPass() }
        needsLayout = true
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePressedAppearance()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === customField else {
            return
        }
        onCustomResponseChanged?(customField.stringValue)
        invalidateTranscriptHeight(force: false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        rowButton.translatesAutoresizingMaskIntoConstraints = true
        rowButton.target = self
        rowButton.action = #selector(handleRowButtonPreview)
        rowButton.onPressedChanged = { [weak self] isPressed in
            self?.setPressed(isPressed)
        }
        rowButton.onReleased = { [weak self] releasedInside in
            self?.finishTogglePreview(releasedInside: releasedInside)
        }
        // The row button sits above static labels for full-width clicks, then below
        // the custom text field so selected Other rows can still edit text.
        rowButton.setAccessibilityElement(false)
        button.translatesAutoresizingMaskIntoConstraints = true
        button.title = ""
        button.target = self
        // Keep the native control committing directly for keyboard and
        // accessibility activation; the overlay handles mouse press preview.
        button.action = #selector(handleNativeButtonToggle)
        addSubview(button)
        [titleField, descriptionField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            $0.lineBreakMode = .byWordWrapping
            $0.maximumNumberOfLines = 0
            addSubview($0)
        }
        addSubview(rowButton)
        customField.translatesAutoresizingMaskIntoConstraints = true
        customField.placeholderString = "Enter your response"
        customField.delegate = self
        addSubview(customField)
        updatePressedAppearance()
    }

    private func focusCustomFieldOnNextPass() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.customField.isHidden else { return }
            self.window?.makeFirstResponder(self.customField)
        }
    }

    private func layoutContent() {
        let buttonSize = NSSize(width: 20, height: 20)
        let glyphX = promptQuestionCardPadding
        let textX = glyphX + buttonSize.width + promptOptionGlyphTextSpacing
        let textWidth = max(bounds.width - textX - promptQuestionCardPadding, 0)
        var currentY = promptOptionRowVerticalPadding
        if !titleField.isHidden {
            titleField.frame = wrappedTextFrame(for: titleField, originX: textX, originY: currentY, width: textWidth)
            currentY = titleField.frame.maxY
        }
        if !descriptionField.isHidden {
            let descriptionY = titleField.isHidden ? currentY : currentY + 4
            descriptionField.frame = wrappedTextFrame(for: descriptionField, originX: textX, originY: descriptionY, width: textWidth)
            currentY = descriptionField.frame.maxY
        }
        if !customField.isHidden {
            let height = reservedTextHeight(width: textWidth)
            customField.frame = NSRect(
                x: textX,
                y: currentY + max((height - promptOptionCustomFieldHeight) / 2, 0),
                width: textWidth,
                height: promptOptionCustomFieldHeight
            )
            currentY += height
        }
        let contentHeight = max(buttonSize.height + (promptOptionRowVerticalPadding * 2), currentY + promptOptionRowVerticalPadding)
        let glyphCenterY = contentHeight / 2
        button.frame = NSRect(x: glyphX, y: glyphCenterY - (buttonSize.height / 2), width: buttonSize.width, height: buttonSize.height)
        rowButton.frame = NSRect(x: 0, y: 0, width: bounds.width, height: contentHeight)
    }

    private func measuredHeight() -> CGFloat {
        let buttonSize = NSSize(width: 20, height: 20)
        let textWidth = max(
            bounds.width - promptQuestionCardPadding - buttonSize.width - promptOptionGlyphTextSpacing - promptQuestionCardPadding,
            0
        )
        let textHeight = customField.isHidden ? visibleTextHeight() : reservedTextHeight(width: textWidth)
        return ceil(max(20, textHeight) + (promptOptionRowVerticalPadding * 2))
    }

    private func visibleTextHeight() -> CGFloat {
        let buttonSize = NSSize(width: 20, height: 20)
        let textWidth = max(bounds.width - promptQuestionCardPadding - buttonSize.width - promptOptionGlyphTextSpacing - promptQuestionCardPadding, 0)
        let titleHeight = titleField.isHidden ? 0 : appKitPromptWrappedTextHeight(for: titleField, width: textWidth)
        let descriptionHeight = descriptionField.isHidden ? 0 : (titleHeight == 0 ? 0 : 4) + appKitPromptWrappedTextHeight(
            for: descriptionField,
            width: textWidth
        )
        return titleHeight + descriptionHeight
    }

    private func reservedTextHeight(width: CGFloat) -> CGFloat {
        guard let configuration else {
            return promptOptionCustomFieldHeight
        }
        // Selecting Other swaps label/description for the field, but must keep the
        // original row height so transcript anchors do not jump on selection.
        let title = appKitPromptWrappedTextHeight(
            configuration.option.label,
            font: configuration.typography.nsFont(.subheadline, weight: .medium),
            width: width
        )
        let description = configuration.option.description.isEmpty ? 0 :
            4 + appKitPromptWrappedTextHeight(
                configuration.option.description,
                font: configuration.typography.nsFont(.caption),
                width: width
            )
        return max(promptOptionCustomFieldHeight, title + description)
    }

    private func wrappedTextFrame(for field: NSTextField, originX: CGFloat, originY: CGFloat, width: CGFloat) -> NSRect {
        NSRect(x: originX, y: originY, width: width, height: appKitPromptWrappedTextHeight(for: field, width: width))
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

    @objc private func handleRowButtonPreview() {
        previewToggle()
    }

    @objc private func handleNativeButtonToggle() {
        onToggle?()
    }

    func previewToggle() {
        guard let configuration else {
            return
        }
        if configuration.question.multiSelect {
            button.state = configuration.isSelected ? .off : .on
        } else {
            button.state = .on
        }
    }

    func finishTogglePreview(releasedInside: Bool) {
        guard releasedInside else {
            resetSelectionPreview()
            return
        }
        onToggle?()
    }

    private func resetSelectionPreview() {
        guard let configuration else {
            return
        }
        button.state = configuration.isSelected ? .on : .off
    }

    func setPressed(_ pressed: Bool) {
        guard isPressed != pressed else {
            return
        }
        isPressed = pressed
        updatePressedAppearance()
    }

    private func updatePressedAppearance() {
        layer?.backgroundColor = isPressed ?
            NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.10).cgColor :
            nil
    }
}

private let promptOptionCustomFieldHeight: CGFloat = 24
private let promptOptionGlyphTextSpacing: CGFloat = 8
private let promptOptionRowSpacing: CGFloat = 4
private let promptOptionRowVerticalPadding: CGFloat = 4
