@preconcurrency import AppKit

extension AppKitTranscriptTextBubbleRowView {
    func layoutMetrics(for configuration: Configuration) -> TextBubbleLayoutMetrics {
        let maxWidth = maxBubbleWidth(for: configuration, availableWidth: max(bounds.width, 0))
        let imageStripFrame = imageStripFrame(for: configuration, maxWidth: maxWidth)

        guard configuration.hasBubbleContent else {
            return TextBubbleLayoutMetrics(
                imageStripFrame: imageStripFrame,
                bubbleFrame: .zero,
                hasBubble: false,
                markdownClipFrame: .zero,
                markdownFrame: .zero,
                overflows: false,
                isCollapsed: false
            )
        }

        let width = bubbleWidth(for: configuration)
        let markdownWidth = max(width - (chatBubbleHorizontalPadding * 2), 0)
        let fullMarkdownHeight = preparedMarkdownMeasurement(for: markdownWidth)?.contentHeight
            ?? measuredMarkdownHeight(for: markdownWidth)
        let overflows = isOverflowing(markdownHeight: fullMarkdownHeight)
        let visibleMarkdownHeight = overflows && !isExpanded ? min(fullMarkdownHeight, collapsedMaxHeight) : fullMarkdownHeight
        let toggleHeight = overflows ? max(textBubbleToggleMinHeight, ceil(expansionButton.fittingSize.height)) : 0
        let height = visibleMarkdownHeight + (chatBubbleVerticalPadding * 2) +
            (overflows ? textBubbleControlClearance + textBubbleControlSpacing + toggleHeight : 0)
        let originX = configuration.role == .user ? max(bounds.width - width, 0) : 0
        let bubbleY = if let imageStripFrame {
            imageStripFrame.maxY + textBubbleImageStripBubbleSpacing
        } else {
            CGFloat(0)
        }
        return TextBubbleLayoutMetrics(
            imageStripFrame: imageStripFrame,
            bubbleFrame: NSRect(x: originX, y: bubbleY, width: width, height: height),
            hasBubble: true,
            markdownClipFrame: NSRect(
                x: chatBubbleHorizontalPadding,
                y: chatBubbleVerticalPadding,
                width: markdownWidth,
                height: visibleMarkdownHeight
            ),
            markdownFrame: NSRect(x: 0, y: 0, width: markdownWidth, height: fullMarkdownHeight),
            overflows: overflows,
            isCollapsed: overflows && !isExpanded
        )
    }

    func imageStripFrame(for configuration: Configuration, maxWidth: CGFloat) -> NSRect? {
        let imageStripSize = imageAttachmentStripView.measuredSize(constrainedTo: maxWidth)
        guard imageStripSize != .zero else {
            return nil
        }
        return NSRect(
            x: configuration.role == .user ? max(bounds.width - imageStripSize.width, 0) : 0,
            y: 0,
            width: imageStripSize.width,
            height: imageStripSize.height
        )
    }

    func applyBubbleLayout(_ metrics: TextBubbleLayoutMetrics) {
        imageAttachmentStripView.isHidden = metrics.imageStripFrame == nil
        bubbleView.isHidden = !metrics.hasBubble
        markdownClipView.isHidden = !metrics.hasBubble
        markdownView?.isHidden = !metrics.hasBubble
        if !metrics.overflows {
            expansionButton.frame = .zero
        }
        applyFrameUpdates(frameUpdates(for: metrics), animated: false)
        guard metrics.hasBubble else {
            updateCollapsedFadeMask(isCollapsed: false)
            return
        }
        if let markdownView {
            markdownView.maximumImageDisplayWidth = metrics.markdownFrame.width
            validateHydratedMarkdownHeight(markdownView, metrics: metrics)
        }
        updateCollapsedFadeMask(isCollapsed: metrics.isCollapsed)
    }

