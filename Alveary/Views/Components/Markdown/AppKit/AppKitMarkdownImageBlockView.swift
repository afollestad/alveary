@preconcurrency import AppKit
import BlockInputKit

/// One standalone markdown image block: placeholder chrome while loading, the
/// bitmap once it arrives, and an unavailable label on failure.
///
/// The box wraps the bitmap rather than reserving a fixed aspect ratio, and it
/// does so *before* the load by resolving the source's real dimensions through
/// `AppMarkdownImageStore` — a local file answers from its header, and anything
/// already loaded answers from the store. Sizing from the decoded `NSImage`
/// instead would move the transcript under the reader on every load.
@MainActor
final class AppKitMarkdownImageBlockView: NSView {
    struct Configuration: Equatable {
        let image: BlockInputImage
        let baseURL: URL?
    }

    static let defaultInitialWidth: CGFloat = 520

    private let contentView = AppKitFlippedDynamicColorView()
    private let imageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    /// Centered working indicator while the network load runs; mirrors the
    /// SwiftUI block view's spinner.
    private let loadingSpinner = AppKitStatusIndicatorSpinner()
    private let imageStore: AppMarkdownImageStore
    private var configuration: Configuration?
    private nonisolated(unsafe) var imageStateObserver: (any NSObjectProtocol)?
    /// The display size this view last reported upward. A load whose dimensions
    /// the header probe already predicted must not re-report, or every image
    /// would still cost the transcript a height invalidation it does not need.
    private var reportedDisplaySize: CGSize = .zero
    /// Invoked only when a store update actually changes `displaySize`.
    var onHeightInvalidated: (() -> Void)?
    var onOpen: ((BlockInputImage, URL?) -> Void)? {
        didSet {
            updateOpenState()
        }
    }
    var maximumDisplayWidth = defaultInitialWidth {
        didSet {
            if abs(oldValue - maximumDisplayWidth) > 0.5 {
                invalidateIntrinsicContentSize()
                reportedDisplaySize = displaySize
                needsLayout = true
            }
        }
    }

    init(
        configuration: Configuration,
        imageStore: AppMarkdownImageStore = .shared,
        onOpen: ((BlockInputImage, URL?) -> Void)? = nil,
        onHeightInvalidated: (() -> Void)? = nil
    ) {
        self.imageStore = imageStore
        self.onOpen = onOpen
        self.onHeightInvalidated = onHeightInvalidated
        super.init(frame: .zero)
        setup()
        observeImageStateChanges()
        configure(configuration)
        updateOpenState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let imageStateObserver {
            NotificationCenter.default.removeObserver(imageStateObserver)
        }
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
            reportedDisplaySize = displaySize
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
        let spinnerSide: CGFloat = 16
        loadingSpinner.frame = NSRect(
            x: floor((contentView.bounds.width - spinnerSide) / 2),
            y: floor((contentView.bounds.height - spinnerSide) / 2),
            width: spinnerSide,
            height: spinnerSide
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
        imageView.image = nil
        showStatus("")
        applyPlaceholderStyle()
        imageStore.ensureLoad(for: configuration.image, baseURL: configuration.baseURL)
        applyStoreState()
        invalidateIntrinsicContentSize()
        reportedDisplaySize = displaySize
        needsLayout = true
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

        contentView.addSubview(loadingSpinner)

        applyPlaceholderStyle()
    }

    /// The store owns loading for every markdown surface, so this view only
    /// reacts to it. Filtering to its own source keeps an unrelated image's
    /// load from touching this block.
    private func observeImageStateChanges() {
        imageStateObserver = NotificationCenter.default.addObserver(
            forName: .appMarkdownImageStateDidChange,
            object: imageStore,
            queue: .main
        ) { [weak self] notification in
            guard let key = notification.userInfo?[AppMarkdownImageStore.storageKeyUserInfoKey] as? String else {
                return
            }
            MainActor.assumeIsolated {
                guard let self, let configuration = self.configuration else {
                    return
                }
                let ownKey = self.imageStore.storageKey(
                    forSource: configuration.image.source,
                    baseURL: configuration.baseURL
                )
                guard ownKey == key else {
                    return
                }
                self.applyStoreState()
                self.reportDisplaySizeChangeIfNeeded()
            }
        }
    }

    private func applyStoreState() {
        guard let configuration else {
            return
        }
        if let image = imageStore.image(forSource: configuration.image.source, baseURL: configuration.baseURL) {
            imageView.image = image
            imageView.isHidden = false
            statusLabel.isHidden = true
            loadingSpinner.isHidden = true
            contentView.setLayerFillColor(nil)
            contentView.setLayerStrokeColor(nil)
            return
        }
        imageView.image = nil
        let hasFailed = imageStore.hasFailed(source: configuration.image.source, baseURL: configuration.baseURL)
        showStatus(hasFailed ? "Image unavailable" : "")
        applyPlaceholderStyle()
    }

    private func reportDisplaySizeChangeIfNeeded() {
        let size = displaySize
        guard abs(size.width - reportedDisplaySize.width) > 0.5 ||
            abs(size.height - reportedDisplaySize.height) > 0.5 else {
            return
        }
        reportedDisplaySize = size
        invalidateIntrinsicContentSize()
        needsLayout = true
        onHeightInvalidated?()
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

    private func showStatus(_ value: String) {
        statusLabel.stringValue = value
        statusLabel.isHidden = value.isEmpty
        imageView.isHidden = !value.isEmpty
        // The empty status is the loading placeholder; text means failure.
        loadingSpinner.isHidden = !value.isEmpty
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
        let naturalSize = imageStore.naturalSize(for: configuration.image, baseURL: configuration.baseURL)
        return appMarkdownImageDisplaySize(
            for: configuration.image.appMarkdownResolved(naturalSize: naturalSize),
            constrainedTo: constrainedWidth
        )
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
