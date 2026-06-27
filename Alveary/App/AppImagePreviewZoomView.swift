@preconcurrency import AppKit
import SwiftUI

struct AppImagePreviewZoomCommand: Equatable {
    let id = UUID()
    let action: Action

    enum Action: Equatable {
        case fit
        case actualSize
        case zoomIn
        case zoomOut
    }
}

struct AppImagePreviewZoomState: Equatable {
    let magnification: CGFloat
    let fittedMagnification: CGFloat?

    static let identity = AppImagePreviewZoomState(magnification: 1, fittedMagnification: nil)

    var displayScale: CGFloat {
        guard let fittedMagnification,
              fittedMagnification > 0 else {
            return magnification
        }
        return magnification / fittedMagnification
    }

    func isApproximatelyEqual(to other: AppImagePreviewZoomState) -> Bool {
        abs(magnification - other.magnification) <= Self.tolerance &&
            abs((fittedMagnification ?? 0) - (other.fittedMagnification ?? 0)) <= Self.tolerance
    }

    private static let tolerance: CGFloat = 0.0001
}

struct AppImagePreviewZoomView: NSViewRepresentable {
    let image: NSImage
    let command: AppImagePreviewZoomCommand?
    let onZoomStateChanged: @MainActor (AppImagePreviewZoomState) -> Void
    let onBackgroundClick: @MainActor () -> Void

    init(
        image: NSImage,
        command: AppImagePreviewZoomCommand?,
        onZoomStateChanged: @escaping @MainActor (AppImagePreviewZoomState) -> Void = { _ in },
        onBackgroundClick: @escaping @MainActor () -> Void = {}
    ) {
        self.image = image
        self.command = command
        self.onZoomStateChanged = onZoomStateChanged
        self.onBackgroundClick = onBackgroundClick
    }

    func makeNSView(context: Context) -> AppImagePreviewScrollView {
        AppImagePreviewScrollView()
    }

    func updateNSView(_ nsView: AppImagePreviewScrollView, context: Context) {
        nsView.onZoomStateChanged = onZoomStateChanged
        nsView.onBackgroundClick = onBackgroundClick
        nsView.configure(image: image)
        if context.coordinator.lastCommand != command {
            context.coordinator.lastCommand = command
            if let command {
                nsView.perform(command.action)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastCommand: AppImagePreviewZoomCommand?
    }
}

@MainActor
final class AppImagePreviewScrollView: NSScrollView {
    private let imageView = NSImageView()
    private var currentImage: NSImage?
    private var shouldFitAfterNextLayout = false
    private var lastLaidOutBoundsSize: NSSize?
    private var lastLaidOutVisibleSize: NSSize?
    private var lastReportedZoomState: AppImagePreviewZoomState?
    var onZoomStateChanged: (@MainActor (AppImagePreviewZoomState) -> Void)?
    var onBackgroundClick: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        lastLaidOutBoundsSize = bounds.size
        lastLaidOutVisibleSize = contentView.frame.size
        if shouldFitAfterNextLayout {
            shouldFitAfterNextLayout = !fitToVisibleBounds()
        }
        notifyMagnificationChanged()
    }

    override func setMagnification(_ magnification: CGFloat, centeredAt point: NSPoint) {
        super.setMagnification(magnification, centeredAt: point)
        notifyMagnificationChanged()
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        notifyMagnificationChanged()
    }

    override func smartMagnify(with event: NSEvent) {
        super.smartMagnify(with: event)
        notifyMagnificationChanged()
    }

    override func mouseDown(with event: NSEvent) {
        if handleBackgroundClickIfNeeded(at: event.locationInWindow, from: nil) {
            return
        } else {
            super.mouseDown(with: event)
        }
    }

    func configure(image: NSImage) {
        guard currentImage !== image else {
            return
        }
        currentImage = image
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: image.previewDisplaySize)
        documentView = imageView
        lastReportedZoomState = nil
        shouldFitAfterNextLayout = true
        needsLayout = true
    }

    func perform(_ action: AppImagePreviewZoomCommand.Action) {
        switch action {
        case .fit:
            if canFitWithCurrentLayout {
                shouldFitAfterNextLayout = !fitToVisibleBounds()
            } else {
                shouldFitAfterNextLayout = true
                needsLayout = true
            }
        case .actualSize:
            shouldFitAfterNextLayout = false
            setMagnification(1, centeredAt: visibleCenter)
            notifyMagnificationChanged()
        case .zoomIn:
            shouldFitAfterNextLayout = false
            setMagnification(magnification * 1.2, centeredAt: visibleCenter)
            notifyMagnificationChanged()
        case .zoomOut:
            shouldFitAfterNextLayout = false
            setMagnification(magnification / 1.2, centeredAt: visibleCenter)
            notifyMagnificationChanged()
        }
    }