    func expansionButtonFrame(markdownClipFrame: NSRect) -> NSRect {
        let buttonSize = expansionButton.fittingSize
        return NSRect(
            x: chatBubbleHorizontalPadding,
            // SwiftUI stacked the 8pt content clearance and 4pt VStack spacing
            // above Show more/less, leaving only the normal bubble padding below it.
            y: markdownClipFrame.maxY + textBubbleControlClearance + textBubbleControlSpacing,
            width: ceil(buttonSize.width),
            height: max(textBubbleToggleMinHeight, ceil(buttonSize.height))
        )
    }

    func measuredMarkdownHeight(for markdownWidth: CGFloat) -> CGFloat {
        hydrateMarkdownIfNeeded()
        // Measure against the current content height rather than an arbitrary
        // giant probe frame. Some AppKit markdown children pin to their container
        // for width/layout, and a huge temporary height can leak into the rendered
        // bubble before the transcript container caches the row height.
        let measurementHeight = max(markdownView?.intrinsicContentSize.height ?? 0, 120)
        markdownView?.maximumImageDisplayWidth = markdownWidth
        markdownView?.frame = NSRect(x: 0, y: 0, width: markdownWidth, height: measurementHeight)
        markdownView?.layoutSubtreeIfNeeded()
        return markdownView?.intrinsicContentSize.height ?? 0
    }

    func bubbleWidth(for configuration: Configuration) -> CGFloat {
        guard configuration.hasBubbleContent else {
            return 0
        }
        let availableWidth = max(bounds.width, 0)
        let maxWidth = maxBubbleWidth(for: configuration, availableWidth: availableWidth)

        // SwiftUI used `.frame(maxWidth:)`, so short bubbles hugged their
        // rendered markdown and only grew to the cap when text needed to wrap.
        let maxContentWidth = max(maxWidth - (chatBubbleHorizontalPadding * 2), 0)
        let naturalContentWidth = preparedMarkdownMeasurement(for: maxContentWidth)?.naturalContentWidth
            ?? naturalMarkdownWidth(constrainedTo: maxContentWidth)
        let naturalBubbleWidth = naturalContentWidth + (chatBubbleHorizontalPadding * 2)
        return min(max(naturalBubbleWidth, 0), maxWidth)
    }

    func maxBubbleWidth(for configuration: Configuration, availableWidth: CGFloat) -> CGFloat {
        switch configuration.role {
        case .user:
            return min(userBubbleMaxWidth, max(availableWidth - userBubbleLeadingClearance, 0))
        case .assistant:
            return min(max(configuration.bubbleMaxWidth.isFinite ? configuration.bubbleMaxWidth : availableWidth, 0), availableWidth)
        }
    }

    func preparedMarkdownMeasurement(for markdownWidth: CGFloat) -> AppKitMarkdownLayoutMeasurement? {
        guard let configuration, !forceHydratedMarkdownMeasurement else {
            return nil
        }
        let context = preparedMeasurementContext(for: markdownWidth, configuration: configuration)
        if let cached = TextBubblePreparedMeasurement.cachedMeasurement(for: context.key) {
            return cached
        }
        scheduleAsyncMarkdownPreparation(for: context)
        if asyncPreparedMarkdown?.key == context.key, let document = asyncPreparedMarkdown?.document {
            return TextBubblePreparedMeasurement.measurement(context, document: document)
        }
        return TextBubblePreparedMeasurement.measurement(context, document: document(for: configuration))
    }

    func naturalMarkdownWidth(constrainedTo maxContentWidth: CGFloat) -> CGFloat {
        hydrateMarkdownIfNeeded()
        guard let markdownView else {
            return 0
        }

        let textWidths = markdownView.transcriptMarkdownTextViews.map { textView in
            textView.transcriptNaturalTextWidth(constrainedTo: maxContentWidth)
        }
        let viewWidths = markdownView.transcriptNonTextMarkdownViews.map { view in
            if let tableView = view as? AppKitMarkdownTableView {
                return tableView.naturalViewportWidth(constrainedTo: maxContentWidth)
            }
            return view.fittingSize.width
        }
        return ceil(max((textWidths + viewWidths).max() ?? 0, 0))
    }
}
