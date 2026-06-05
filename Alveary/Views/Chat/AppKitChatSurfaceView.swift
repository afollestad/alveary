import AppKit
import QuartzCore
import SwiftUI

/// Native owner for the active chat surface layout.
final class AppKitChatSurfaceView: NSView {
    private weak var contentView: NSView?
    private weak var composerView: NSView?
    private var composerHeightAnimationID: UUID?
    private var animatedComposerHeight: CGFloat?
    private var animationBoundsSize = NSSize.zero
    private let composerHeightAnimationDuration: TimeInterval = 0.18

#if DEBUG
    var disableHeightAnimationForTesting = false
#endif

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
            cancelComposerHeightAnimation()
            clearHostedInvalidation(composerView)
            composerView?.removeFromSuperview()
            composerView = newComposerView
            configureHostedInvalidation(newComposerView)
            addSubview(newComposerView)
        }

        needsLayout = true
    }

    override func scrollWheel(with event: NSEvent) {
        forwardScrollWheelOutsideComposer(event)
    }

    override func layout() {
        super.layout()

        guard let contentView, let composerView else {
            return
        }

        if animatedComposerHeight != nil, animationBoundsSize != bounds.size {
            cancelComposerHeightAnimation()
        }
        let composerHeight = animatedComposerHeight ?? measuredComposerHeight(for: composerView, width: bounds.width)
        applySurfaceLayout(contentView: contentView, composerView: composerView, composerHeight: composerHeight)
    }

    func layoutPreferredComposerHeightChange(animated: Bool = true) {
        guard let contentView, let composerView else {
            layoutSubtreeIfNeeded()
            return
        }
        let targetHeight = measuredComposerHeight(for: composerView, width: bounds.width)
        let currentHeight = composerView.frame.height > 0 ? composerView.frame.height : targetHeight
        cancelComposerHeightAnimation()

        guard animated,
              shouldAnimateHeightChange,
              abs(currentHeight - targetHeight) > 0.5
        else {
            animatedComposerHeight = nil
            applySurfaceLayout(contentView: contentView, composerView: composerView, composerHeight: targetHeight)
            return
        }

        animatedComposerHeight = currentHeight
        animationBoundsSize = bounds.size
        startComposerHeightAnimation(
            contentView: contentView,
            composerView: composerView,
            from: currentHeight,
            to: targetHeight
        )
    }

    func scrollEventWindowPoint(_ event: NSEvent) -> NSPoint {
        return event.locationInWindow
    }

    func forwardScrollWheelOutsideComposer(_ event: NSEvent) {
        let surfacePoint = convert(scrollEventWindowPoint(event), from: nil)
        let target = hitTest(surfacePoint)
        if let contentView,
           convert(contentView.bounds, from: contentView).contains(surfacePoint),
           let target,
           target.isDescendant(of: contentView),
           let scrollView = scrollViewForWheelForwarding(target: contentView, surfacePoint: surfacePoint, event: event) {
            scrollView.scrollWheel(with: event)
            return
        }
        guard let target,
              target !== self else {
            super.scrollWheel(with: event)
            return
        }
        if isSurfaceOverlayTarget(target) {
            target.scrollWheel(with: event)
            return
        }
        if let scrollView = scrollViewForWheelForwarding(target: target, surfacePoint: surfacePoint, event: event) {
            scrollView.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func isSurfaceOverlayTarget(_ target: NSView) -> Bool {
        if let contentView,
           target.isDescendant(of: contentView) {
            return false
        }
        if let composerView,
           target.isDescendant(of: composerView) {
            return false
        }
        return true
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

    private var shouldAnimateHeightChange: Bool {
#if DEBUG
        guard !disableHeightAnimationForTesting else {
            return false
        }
#endif
        return window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func startComposerHeightAnimation(
        contentView: NSView,
        composerView: NSView,
        from startHeight: CGFloat,
        to targetHeight: CGFloat
    ) {
        let animationID = UUID()
        composerHeightAnimationID = animationID
        let state = ComposerHeightAnimationState(
            id: animationID,
            startTime: CACurrentMediaTime(),
            startHeight: startHeight,
            targetHeight: targetHeight
        )
        advanceComposerHeightAnimation(
            contentView: contentView,
            composerView: composerView,
            state: state
        )
    }

    private func advanceComposerHeightAnimation(
        contentView: NSView,
        composerView: NSView,
        state: ComposerHeightAnimationState
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 / 60.0)) { [weak self, weak contentView, weak composerView] in
            MainActor.assumeIsolated {
                guard let self,
                      self.composerHeightAnimationID == state.id,
                      let contentView,
                      let composerView
                else {
                    return
                }
                let elapsed = CACurrentMediaTime() - state.startTime
                let progress = min(max(elapsed / self.composerHeightAnimationDuration, 0), 1)
                let easedProgress = self.easeInEaseOut(progress)
                let height = state.startHeight + ((state.targetHeight - state.startHeight) * easedProgress)
                self.animatedComposerHeight = progress < 1 ? height : nil
                self.applySurfaceLayout(contentView: contentView, composerView: composerView, composerHeight: height)
                if progress >= 1 {
                    self.composerHeightAnimationID = nil
                    self.applySurfaceLayout(contentView: contentView, composerView: composerView, composerHeight: state.targetHeight)
                    return
                }
                self.advanceComposerHeightAnimation(
                    contentView: contentView,
                    composerView: composerView,
                    state: state
                )
            }
        }
    }

    private func cancelComposerHeightAnimation() {
        composerHeightAnimationID = nil
        animatedComposerHeight = nil
    }

    private func applySurfaceLayout(contentView: NSView, composerView: NSView, composerHeight: CGFloat) {
        let width = bounds.width
        let height = bounds.height
        let resolvedComposerHeight = min(max(0, ceil(composerHeight)), height)
        let contentHeight = max(0, height - resolvedComposerHeight)

        contentView.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)
        composerView.frame = NSRect(x: 0, y: contentHeight, width: width, height: resolvedComposerHeight)
        contentView.needsLayout = true
        composerView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
        composerView.layoutSubtreeIfNeeded()
    }

    private func easeInEaseOut(_ progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        let eased = clamped * clamped * (3 - (2 * clamped))
        return CGFloat(eased)
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

private struct ComposerHeightAnimationState {
    let id: UUID
    let startTime: CFTimeInterval
    let startHeight: CGFloat
    let targetHeight: CGFloat
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
