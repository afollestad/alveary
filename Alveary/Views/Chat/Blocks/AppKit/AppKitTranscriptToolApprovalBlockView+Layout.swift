import AppKit
import QuartzCore

@MainActor
extension AppKitTranscriptToolApprovalBlockView {
    func layoutContent() {
        guard let configuration else {
            return
        }
        let width = bubbleWidth(for: configuration)
        bubbleView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)

        let contentX = chatBlockPadding
        let contentWidth = max(width - (chatBlockPadding * 2), 0)
        var currentY = chatVerticalPadding + transcriptToolRowVerticalPadding
        layoutHeader(originX: contentX, originY: currentY, width: contentWidth, typography: configuration.typography)
        currentY = titleField.frame.maxY

        if !summaryViews.isEmpty {
            currentY += toolApprovalSummaryTopSpacing
            for summaryView in summaryViews {
                let summaryWidth = min(summaryView.naturalWidth, max(contentWidth - transcriptToolDetailLeadingInset, 0))
                summaryView.frame = NSRect(
                    x: contentX + transcriptToolDetailLeadingInset,
                    y: currentY,
                    width: summaryWidth,
                    height: CGFloat.greatestFiniteMagnitude / 2
                )
                summaryView.layoutSubtreeIfNeeded()
                summaryView.frame.size.height = summaryView.intrinsicContentSize.height
                currentY = summaryView.frame.maxY + toolApprovalSummaryLineSpacing
            }
            currentY -= toolApprovalSummaryLineSpacing
        }

