@preconcurrency import AppKit

private typealias Metrics = AppKitComposerOverlayMetrics

@MainActor
final class AppKitComposerOverlayOptionRowView: NSView, NSTextFieldDelegate {
    struct Configuration {
        let id: String
        let indexText: String
        let title: String
        let description: String?
        let helpText: String?
        let isSelected: Bool
        let showsSelectedChip: Bool
        let isFocused: Bool
        let isEnabled: Bool
        let customPlaceholder: String?
        let customText: String
        let fontSize: CGFloat
        let fontWeight: NSFont.Weight
        let minimumHeight: CGFloat
        let verticalPadding: CGFloat
        let customFieldHeight: CGFloat
        let usesInlineCustomPlaceholder: Bool
        let onSelect: () -> Void
        let onSubmitSelection: (() -> Void)?
        let onCustomTextChanged: (String) -> Void

        init(
            id: String,
            indexText: String,
            title: String,
            description: String? = nil,
            helpText: String? = nil,
            isSelected: Bool = false,
            showsSelectedChip: Bool = false,
            isFocused: Bool = false,
            isEnabled: Bool = true,
            customPlaceholder: String? = nil,
            customText: String = "",
            fontSize: CGFloat = 14,
            fontWeight: NSFont.Weight = .semibold,
            minimumHeight: CGFloat = Metrics.optionMinimumHeight,
            verticalPadding: CGFloat = Metrics.optionVerticalPadding,
            customFieldHeight: CGFloat = Metrics.customFieldHeight,
            usesInlineCustomPlaceholder: Bool = false,
            onSelect: @escaping () -> Void,
            onSubmitSelection: (() -> Void)? = nil,
            onCustomTextChanged: @escaping (String) -> Void = { _ in }
        ) {
            self.id = id
            self.indexText = indexText
            self.title = title
            self.description = description
            self.helpText = helpText
            self.isSelected = isSelected
            self.showsSelectedChip = showsSelectedChip
            self.isFocused = isFocused
            self.isEnabled = isEnabled
            self.customPlaceholder = customPlaceholder
            self.customText = customText
            self.fontSize = fontSize
            self.fontWeight = fontWeight
            self.minimumHeight = minimumHeight
            self.verticalPadding = verticalPadding
            self.customFieldHeight = customFieldHeight
            self.usesInlineCustomPlaceholder = usesInlineCustomPlaceholder
            self.onSelect = onSelect
            self.onSubmitSelection = onSubmitSelection
            self.onCustomTextChanged = onCustomTextChanged
        }
    }

    var onPreferredSizeInvalidated: (() -> Void)?
    var onKeyEvent: ((NSEvent) -> Bool)?
    var onCustomSubmit: (() -> Void)?
    var onCustomCancel: (() -> Void)?

    let indexField = NSTextField(labelWithString: "")
    let titleField = NSTextField(labelWithString: "")
    let descriptionField = NSTextField(labelWithString: "")
    let selectedChipView = AppKitComposerOverlaySelectedChipView()
    let infoButton = AppKitComposerOverlayInfoButton()
    let customField = AppKitComposerOverlayCustomTextField(string: "")
    private var configuration: Configuration?
    var trackingArea: NSTrackingArea?
    var isHovering = false
    var isPressed = false

    var configurationID: String {
        configuration?.id ?? ""
    }

    var configurationIsFocused: Bool {
        configuration?.isFocused == true
    }

    var containsKeyboardFocus: Bool {
        guard let firstResponder = window?.firstResponder else {
            return false
        }
        return firstResponder === self ||
            firstResponder === customField ||
            customField.currentEditor() === firstResponder ||
            (firstResponder as? NSView)?.isDescendant(of: self) == true
    }

