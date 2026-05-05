import AppKit
import SwiftUI

/// Native owner for the active chat surface layout.
///
/// `ChatView` still builds the current SwiftUI content-mode view and inner
/// composer content during the migration, but this view owns their vertical
/// frames and mounts the native composer panel shell directly.
final class AppKitChatSurfaceView: NSView {
    private weak var contentView: NSView?
    private weak var composerView: NSView?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupClipping()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupClipping()
    }

    func configure(contentView newContentView: NSView, composerView newComposerView: NSView) {
        if contentView !== newContentView {
            clearHostedInvalidation(contentView)
            contentView?.removeFromSuperview()
            contentView = newContentView
            configureHostedInvalidation(newContentView)
            addSubview(newContentView)
        }

        if composerView !== newComposerView {
            clearHostedInvalidation(composerView)
            composerView?.removeFromSuperview()
            composerView = newComposerView
            configureHostedInvalidation(newComposerView)
            addSubview(newComposerView)
        }

        needsLayout = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The autocomplete popup is mounted inside the composer but floats upward
        // over transcript space, so route it before the surface clips normal hits.
        if let autocompleteHitView = hitTestComposerAutocomplete(point) {
            return autocompleteHitView
        }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()

        guard let contentView, let composerView else {
            return
        }

        let width = bounds.width
        let height = bounds.height
        let composerHeight = measuredComposerHeight(for: composerView, width: width)
        let contentHeight = max(0, height - composerHeight)

        contentView.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)
        composerView.frame = NSRect(x: 0, y: contentHeight, width: width, height: composerHeight)
    }

    private func hitTestComposerAutocomplete(_ point: NSPoint) -> NSView? {
        guard let composerView,
              let popup = visibleAutocompletePopup(in: composerView) else {
            return nil
        }
        let popupPoint = popup.convert(point, from: self)
        guard popup.bounds.contains(popupPoint) else {
            return nil
        }
        return popup.hitTest(popupPoint)
    }

    private func measuredComposerHeight(for composerView: NSView, width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return max(0, ceil(composerView.fittingSize.height))
        }

        if composerView.frame.width != width {
            composerView.frame.size.width = width
            composerView.needsLayout = true
        }
        composerView.layoutSubtreeIfNeeded()

        if let panelView = composerView as? AppKitChatComposerPanelView {
            return max(0, ceil(panelView.fittingSize.height))
        }

        return max(0, ceil(composerView.fittingSize.height))
    }

    private func visibleAutocompletePopup(in view: NSView) -> AppKitComposerAutocompletePopupView? {
        if let popup = view as? AppKitComposerAutocompletePopupView,
           !popup.isHidden {
            return popup
        }
        for subview in view.subviews {
            if let match = visibleAutocompletePopup(in: subview) {
                return match
            }
        }
        return nil
    }

    private func configureHostedInvalidation(_ view: NSView) {
        guard let hostedView = view as? AppKitChatSurfaceHostingView else {
            return
        }
        hostedView.onPreferredSizeInvalidated = { [weak self] in
            self?.needsLayout = true
        }
    }

    private func clearHostedInvalidation(_ view: NSView?) {
        guard let hostedView = view as? AppKitChatSurfaceHostingView else {
            return
        }
        hostedView.onPreferredSizeInvalidated = nil
    }

    private func setupClipping() {
        // Hosted SwiftUI content can draw outside the AppKit frame we assign
        // during the transcript/composer split. Clip at this boundary so empty
        // states and transcript content cannot bleed under thread tabs.
        wantsLayer = true
        layer?.masksToBounds = true
    }
}

/// Thin SwiftUI bridge that lets `ChatView` continue to produce stateful child
/// views while AppKit owns the active chat surface's parent layout.
struct AppKitChatSurfaceRepresentable: NSViewRepresentable {
    let content: AnyView
    let composerConfiguration: AppKitChatComposerPanelConfiguration

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content, composerConfiguration: composerConfiguration)
    }

    func makeNSView(context: Context) -> AppKitChatSurfaceView {
        let view = AppKitChatSurfaceView()
        view.configure(
            contentView: context.coordinator.contentHost,
            composerView: context.coordinator.composerPanelView
        )
        return view
    }

    func updateNSView(_ nsView: AppKitChatSurfaceView, context: Context) {
        context.coordinator.update(content: content, composerConfiguration: composerConfiguration)
        nsView.configure(
            contentView: context.coordinator.contentHost,
            composerView: context.coordinator.composerPanelView
        )
    }
}

extension AppKitChatSurfaceRepresentable {
    @MainActor
    final class Coordinator {
        let contentHost: AppKitChatSurfaceHostingView
        let composerPanelView: AppKitChatComposerPanelView

        init(content: AnyView, composerConfiguration: AppKitChatComposerPanelConfiguration) {
            contentHost = AppKitChatSurfaceHostingView(rootView: content)
            composerPanelView = AppKitChatComposerPanelView()
            contentHost.configureChatSurfaceSizing()
            composerPanelView.configure(composerConfiguration)
        }

        func update(content: AnyView, composerConfiguration: AppKitChatComposerPanelConfiguration) {
            contentHost.rootView = content
            composerPanelView.configure(composerConfiguration)
        }
    }
}

/// `NSHostingView` subclass that forwards SwiftUI intrinsic-size invalidations
/// to the AppKit parent that is responsible for splitting transcript/composer
/// frames.
@MainActor
final class AppKitChatSurfaceHostingView: NSHostingView<AnyView> {
    var onPreferredSizeInvalidated: (() -> Void)?

    func configureChatSurfaceSizing() {
        // The AppKit surface supplies concrete child frames. Disabling the
        // hosting view's min/max sizing constraints prevents a SwiftUI ideal
        // width from pushing the composer outside narrow AppKit bounds.
        sizingOptions = [.intrinsicContentSize]
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onPreferredSizeInvalidated?()
    }
}
