import AppKit

extension ChatComposerActionRowView {
    /// Lays out the row in two independent groups: settings stay on the leading
    /// side and trailing accessories/actions pin to the right edge. This avoids
    /// `NSStackView` compression redistributing space in ways that truncate
    /// short session-location labels like "Local" while still letting dropdowns
    /// compress first.
    func layoutArrangedSubviews() {
        let arrangedSubviews = rowSubviews.filter { $0.superview === stack && !$0.isHidden }
        guard let spacerIndex = arrangedSubviews.firstIndex(of: spacer) else {
            return
        }

        let settingsViews = Array(arrangedSubviews[..<spacerIndex])
        let trailingViews = Array(arrangedSubviews[(spacerIndex + 1)...])

        stack.frame = bounds
        spacer.frame = .zero

        let trailingFrames = trailingFrames(for: trailingViews, rowWidth: stack.bounds.width)
        for (view, frame) in trailingFrames {
            view.frame = frame
            view.layoutSubtreeIfNeeded()
        }

        let settingsLimit = max(0, (trailingFrames.map(\.value.minX).min() ?? stack.bounds.maxX) - rowSpacing)
        let settingsFrames = settingsFrames(for: settingsViews, availableWidth: settingsLimit)
        for (view, frame) in settingsFrames {
            view.frame = frame
        }
    }

    private func trailingFrames(for views: [NSView], rowWidth: CGFloat) -> [NSView: NSRect] {
        var frames: [NSView: NSRect] = [:]
        var nextX = rowWidth
        for view in views.reversed() {
            let width = preferredWidth(for: view)
            nextX -= width
            frames[view] = centeredFrame(originX: nextX, width: width, for: view)
            nextX -= rowSpacing
        }
        return frames
    }

    private func settingsFrames(for views: [NSView], availableWidth: CGFloat) -> [NSView: NSRect] {
        guard !views.isEmpty, availableWidth > 0 else {
            return views.reduce(into: [:]) { frames, view in
                frames[view] = centeredFrame(originX: 0, width: 0, for: view)
            }
        }

        let spacing = min(rowSpacing, views.count > 1 ? availableWidth / CGFloat(views.count - 1) : rowSpacing)
        let spacingWidth = spacing * CGFloat(max(0, views.count - 1))
        let contentWidth = max(0, availableWidth - spacingWidth)
        let preferredWidths = views.map(preferredWidth(for:))
        let widths = compressedWidths(views: views, preferredWidths: preferredWidths, availableWidth: contentWidth)

        var frames: [NSView: NSRect] = [:]
        var nextX: CGFloat = 0
        for (index, view) in views.enumerated() {
            let width = widths[index]
            frames[view] = centeredFrame(originX: nextX, width: width, for: view)
            nextX += width + spacing
        }
        return frames
    }

    private func compressedWidths(views: [NSView], preferredWidths: [CGFloat], availableWidth: CGFloat) -> [CGFloat] {
        guard !preferredWidths.isEmpty else {
            return []
        }
        let preferredTotal = preferredWidths.reduce(0, +)
        guard preferredTotal > availableWidth else {
            return preferredWidths
        }

        let minimumWidths = zip(views, preferredWidths).map { view, preferredWidth in
            minimumWidth(for: view, preferredWidth: preferredWidth)
        }
        let minimumTotal = minimumWidths.reduce(0, +)
        guard minimumTotal < availableWidth else {
            return overflowWidths(views: views, minimumWidths: minimumWidths, availableWidth: availableWidth)
        }

        var widths = preferredWidths
        var remainingReduction = preferredTotal - availableWidth
        for index in widths.indices {
            let reducible = widths[index] - minimumWidths[index]
            let reduction = min(reducible, remainingReduction)
            widths[index] -= reduction
            remainingReduction -= reduction
            if remainingReduction <= 0 {
                break
            }
        }
        return widths
    }

    private func overflowWidths(views: [NSView], minimumWidths: [CGFloat], availableWidth: CGFloat) -> [CGFloat] {
        let fixedWidth = zip(views, minimumWidths)
            .filter { view, _ in !canCompressBelowMinimum(view) }
            .map(\.1)
            .reduce(0, +)
        let compressibleIndexes = views.indices.filter { canCompressBelowMinimum(views[$0]) }
        let compressibleWidth = max(0, availableWidth - fixedWidth)
        let compressibleMinimumTotal = compressibleIndexes
            .map { minimumWidths[$0] }
            .reduce(0, +)
        var widths = minimumWidths

        for index in compressibleIndexes {
            let scale = compressibleMinimumTotal > 0 ? compressibleWidth / compressibleMinimumTotal : 0
            widths[index] = floor(minimumWidths[index] * scale)
        }

        return widths
    }

    private func minimumWidth(for view: NSView, preferredWidth: CGFloat) -> CGFloat {
        if !canCompressBelowMinimum(view) {
            return preferredWidth
        }
        return min(preferredWidth, minimumSettingsControlWidth)
    }

    private func canCompressBelowMinimum(_ view: NSView) -> Bool {
        view !== sessionLocationField
    }

    private func centeredFrame(originX: CGFloat, width: CGFloat, for view: NSView) -> NSRect {
        let height = preferredHeight(for: view)
        return NSRect(
            x: floor(originX),
            y: floor((stack.bounds.height - height) / 2),
            width: max(0, floor(width)),
            height: height
        )
    }

    private func preferredWidth(for view: NSView) -> CGFloat {
        if view === disabledProgressContainer {
            return disabledSendSlot.intrinsicContentSize.width
        }
        if view === sessionLocationField {
            return measuredWidth(for: sessionLocationField)
        }
        let intrinsicWidth = view.intrinsicContentSize.width
        if intrinsicWidth != NSView.noIntrinsicMetric, intrinsicWidth > 0 {
            return ceil(intrinsicWidth)
        }
        return ceil(view.fittingSize.width)
    }

    private func preferredHeight(for view: NSView) -> CGFloat {
        let intrinsicHeight = view.intrinsicContentSize.height
        if intrinsicHeight != NSView.noIntrinsicMetric, intrinsicHeight > 0 {
            return ceil(intrinsicHeight)
        }
        return configuration?.composerActionRowHeight ?? 30
    }

    private func measuredWidth(for field: NSTextField) -> CGFloat {
        let font = field.font ?? .preferredFont(forTextStyle: .callout)
        let textWidth = (field.stringValue as NSString).size(withAttributes: [.font: font]).width
        let cellWidth = field.cell?.cellSize.width ?? 0
        let intrinsicWidth = field.intrinsicContentSize.width
        return ceil(max(textWidth, cellWidth, intrinsicWidth)) + 4
    }

    func progressLabelText(for configuration: Configuration) -> String {
        guard case .progressOnly(let reason) = configuration.mode,
              !reason.canStop,
              reason != .reconfiguringSession else {
            return ""
        }
        return ChatComposerTextSupport.progressLabel(for: reason)
    }
}
