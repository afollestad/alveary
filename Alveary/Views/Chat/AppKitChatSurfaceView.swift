import AppKit
import SwiftUI

/// Native owner for the active chat surface layout.
///
/// `ChatView` still builds the current SwiftUI content-mode view and composer
/// panel during the migration, but this view owns their vertical frames. That
/// keeps the transcript, empty/trust states, and composer in one AppKit layout
/// pass before later phases move more composer chrome out of SwiftUI.
final class AppKitChatSurfaceView: NSView {
    private weak var contentView: NSView?
    private weak var composerView: NSView?

    override var isFlipped: Bool {
        true
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

    private func measuredComposerHeight(for composerView: NSView, width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return max(0, ceil(composerView.fittingSize.height))
        }

        // NSHostingView reports the composer's fitting height for its current
        // width, so measure after applying the chat surface width. This avoids
        // the composer inheriting a stale wrapping width from the previous pass.
        if composerView.frame.width != width {
            composerView.frame.size.width = width
            composerView.needsLayout = true
        }
        composerView.layoutSubtreeIfNeeded()

        return max(0, ceil(composerView.fittingSize.height))
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
}

/// Thin SwiftUI bridge that lets `ChatView` continue to produce stateful child
/// views while AppKit owns the active chat surface's parent layout.
struct AppKitChatSurfaceRepresentable: NSViewRepresentable {
    let content: AnyView
    let composer: AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content, composer: composer)
    }

    func makeNSView(context: Context) -> AppKitChatSurfaceView {
        let view = AppKitChatSurfaceView()
        view.configure(
            contentView: context.coordinator.contentHost,
            composerView: context.coordinator.composerHost
        )
        return view
    }

    func updateNSView(_ nsView: AppKitChatSurfaceView, context: Context) {
        context.coordinator.update(content: content, composer: composer)
        nsView.configure(
            contentView: context.coordinator.contentHost,
            composerView: context.coordinator.composerHost
        )
    }
}

extension AppKitChatSurfaceRepresentable {
    @MainActor
    final class Coordinator {
        let contentHost: AppKitChatSurfaceHostingView
        let composerHost: AppKitChatSurfaceHostingView

        init(content: AnyView, composer: AnyView) {
            contentHost = AppKitChatSurfaceHostingView(rootView: content)
            composerHost = AppKitChatSurfaceHostingView(rootView: composer)
        }

        func update(content: AnyView, composer: AnyView) {
            contentHost.rootView = content
            composerHost.rootView = composer
        }
    }
}

/// `NSHostingView` subclass that forwards SwiftUI intrinsic-size invalidations
/// to the AppKit parent that is responsible for splitting transcript/composer
/// frames.
@MainActor
final class AppKitChatSurfaceHostingView: NSHostingView<AnyView> {
    var onPreferredSizeInvalidated: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onPreferredSizeInvalidated?()
    }
}
