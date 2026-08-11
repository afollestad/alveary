@preconcurrency import AppKit

private typealias Metrics = AppKitComposerOverlayMetrics

extension AppKitComposerOverlayOptionRowView {
    func setup() {
        wantsLayer = true
        setAccessibilityRole(.button)
        [indexField, titleField, descriptionField].forEach {
            $0.lineBreakMode = .byWordWrapping
            $0.maximumNumberOfLines = 0
            addSubview($0)
        }
        addSubview(selectedChipView)
        indexField.font = .systemFont(ofSize: 14, weight: .semibold)
        indexField.textColor = .secondaryLabelColor
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .labelColor
        descriptionField.font = .systemFont(ofSize: 12)
        descriptionField.textColor = .secondaryLabelColor
        infoButton.isBordered = false
        infoButton.refusesFirstResponder = true
        addSubview(infoButton)
        customField.font = .systemFont(ofSize: 14)
        customField.cell = AppKitComposerOverlayCustomTextFieldCell(textCell: "")
        customField.textColor = .labelColor
        customField.placeholderAttributedString = nil
        customField.isEditable = true
        customField.isSelectable = true
        customField.cell?.isEditable = true
        customField.cell?.isSelectable = true
        customField.isBordered = false
        customField.isBezeled = false
        customField.drawsBackground = false
        customField.focusRingType = .none
        customField.delegate = self
        customField.setAccessibilityLabel("Custom response")
        addSubview(customField)
    }

    func layoutAccessories() {
        var currentX = bounds.width - Metrics.optionPadding
        if !selectedChipView.isHidden {
            let chipWidth = selectedChipView.measuredWidth
            currentX -= chipWidth
            selectedChipView.frame = NSRect(
                x: currentX,
                y: floor((bounds.height - Metrics.chipHeight) / 2),
                width: chipWidth,
                height: Metrics.chipHeight
            )
        }
    }

    func trackPressedStateUntilMouseUp() -> Bool {
        var isInside = true
        while let event = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = convert(event.locationInWindow, from: nil)
            isInside = bounds.contains(point)
            if event.type == .leftMouseUp {
                return isInside
            }
            let nextPressed = isInside
            if nextPressed != isPressed {
                isPressed = nextPressed
                needsDisplay = true
            }
        }
        return false
    }
}
