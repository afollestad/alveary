import AppKit

@MainActor
extension AppKitTranscriptToolHeaderRowView {
    func layoutContent() {
        guard let configuration else {
            return
        }
        let metrics = transcriptInlineToolRowMetrics(for: configuration.typography)
        let rowWidth = effectiveRowWidth(for: configuration)
        let leadingTextInset = configuration.showsLeadingIcon ? metrics.leadingTextInset : 0
        let trailingStatusWidth = configuration.showsStatusSlot ? metrics.textStatusSpacing + metrics.controlSize : 0
        let availableSummaryWidth = max(rowWidth - leadingTextInset - trailingStatusWidth, 0)
        let summarySize = measuredSummarySize(maxWidth: availableSummaryWidth, configuration: configuration)
        let contentY = transcriptInlineToolRowVerticalPadding
        let slotHeight = configuration.showsLeadingIcon || configuration.showsStatusSlot ? metrics.controlSize : 0
        let contentHeight = max(slotHeight, summarySize.height)

        if configuration.showsLeadingIcon {
            iconView.frame = NSRect(
                x: 0,
                y: contentY + ((contentHeight - metrics.controlSize) / 2),
                width: metrics.controlSize,
                height: metrics.controlSize
            )
        } else {
            iconView.frame = .zero
        }

        summaryField.frame = NSRect(
            x: leadingTextInset,
            y: contentY + ((contentHeight - summarySize.height) / 2),
            width: summarySize.width,
            height: summarySize.height
        )
        summaryPulseField.frame = summaryField.frame
        summaryPulseMask.frame = summaryPulseField.bounds

        if configuration.showsStatusSlot {
            let statusX = max(0, min(
                leadingTextInset + summarySize.width + metrics.textStatusSpacing + appKitTranscriptToolStatusSlotTextOffset,
                rowWidth - metrics.controlSize
            ))
            statusView.frame = NSRect(
                x: statusX,
                y: contentY + ((contentHeight - metrics.controlSize) / 2),
                width: metrics.controlSize,
                height: metrics.controlSize
            )
        } else {
            statusView.frame = .zero
        }

        frame.size.height = measuredHeight(for: configuration)
        restartSummaryPulseIfNeeded()
    }

    func effectiveRowWidth(for configuration: Configuration) -> CGFloat {
        let availableWidth = max(bounds.width, 0)
        let cap = configuration.maxWidth.isFinite ? configuration.maxWidth : availableWidth
        return min(max(cap, 0), availableWidth)
    }

    func updateSummaryLineMode(for configuration: Configuration) {
        let wraps = configuration.summaryMaximumNumberOfLines != 1
        for field in [summaryField, summaryPulseField] {
            field.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingMiddle
            field.maximumNumberOfLines = configuration.summaryMaximumNumberOfLines
        }
    }

    func measuredSummarySize(maxWidth: CGFloat, configuration: Configuration) -> CGSize {
        let summaryWidth = measuredSummaryWidth(maxWidth: maxWidth, configuration: configuration)
        guard summaryWidth > 0 else {
            return .zero
        }
        return CGSize(
            width: summaryWidth,
            height: measuredSummaryHeight(width: summaryWidth, configuration: configuration)
        )
    }

    func measuredSummaryWidth(maxWidth: CGFloat, configuration: Configuration) -> CGFloat {
        guard maxWidth > 0 else {
            return 0
        }
        let naturalWidth = ceil(summaryField.fittingSize.width)
        let proposedWidth = min(naturalWidth, maxWidth)
        guard configuration.summaryMaximumNumberOfLines == 1 else {
            return proposedWidth
        }
        let proposedBounds = NSRect(x: 0, y: 0, width: proposedWidth, height: ceil(summaryField.fittingSize.height))
        let cellWidth = summaryField.cell.map { ceil($0.cellSize(forBounds: proposedBounds).width) } ?? proposedWidth
        return min(max(cellWidth, 0), proposedWidth)
    }

    func measuredSummaryHeight(width: CGFloat, configuration: Configuration) -> CGFloat {
        guard width > 0 else {
            return 0
        }
        guard configuration.summaryMaximumNumberOfLines != 1 else {
            return ceil(summaryField.fittingSize.height)
        }
        let bounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)
        let cellHeight = summaryField.cell.map { ceil($0.cellSize(forBounds: bounds).height) }
        return max(cellHeight ?? ceil(summaryField.fittingSize.height), 0)
    }

    func measuredHeight() -> CGFloat {
        guard let configuration else {
            return 0
        }
        return measuredHeight(for: configuration)
    }

    func measuredHeight(for configuration: Configuration) -> CGFloat {
        let metrics = transcriptInlineToolRowMetrics(for: configuration.typography)
        let rowWidth = effectiveRowWidth(for: configuration)
        let leadingTextInset = configuration.showsLeadingIcon ? metrics.leadingTextInset : 0
        let trailingStatusWidth = configuration.showsStatusSlot ? metrics.textStatusSpacing + metrics.controlSize : 0
        let availableSummaryWidth = max(rowWidth - leadingTextInset - trailingStatusWidth, 0)
        let summaryHeight = measuredSummarySize(maxWidth: availableSummaryWidth, configuration: configuration).height
        let slotHeight = configuration.showsLeadingIcon || configuration.showsStatusSlot ? metrics.controlSize : 0
        return transcriptInlineToolRowVerticalPadding
            + max(slotHeight, summaryHeight)
            + configuration.bottomPadding
    }

    func invalidateTranscriptHeight(force: Bool) {
        let newHeight = measuredHeight()
        guard force || abs(newHeight - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = newHeight
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    // Keep this switch exhaustive so new semantic icon cases cannot silently fall back to a generic glyph.
    // swiftlint:disable:next cyclomatic_complexity
    func systemSymbolName(for kind: TranscriptToolLeadingIconKind) -> String {
        switch kind {
        case .terminal:
            return "terminal"
        case .search:
            return "magnifyingglass"
        case .folder:
            return "folder"
        case .read:
            return "magnifyingglass"
        case .book:
            return "book"
        case .document:
            return "doc.text"
        case .edit:
            return "pencil"
        case .write:
            return "pencil"
        case .skill:
            return "book"
        case .checklist:
            return "checklist"
        case .question:
            return "questionmark"
        case .subAgent:
            return "hat.widebrim"
        case .toolGroup:
            return "wrench.and.screwdriver"
        case .genericTool:
            return "gearshape"
        }
    }
}
