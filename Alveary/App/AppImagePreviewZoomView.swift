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

struct AppImagePreviewZoomView: NSViewRepresentable {
    let image: NSImage
    let command: AppImagePreviewZoomCommand?

    func makeNSView(context: Context) -> AppImagePreviewScrollView {
        AppImagePreviewScrollView()
    }

    func updateNSView(_ nsView: AppImagePreviewScrollView, context: Context) {
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
        if shouldFitAfterNextLayout, bounds.width > 0, bounds.height > 0 {
            shouldFitAfterNextLayout = false
            fitToVisibleBounds()
        }
    }

    func configure(image: NSImage) {
        guard currentImage !== image else {
            return
        }
        currentImage = image
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: image.pixelBackedSize)
        documentView = imageView
        shouldFitAfterNextLayout = true
        needsLayout = true
    }

    func perform(_ action: AppImagePreviewZoomCommand.Action) {
        switch action {
        case .fit:
            fitToVisibleBounds()
        case .actualSize:
            setMagnification(1, centeredAt: visibleCenter)
        case .zoomIn:
            setMagnification(magnification * 1.2, centeredAt: visibleCenter)
        case .zoomOut:
            setMagnification(magnification / 1.2, centeredAt: visibleCenter)
        }
    }

    private func setup() {
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

    private func fitToVisibleBounds() {
        let imageSize = imageView.frame.size
        guard let scale = Self.fittedMagnification(
            imageSize: imageSize,
            visibleSize: contentView.bounds.size,
            minMagnification: minMagnification,
            maxMagnification: maxMagnification
        ) else {
            return
        }
        setMagnification(scale, centeredAt: imageCenter)
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
        let scale = min(widthScale, heightScale, 1)
        return max(minMagnification, min(maxMagnification, scale))
    }

    private var imageCenter: NSPoint {
        NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
    }

    private var visibleCenter: NSPoint {
        NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    }
}

private extension NSImage {
    var pixelBackedSize: NSSize {
        if let representation = representations.first {
            return NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return size
    }
}

#if DEBUG
extension AppImagePreviewScrollView {
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