    private func setup() {
        let clipView = AppImagePreviewClipView()
        clipView.drawsBackground = false
        contentView = clipView

        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = 0.05
        maxMagnification = 8
        scrollerStyle = .overlay

        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = true
        documentView = imageView
    }

    private func fitToVisibleBounds() -> Bool {
        guard let scale = fittedMagnificationForCurrentBounds() else {
            return false
        }
        setMagnification(scale, centeredAt: imageCenter)
        notifyMagnificationChanged()
        return true
    }

    private func notifyMagnificationChanged() {
        let zoomState = AppImagePreviewZoomState(
            magnification: magnification,
            fittedMagnification: fittedMagnificationForCurrentBounds()
        )
        if let lastReportedZoomState,
           zoomState.isApproximatelyEqual(to: lastReportedZoomState) {
            return
        }
        lastReportedZoomState = zoomState
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else {
                return
            }
            self.onZoomStateChanged?(zoomState)
        }
    }

    private func fittedMagnificationForCurrentBounds() -> CGFloat? {
        Self.fittedMagnification(
            imageSize: imageView.frame.size,
            visibleSize: contentView.frame.size,
            minMagnification: minMagnification,
            maxMagnification: maxMagnification
        )
    }

    private static func fittedMagnification(
        imageSize: NSSize,
        visibleSize: NSSize,
        minMagnification: CGFloat,
        maxMagnification: CGFloat
    ) -> CGFloat? {
        guard imageSize.width > 0, imageSize.height > 0,
              visibleSize.width > 0, visibleSize.height > 0 else {
            return nil
        }
        let widthScale = visibleSize.width / imageSize.width
        let heightScale = visibleSize.height / imageSize.height
        let scale = min(widthScale, heightScale, 1) * modalBaselineScale
        return max(minMagnification, min(maxMagnification, scale))
    }

    private static let modalBaselineScale: CGFloat = 0.8

    private var canFitWithCurrentLayout: Bool {
        guard let lastLaidOutBoundsSize,
              let lastLaidOutVisibleSize,
              contentView.frame.width > 0,
              contentView.frame.height > 0 else {
            return false
        }
        return abs(lastLaidOutBoundsSize.width - bounds.width) <= 0.5 &&
            abs(lastLaidOutBoundsSize.height - bounds.height) <= 0.5 &&
            abs(lastLaidOutVisibleSize.width - contentView.frame.width) <= 0.5 &&
            abs(lastLaidOutVisibleSize.height - contentView.frame.height) <= 0.5
    }

    private var imageCenter: NSPoint {
        NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
    }

    private var visibleCenter: NSPoint {
        let visibleRect = contentView.documentVisibleRect
        return NSPoint(x: visibleRect.midX, y: visibleRect.midY)
    }

    private func handleBackgroundClickIfNeeded(at point: NSPoint, from view: NSView?) -> Bool {
        guard !imageContainsPoint(point, from: view) else {
            return false
        }
        onBackgroundClick?()
        return true
    }

    private func imageContainsPoint(_ point: NSPoint, from view: NSView?) -> Bool {
        let pointInImage = imageView.convert(point, from: view)
        return imageView.bounds.contains(pointInImage)
    }
}

private final class AppImagePreviewClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        guard let documentView else {
            return constrained
        }
        let documentFrame = documentView.frame
        // Negative origins keep the scaled document centered when it is smaller than the viewport.
        if documentFrame.width < proposedBounds.width {
            constrained.origin.x = (documentFrame.width - proposedBounds.width) / 2
        }
        if documentFrame.height < proposedBounds.height {
            constrained.origin.y = (documentFrame.height - proposedBounds.height) / 2
        }
        return constrained
    }
}

private extension NSImage {
    var previewDisplaySize: NSSize {
        if size.width > 0, size.height > 0 {
            return size
        }
        if let representation = representations.first,
           representation.pixelsWide > 0,
           representation.pixelsHigh > 0 {
            return NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return size
    }
}

#if DEBUG
extension AppImagePreviewScrollView {
    var hasPendingFitAfterLayoutForTesting: Bool {
        shouldFitAfterNextLayout
    }

    var documentViewSizeForTesting: NSSize? {
        documentView?.frame.size
    }

    var visibleDocumentCenterForTesting: NSPoint {
        NSPoint(x: contentView.documentVisibleRect.midX, y: contentView.documentVisibleRect.midY)
    }

    func imageContainsScrollViewPointForTesting(_ point: NSPoint) -> Bool {
        imageContainsPoint(point, from: self)
    }

    @discardableResult
    func handleMouseDownInScrollViewForTesting(_ point: NSPoint) -> Bool {
        handleBackgroundClickIfNeeded(at: point, from: self)
    }

    func fittedMagnificationForTesting(imageSize: NSSize, visibleSize: NSSize) -> CGFloat? {
        Self.fittedMagnification(
            imageSize: imageSize,
            visibleSize: visibleSize,
            minMagnification: minMagnification,
            maxMagnification: maxMagnification
        )
    }
}
#endif