        currentY += toolApprovalActionsTopSpacing
        layoutActions(
            originX: contentX + transcriptToolDetailLeadingInset,
            originY: currentY,
            width: max(contentWidth - transcriptToolDetailLeadingInset, 0)
        )
        bubbleView.frame.size.height = ceil(
            max(approveButton.frame.maxY, approvalSplitControl.frame.maxY, denyButton.frame.maxY) + chatVerticalPadding
        )
    }

    func captureDenySlotAnimationStartFrameIfNeeded(previousActionAnimationID: String?, newActionAnimationID: String) {
        guard previousActionAnimationID != nil,
              previousActionAnimationID != newActionAnimationID,
              newActionAnimationID == ToolApprovalStatus.denied.rawValue || newActionAnimationID == ToolApprovalStatus.denying.rawValue,
              denyButton.frame != .zero else {
            pendingDenySlotAnimationStartFrame = nil
            pendingApprovePlaceholderFrame = nil
            return
        }
        pendingDenySlotAnimationStartFrame = denyButton.frame
        let approvalControl = approvalSplitControl.isHidden ? approveButton : approvalSplitControl
        pendingApprovePlaceholderFrame = approvalControl.frame == .zero ? nil : approvalControl.frame
    }

    func measuredHeight() -> CGFloat {
        if bubbleView.frame.height > 0, bubbleView.frame.height < CGFloat.greatestFiniteMagnitude / 4 {
            return ceil(bubbleView.frame.height)
        }
        let summaryHeight = summaryViews.reduce(CGFloat.zero) { partialResult, view in
            partialResult + ceil(view.intrinsicContentSize.height)
        }
        let summarySpacing = summaryViews.isEmpty ?
            0 :
            toolApprovalSummaryTopSpacing + (CGFloat(summaryViews.count - 1) * toolApprovalSummaryLineSpacing)
        let approvalHeight = approvalSplitControl.isHidden ? approveButton.fittingSize.height : approvalSplitControl.fittingSize.height
        let actionHeight = max(approvalHeight, denyButton.fittingSize.height)
        return ceil(
            chatVerticalPadding
                + transcriptToolRowVerticalPadding
                + transcriptToolIconFrameSize
                + summarySpacing
                + summaryHeight
                + toolApprovalActionsTopSpacing
                + actionHeight
                + chatVerticalPadding
        )
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

    func updateBubbleAppearance() {
        bubbleView.setLayerFillColor(.secondaryLabelColor, alpha: 0.08)
    }

    func updateSummaryAppearance() {
        guard let configuration else {
            return
        }
        for (view, item) in zip(summaryViews, summaryItems(for: configuration)) {
            view.configure(item, typography: configuration.typography)
        }
    }

    private func layoutHeader(originX: CGFloat, originY: CGFloat, width: CGFloat, typography: TranscriptTypography) {
        iconView.frame = NSRect(x: originX, y: originY, width: transcriptToolIconFrameSize, height: transcriptToolIconFrameSize)
        let titleHeight = ceil(titleField.fittingSize.height)
        titleField.frame = NSRect(
            x: originX + transcriptToolIconTextSpacing,
            y: originY + ((transcriptToolIconFrameSize - titleHeight) / 2),
            width: max(width - transcriptToolIconTextSpacing, 0),
            height: titleHeight
        )
        iconView.symbolConfiguration = .init(pointSize: typography.size(for: .toolIcon), weight: .regular)
    }

    private func layoutActions(originX: CGFloat, originY: CGFloat, width: CGFloat) {
        sizeApprovalSplitControl()
        let approvalControl = approvalSplitControl.isHidden ? approveButton : approvalSplitControl
        let approveWidth = ceil(preferredWidth(for: approvalControl))
        let denyWidth = ceil(preferredWidth(for: denyButton))
        let horizontalWidth = approveWidth + 8 + denyWidth
        let shouldAnimateActions = shouldAnimateActionsOnNextLayout
        shouldAnimateActionsOnNextLayout = false
        let metrics = ApprovalActionLayoutMetrics(
            origin: NSPoint(x: originX, y: originY),
            approveWidth: approveWidth,
            denyWidth: denyWidth,
            animated: shouldAnimateActions
        )

        if horizontalWidth <= width {
            layoutHorizontalActions(approvalControl: approvalControl, metrics: metrics)
        } else {
            layoutVerticalActions(approvalControl: approvalControl, availableWidth: width, metrics: metrics)
        }
    }

    private func layoutHorizontalActions(
        approvalControl: NSView,
        metrics: ApprovalActionLayoutMetrics
    ) {
        if showsDenyInPrimarySlot {
            // Preserve the SwiftUI matched-geometry behavior: after denial,
            // Denied moves into the prior approval slot while the old approval
            // control stays as an invisible width placeholder after it.
            let deniedFrame = NSRect(x: metrics.origin.x, y: metrics.origin.y, width: metrics.denyWidth, height: denyButton.fittingSize.height)
            setDeniedActionFrame(deniedFrame, animated: metrics.animated)
            setApprovalPlaceholderFrame(
                NSRect(
                    x: deniedFrame.maxX + 8,
                    y: metrics.origin.y,
                    width: metrics.approveWidth,
                    height: approvalControl.fittingSize.height
                ),
                for: approvalControl,
                animated: metrics.animated
            )
        } else {
            setActionFrame(
                NSRect(
                    x: metrics.origin.x,
                    y: metrics.origin.y,
                    width: metrics.approveWidth,
                    height: approvalControl.fittingSize.height
                ),
                for: approvalControl,
                animated: metrics.animated
            )
            setActionFrame(
                NSRect(
                    x: approvalControl.frame.maxX + 8,
                    y: metrics.origin.y,
                    width: metrics.denyWidth,
                    height: denyButton.fittingSize.height
                ),
                for: denyButton,
                animated: metrics.animated
            )
        }
        hiddenApprovalControl.frame = .zero
    }

    private func layoutVerticalActions(
        approvalControl: NSView,
        availableWidth: CGFloat,
        metrics: ApprovalActionLayoutMetrics
    ) {
        let firstControl = showsDenyInPrimarySlot ? denyButton : approvalControl
        let secondControl = showsDenyInPrimarySlot ? approvalControl : denyButton
        let firstWidth = showsDenyInPrimarySlot ? metrics.denyWidth : metrics.approveWidth
        let secondWidth = showsDenyInPrimarySlot ? metrics.approveWidth : metrics.denyWidth
        let firstFrame = NSRect(
            x: metrics.origin.x,
            y: metrics.origin.y,
            width: min(firstWidth, availableWidth),
            height: firstControl.fittingSize.height
        )
        if firstControl === denyButton {
            setDeniedActionFrame(firstFrame, animated: metrics.animated)
        } else {
            setActionFrame(firstFrame, for: firstControl, animated: metrics.animated)
        }

        let secondFrame = NSRect(
            x: metrics.origin.x,
            y: firstFrame.maxY + 8,
            width: min(secondWidth, availableWidth),
            height: secondControl.fittingSize.height
        )
        if showsDenyInPrimarySlot {
            setApprovalPlaceholderFrame(secondFrame, for: secondControl, animated: metrics.animated)
        } else {
            setActionFrame(secondFrame, for: secondControl, animated: metrics.animated)
        }
        hiddenApprovalControl.frame = .zero
    }

    private func preferredWidth(for view: NSView) -> CGFloat {
        if let button = view as? AppKitTranscriptApprovalButton {
            return button.preferredWidth
        }
        if let splitControl = view as? AppKitTranscriptApprovalSplitControl {
            return splitControl.preferredWidth
        }
        return view.fittingSize.width
    }

    private func setActionFrame(_ frame: NSRect, for view: NSView, animated: Bool) {
        guard animated, view.frame != .zero, view.frame != frame else {
            view.frame = frame
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = appExpansionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.animator().frame = frame
        }
    }

    private func setDeniedActionFrame(_ frame: NSRect, animated: Bool) {
        if activeDenySlotAnimationTargetFrame == frame {
            return
        }
        guard animated, let startFrame = pendingDenySlotAnimationStartFrame, startFrame != frame else {
            setActionFrame(frame, for: denyButton, animated: animated)
            pendingDenySlotAnimationStartFrame = nil
            return
        }
        denyButton.frame = startFrame
        pendingDenySlotAnimationStartFrame = nil
        scheduleDenySlotAnimation(from: startFrame, to: frame)
    }

    private func setApprovalPlaceholderFrame(_ frame: NSRect, for view: NSView, animated: Bool) {
        if activeApprovePlaceholderTargetFrame == frame {
            return
        }
        guard animated, let startFrame = pendingApprovePlaceholderFrame, startFrame != frame else {
            setActionFrame(frame, for: view, animated: animated)
            pendingApprovePlaceholderFrame = nil
            return
        }
        view.frame = startFrame
        pendingApprovePlaceholderFrame = nil
        scheduleApprovalPlaceholderAnimation(from: startFrame, to: frame, view: view)
    }

    private func scheduleDenySlotAnimation(from startFrame: NSRect, to frame: NSRect) {
#if DEBUG
        lastDenySlotAnimationFrames = (from: startFrame, to: frame)
        didDeferDenySlotAnimation = window != nil
#endif
        guard window != nil else {
            denyButton.frame = frame
            return
        }
        denySlotAnimationGeneration += 1
        let generation = denySlotAnimationGeneration
        activeDenySlotAnimationTargetFrame = frame
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.window != nil,
                  generation == self.denySlotAnimationGeneration else {
                return
            }
            self.denyButton.frame = startFrame
            NSAnimationContext.runAnimationGroup { context in
                context.duration = appExpansionAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.denyButton.animator().frame = frame
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self,
                          generation == self.denySlotAnimationGeneration else {
                        return
                    }
                    self.activeDenySlotAnimationTargetFrame = nil
                    self.denyButton.frame = frame
                }
            }
        }
    }

    private func scheduleApprovalPlaceholderAnimation(from startFrame: NSRect, to frame: NSRect, view: NSView) {
#if DEBUG
        lastApprovePlaceholderFrames = (from: startFrame, to: frame)
        didDeferPlaceholderAnimation = window != nil
#endif
        guard window != nil else {
            view.frame = frame
            return
        }
        approvePlaceholderAnimationGeneration += 1
        let generation = approvePlaceholderAnimationGeneration
        activeApprovePlaceholderTargetFrame = frame
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self,
                  let view,
                  self.window != nil,
                  generation == self.approvePlaceholderAnimationGeneration else {
                return
            }
            view.frame = startFrame
            NSAnimationContext.runAnimationGroup { context in
                context.duration = appExpansionAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.animator().frame = frame
            } completionHandler: { [weak self, weak view] in
                Task { @MainActor [weak self, weak view] in
                    guard let self,
                          let view,
                          generation == self.approvePlaceholderAnimationGeneration else {
                        return
                    }
                    self.activeApprovePlaceholderTargetFrame = nil
                    view.frame = frame
                }
            }
        }
    }

    private var hiddenApprovalControl: NSView {
        approvalSplitControl.isHidden ? approvalSplitControl : approveButton
    }

    private func bubbleWidth(for configuration: Configuration) -> CGFloat {
        let availableWidth = max(bounds.width, 0)
        let cap = configuration.bubbleMaxWidth.isFinite ? configuration.bubbleMaxWidth : availableWidth
        let maxWidth = min(max(cap, 0), availableWidth)
        guard maxWidth > 0 else {
            return 0
        }
        return min(max(naturalBubbleWidth(for: configuration), 0), maxWidth)
    }

    private func naturalBubbleWidth(for configuration: Configuration) -> CGFloat {
        let scopes = sessionApprovalScopes(for: configuration)
        let headerWidth = transcriptToolIconTextSpacing + ceil(titleField.fittingSize.width)
        let summaryWidth = summaryViews.reduce(CGFloat.zero) { width, view in
            max(width, transcriptToolDetailLeadingInset + view.naturalWidth)
        }
        let actionWidth = transcriptToolDetailLeadingInset + naturalActionWidth(scopes: scopes)
        return ceil((chatBlockPadding * 2) + max(headerWidth, summaryWidth, actionWidth))
    }

    private func naturalActionWidth(scopes: [ToolApprovalSessionScope]) -> CGFloat {
        let approveWidth: CGFloat
        if approvalSplitControl.isHidden {
            approveWidth = approveButton.preferredWidth
        } else {
            updateApprovalSplitControl(scopes: scopes)
            approveWidth = approvalSplitControl.preferredWidth
        }
        return approveWidth + 8 + denyButton.preferredWidth
    }
}

private struct ApprovalActionLayoutMetrics {
    let origin: NSPoint
    let approveWidth: CGFloat
    let denyWidth: CGFloat
    let animated: Bool
}

#if DEBUG
@MainActor
extension AppKitTranscriptToolApprovalBlockView {
    var denySlotAnimationFramesForTesting: (from: NSRect, to: NSRect)? {
        lastDenySlotAnimationFrames
    }

    var approvePlaceholderFramesForTesting: (from: NSRect, to: NSRect)? {
        lastApprovePlaceholderFrames
    }

    var didDeferDenySlotAnimationForTesting: Bool {
        didDeferDenySlotAnimation
    }

    var didDeferPlaceholderAnimationForTesting: Bool {
        didDeferPlaceholderAnimation
    }

    var activeDenyTargetFrameForTesting: NSRect? {
        activeDenySlotAnimationTargetFrame
    }
}
#endif