    var keyViewSequence: [NSView] {
        customField.isHidden ? [self] : [customField]
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    func configure(_ configuration: Configuration) {
        self.configuration = configuration
        let showsInlineCustomPlaceholder = configuration.usesInlineCustomPlaceholder &&
            configuration.customPlaceholder != nil &&
            !configuration.isSelected &&
            configuration.customText.isEmpty
        indexField.stringValue = configuration.indexText
        titleField.stringValue = showsInlineCustomPlaceholder ? (configuration.customPlaceholder ?? "") : configuration.title
        titleField.isHidden = configuration.customPlaceholder != nil && !showsInlineCustomPlaceholder
        indexField.font = .systemFont(ofSize: configuration.fontSize, weight: configuration.fontWeight)
        titleField.font = .systemFont(ofSize: configuration.fontSize, weight: configuration.fontWeight)
        customField.font = .systemFont(ofSize: configuration.fontSize)
        titleField.textColor = showsInlineCustomPlaceholder ? .secondaryLabelColor : .labelColor
        descriptionField.stringValue = configuration.description ?? ""
        descriptionField.isHidden = (configuration.description ?? "").isEmpty ||
            configuration.customPlaceholder != nil ||
            showsInlineCustomPlaceholder
        infoButton.isHidden = (configuration.helpText ?? "").isEmpty ||
            configuration.customPlaceholder != nil ||
            showsInlineCustomPlaceholder
        infoButton.configure(helpText: configuration.helpText)
        selectedChipView.isHidden = !configuration.showsSelectedChip
        customField.isHidden = configuration.customPlaceholder == nil || showsInlineCustomPlaceholder
        customField.placeholderString = configuration.customPlaceholder
        if customField.currentEditor() == nil,
           customField.stringValue != configuration.customText {
            customField.stringValue = configuration.customText
        }
        alphaValue = configuration.isEnabled ? 1 : 0.58
        resetInteractionStateIfNeeded(isEnabled: configuration.isEnabled)
        let accessibilityTitle = titleField.stringValue.isEmpty ? (configuration.customPlaceholder ?? configuration.title) : titleField.stringValue
        setAccessibilityLabel("\(configuration.indexText) \(accessibilityTitle)")
        setAccessibilityHelp(configuration.helpText ?? configuration.description)
        needsDisplay = true
        needsLayout = true
        onPreferredSizeInvalidated?()

        if configuration.customPlaceholder != nil,
           configuration.isSelected,
           window != nil,
           !containsKeyboardFocus {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.configuration?.id == configuration.id,
                      !self.containsKeyboardFocus else {
                    return
                }
                self.focusPreferredTarget()
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard configuration?.isEnabled == true else {
            return
        }
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            performSelectionFromKeyboard()
            return
        }
        if event.specialKey == .carriageReturn {
            performSubmitSelectionFromKeyboard()
            return
        }
        if onKeyEvent?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard configuration?.isEnabled == true else {
            return
        }
        window?.makeFirstResponder(self)
        isPressed = true
        needsDisplay = true
        let releasedInside = trackPressedStateUntilMouseUp()
        isPressed = false
        needsDisplay = true
        if releasedInside {
            if configuration?.customPlaceholder != nil {
                focusPreferredTarget()
            } else {
                configuration?.onSelect()
            }
        }
    }

    override func layout() {
        super.layout()
        let contentWidth = bounds.width
        let titleX = Metrics.optionTextX
        let textWidth = max(contentWidth - titleX - Metrics.optionPadding - accessoryWidth, 0)
        layoutIndexAndTextFields(titleX: titleX, textWidth: textWidth)
        if !customField.isHidden {
            let customFieldHeight = configuration?.customFieldHeight ?? Metrics.customFieldHeight
            customField.frame = NSRect(
                x: titleX,
                y: floor((bounds.height - customFieldHeight) / 2),
                width: max(contentWidth - titleX - Metrics.optionPadding, 0),
                height: customFieldHeight
            )
        }
        layoutAccessories()
    }

    private var accessoryWidth: CGFloat {
        var width: CGFloat = 0
        if !selectedChipView.isHidden {
            width += selectedChipView.measuredWidth + Metrics.accessorySpacing
        }
        return width
    }

    private func layoutIndexAndTextFields(titleX: CGFloat, textWidth: CGFloat) {
        let titleWidth = titleTextWidth(for: textWidth)
        let titleHeight = titleField.isHidden ? 0 : appKitPromptWrappedTextHeight(for: titleField, width: titleWidth)
        let descriptionHeight = descriptionField.isHidden ? 0 : appKitPromptWrappedTextHeight(for: descriptionField, width: textWidth)
        let textBlockHeight = titleHeight + (descriptionField.isHidden ? 0 : Metrics.descriptionSpacing + descriptionHeight)
        let verticalPadding = configuration?.verticalPadding ?? Metrics.optionVerticalPadding
        let textBlockY = textBlockHeight > 0 ? floor((bounds.height - textBlockHeight) / 2) : verticalPadding
        let indexHeight = indexField.fittingSize.height
        let indexY = textBlockHeight > 0 ? textBlockY : floor((bounds.height - indexHeight) / 2)
        indexField.frame = NSRect(
            x: Metrics.optionPadding,
            y: indexY,
            width: Metrics.indexWidth,
            height: indexHeight
        )

        var currentY = textBlockY
        if titleField.isHidden {
            titleField.frame = .zero
        } else {
            titleField.frame = NSRect(
                x: titleX,
                y: currentY,
                width: titleWidth,
                height: titleHeight
            )
            layoutInfoButton(titleX: titleX, titleWidth: titleWidth)
            currentY = titleField.frame.maxY
        }
        if !descriptionField.isHidden {
            currentY += Metrics.descriptionSpacing
            descriptionField.frame = NSRect(
                x: titleX,
                y: currentY,
                width: textWidth,
                height: descriptionHeight
            )
            currentY = descriptionField.frame.maxY
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let configuration else {
            return
        }
        let path = NSBezierPath(roundedRect: bounds, xRadius: Metrics.optionCornerRadius, yRadius: Metrics.optionCornerRadius)
        if configuration.isSelected {
            NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.12).setFill()
            path.fill()
        } else if isPressed {
            NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.10).setFill()
            path.fill()
        } else if isHovering {
            NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.07).setFill()
            path.fill()
        }
        if containsKeyboardFocus || configuration.isFocused {
            AppAccentFill.primaryNSColor.appKitResolvedColor(in: self).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === customField else { return }
        configuration?.onCustomTextChanged(customField.stringValue)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard notification.object as AnyObject? === customField else { return }
        configuration?.onSelect()
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as AnyObject? === customField else { return }
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === customField else {
            return false
        }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            onCustomSubmit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCustomCancel?()
            return true
        case #selector(NSResponder.moveUp(_:)):
            sendSyntheticKeyEvent(characters: "\u{F700}", keyCode: 126)
            return true
        case #selector(NSResponder.moveDown(_:)):
            sendSyntheticKeyEvent(characters: "\u{F701}", keyCode: 125)
            return true
        default:
            return false
        }
    }

    private func revealCustomFieldForFocus() {
        guard let configuration,
              configuration.customPlaceholder != nil,
              customField.isHidden else {
            return
        }
        titleField.isHidden = true
        descriptionField.isHidden = true
        infoButton.isHidden = true
        customField.isHidden = false
        needsLayout = true
        onPreferredSizeInvalidated?()
    }

    private func titleTextWidth(for textWidth: CGFloat) -> CGFloat {
        guard !infoButton.isHidden else { return textWidth }
        return max(textWidth - Metrics.inlineInfoSpacing - Metrics.infoButtonSize, 0)
    }

    private func layoutInfoButton(titleX: CGFloat, titleWidth: CGFloat) {
        guard !infoButton.isHidden else {
            infoButton.frame = .zero
            return
        }
        let titleNaturalWidth = ceil(titleField.attributedStringValue.size().width)
        let iconX = titleX + min(titleNaturalWidth, titleWidth) + Metrics.inlineInfoSpacing
        infoButton.frame = NSRect(
            x: iconX,
            y: floor(titleField.frame.midY - (Metrics.infoButtonSize / 2)),
            width: Metrics.infoButtonSize,
            height: Metrics.infoButtonSize
        )
    }

    private func beginCustomFieldEditing() {
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(customField)
        customField.selectText(nil)
        guard let editor = customField.currentEditor() as? NSTextView else { return }
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    }

    private var customFieldHeight: CGFloat {
        configuration?.customFieldHeight ?? Metrics.customFieldHeight
    }
}
extension AppKitComposerOverlayOptionRowView {
    func measuredHeight(width: CGFloat) -> CGFloat {
        let textWidth = max(width - Metrics.optionTextX - Metrics.optionPadding - accessoryWidth, 0)
        let titleWidth = titleTextWidth(for: textWidth)
        let titleHeight = titleField.isHidden ? 0 : appKitPromptWrappedTextHeight(for: titleField, width: titleWidth)
        let descriptionHeight = descriptionField.isHidden ? 0 :
            Metrics.descriptionSpacing + appKitPromptWrappedTextHeight(for: descriptionField, width: textWidth)
        let reservesInlineCustomHeight = configuration?.customPlaceholder != nil && configuration?.usesInlineCustomPlaceholder == true
        let customHeight = customField.isHidden && !reservesInlineCustomHeight ? 0 : customFieldHeight
        let verticalPadding = configuration?.verticalPadding ?? Metrics.optionVerticalPadding
        let minimumHeight = configuration?.minimumHeight ?? Metrics.optionMinimumHeight
        let contentHeight = reservesInlineCustomHeight ?
            max(titleHeight + descriptionHeight, customHeight) :
            titleHeight + descriptionHeight + customHeight
        let naturalHeight = verticalPadding * 2 + contentHeight
        return ceil(max(minimumHeight, naturalHeight))
    }

    func performSelectionFromKeyboard() {
        guard configuration?.isEnabled == true else {
            return
        }
        if configuration?.customPlaceholder != nil {
            focusPreferredTarget()
            return
        }
        configuration?.onSelect()
    }

    func performSubmitSelectionFromKeyboard() {
        guard configuration?.isEnabled == true else {
            return
        }
        if let onSubmitSelection = configuration?.onSubmitSelection {
            onSubmitSelection()
            return
        }
        performSelectionFromKeyboard()
    }

    private func sendSyntheticKeyEvent(characters: String, keyCode: UInt16) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            return
        }
        _ = onKeyEvent?(event)
    }

    func focusPreferredTarget() {
        guard configuration?.isEnabled == true else {
            return
        }
        if configuration?.customPlaceholder != nil {
            configuration?.onSelect()
            revealCustomFieldForFocus()
            beginCustomFieldEditing()
            return
        }
        window?.makeFirstResponder(self)
    }

    private func resetInteractionStateIfNeeded(isEnabled: Bool) {
        guard !isEnabled else {
            return
        }
        isHovering = false
        isPressed = false
    }
}

#if DEBUG
extension AppKitComposerOverlayOptionRowView {
    var isHoveringForTesting: Bool {
        isHovering
    }
}
#endif
