@preconcurrency import AppKit
import BlockInputKit

@MainActor
final class AppKitMarkdownImageBlockView: NSView {
    struct Configuration: Equatable {
        let image: BlockInputImage
        let baseURL: URL?
    }

    static let defaultInitialWidth: CGFloat = 520

    private static let loader = BlockInputDefaultImageLoader()
    private static let diskCache = BlockInputDefaultImageDiskCache()
    private static let maximumSourceBytes = 20 * 1024 * 1024
    private static let maximumPixelDimension = 8_192

    private let contentView = AppKitFlippedDynamicColorView()
    private let imageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var configuration: Configuration?
    private var loadedCacheKey: String?
    private var loadTask: Task<Void, Never>?
    var onOpen: ((BlockInputImage, URL?) -> Void)? {
        didSet {
            updateOpenState()
        }
    }
    var maximumDisplayWidth = defaultInitialWidth {
        didSet {
            if abs(oldValue - maximumDisplayWidth) > 0.5 {
                invalidateIntrinsicContentSize()
                needsLayout = true
            }
        }
    }

    init(
        configuration: Configuration,
        onOpen: ((BlockInputImage, URL?) -> Void)? = nil
    ) {
        self.onOpen = onOpen
        super.init(frame: .zero)
        setup()
        configure(configuration)
        updateOpenState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: displaySize.width, height: displaySize.height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let previousDisplaySize = displaySize
        super.setFrameSize(newSize)
        if abs(previousDisplaySize.width - displaySize.width) > 0.5 ||
            abs(previousDisplaySize.height - displaySize.height) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    override func layout() {
        super.layout()
        let size = displaySize
        contentView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        imageView.frame = contentView.bounds
        statusLabel.frame = NSRect(
            x: 10,
            y: floor((contentView.bounds.height - statusLabel.intrinsicContentSize.height) / 2),
            width: max(contentView.bounds.width - 20, 0),
            height: statusLabel.intrinsicContentSize.height
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)),
              performOpen() else {
            super.mouseUp(with: event)
            return
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if onOpen != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        performOpen()
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        let accessibilityLabel = configuration.image.altText.isEmpty
            ? configuration.image.source
            : configuration.image.altText
        toolTip = accessibilityLabel
        setAccessibilityLabel(accessibilityLabel)
        loadedCacheKey = nil
        imageView.image = nil
        showStatus("")
        invalidateIntrinsicContentSize()
        needsLayout = true
        startLoadIfPossible()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.image)

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        contentView.layer?.masksToBounds = true
        addSubview(contentView)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        contentView.addSubview(imageView)

        statusLabel.alignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        applyPlaceholderStyle()
    }

    @discardableResult
    private func performOpen() -> Bool {
        guard let configuration,
              let onOpen else {
            return false
        }
        onOpen(configuration.image, configuration.baseURL)
        return true
    }

    private func startLoadIfPossible() {
        loadTask?.cancel()
        guard let configuration,
              let resolvedURL = AppMarkdownImageSourceResolver.resolvedURL(
                for: configuration.image.source,
                baseURL: configuration.baseURL
              ) else {
            showStatus("Image unavailable")
            return
        }

        let cacheKey = configuration.image.cacheKey(
            resolvedURL: resolvedURL,
            maximumPixelDimension: Self.maximumPixelDimension
        )
        guard loadedCacheKey != cacheKey else {
            return
        }

        applyPlaceholderStyle()
        let request = BlockInputImageLoadRequest(
            image: configuration.image,
            resolvedURL: resolvedURL,
            cacheKey: cacheKey,
            maxSourceBytes: Self.maximumSourceBytes,
            maxPixelDimension: Self.maximumPixelDimension,
            diskCache: Self.diskCache
        )
        loadTask = Task { [weak self] in
            do {
                let loaded = try await Self.loader.loadImage(request)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.finishLoad(loaded, cacheKey: cacheKey)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.finishLoadFailure()
                }
            }
        }
    }

    private func finishLoad(
        _ loaded: BlockInputLoadedImage,
        cacheKey: String
    ) {
        loadTask = nil
        guard let image = NSImage(data: loaded.data) else {
            finishLoadFailure()
            return
        }
        loadedCacheKey = cacheKey
        imageView.image = image
        imageView.isHidden = false
        statusLabel.isHidden = true
        contentView.setLayerFillColor(nil)
        contentView.setLayerStrokeColor(nil)
    }

    private func finishLoadFailure() {
        loadTask = nil
        loadedCacheKey = nil
        imageView.image = nil
        showStatus("Image unavailable")
        applyPlaceholderStyle()
    }

    private func showStatus(_ value: String) {
        statusLabel.stringValue = value
        statusLabel.isHidden = value.isEmpty
        imageView.isHidden = !value.isEmpty
    }

    private func applyPlaceholderStyle() {
        contentView.setLayerFillColor(.quaternaryLabelColor, alpha: 0.26)
        contentView.layer?.borderWidth = 1
        contentView.setLayerStrokeColor(.separatorColor, alpha: 0.35)
    }

    private func updateOpenState() {
        setAccessibilityRole(onOpen == nil ? .image : .button)
        window?.invalidateCursorRects(for: self)
    }

    private var displaySize: CGSize {
        let constrainedWidth = bounds.width > 0 ? min(bounds.width, maximumDisplayWidth) : maximumDisplayWidth
        guard let configuration else {
            return CGSize(width: appMarkdownImageMinimumDisplayDimension, height: appMarkdownImageMinimumDisplayDimension)
        }
        return appMarkdownImageDisplaySize(for: configuration.image, constrainedTo: constrainedWidth)
    }
}

#if DEBUG
extension AppKitMarkdownImageBlockView {
    var loadedImageForTesting: NSImage? {
        imageView.image
    }

    var statusTextForTesting: String {
        statusLabel.stringValue
    }

    var displaySizeForTesting: CGSize {
        displaySize
    }

    @discardableResult
    func performOpenForTesting() -> Bool {
        performOpen()
    }
}
#endif
