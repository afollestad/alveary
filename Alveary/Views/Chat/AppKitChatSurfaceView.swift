import AppKit
import SwiftUI

/// Native owner for the active chat surface layout.
///
/// `ChatView` still builds the current SwiftUI content-mode view during the
/// migration, but this view owns the vertical content/composer split, mounts
/// the native composer panel directly, and hoists the visible composer
/// autocomplete popup into a surface-level overlay.
final class AppKitChatSurfaceView: NSView {
    private weak var contentView: NSView?
    private weak var composerView: NSView?
    private weak var surfaceAutocompletePopupView: AppKitComposerAutocompletePopupView?
    private let autocompleteEventCaptureView = AutocompleteSurfaceEventCaptureView()
    private var trackingArea: NSTrackingArea?
    private var mouseDownMonitor: ChatSurfaceLocalEventMonitor?

    private struct AutocompletePopupSource {
        let popup: AppKitComposerAutocompletePopupView
        let frame: NSRect
    }

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
            removeSurfaceAutocompletePopup()
            composerView = newComposerView
            configureHostedInvalidation(newComposerView)
            addSubview(newComposerView)
        }

        needsLayout = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        updateSurfaceAutocompletePopup()
        if let popupHit = hitTestSurfaceAutocomplete(at: point) {
            return popupHit
        }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMouseDownMonitor()
    }

    override func mouseMoved(with event: NSEvent) {
        let localPoint = convert(mouseEventWindowPoint(event), from: nil)
        if routeMouseMovedToComposerAutocomplete(at: localPoint, event: event) {
            return
        }
        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(mouseEventWindowPoint(event), from: nil)
        if routeMouseDownToComposerAutocomplete(at: localPoint, event: event) {
            return
        }
        dismissComposerAutocompleteIfNeeded(at: localPoint)
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let localPoint = convert(scrollEventWindowPoint(event), from: nil)
        if routeScrollWheelToComposerAutocomplete(at: localPoint, event: event) {
            return
        }
        forwardScrollWheelOutsideComposerAutocomplete(event)
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
        composerView.layoutSubtreeIfNeeded()
        updateSurfaceAutocompletePopup()
    }

    @discardableResult
    func routeMouseMovedToComposerAutocomplete(at point: NSPoint, event: NSEvent) -> Bool {
        updateSurfaceAutocompletePopup()
        guard let popup = visibleComposerAutocompletePopup() else {
            return false
        }
        return popup.routeMouseMoved(at: popup.convert(point, from: self), event: event)
    }

    @discardableResult
    func routeMouseDownToComposerAutocomplete(at point: NSPoint, event: NSEvent) -> Bool {
        updateSurfaceAutocompletePopup()
        guard let popup = visibleComposerAutocompletePopup() else {
            return false
        }
        return popup.routeMouseDown(at: popup.convert(point, from: self), event: event)
    }

    @discardableResult
    func routeScrollWheelToComposerAutocomplete(at point: NSPoint, event: NSEvent) -> Bool {
        updateSurfaceAutocompletePopup()
        guard let popup = visibleComposerAutocompletePopup() else {
            return false
        }
        return popup.routeScrollWheel(at: popup.convert(point, from: self), event: event)
    }

    func consumeScrollWheelEventIfInsideComposerAutocomplete(_ event: NSEvent) -> NSEvent? {
        consumeScrollWheelEventIfInsideComposerAutocomplete(event, windowPoints: [scrollEventWindowPoint(event)])
    }

    func consumeScrollWheelEventIfInsideComposerAutocomplete(_ event: NSEvent, windowPoint: NSPoint) -> NSEvent? {
        consumeScrollWheelEventIfInsideComposerAutocomplete(event, windowPoints: [windowPoint])
    }

    private func consumeScrollWheelEventIfInsideComposerAutocomplete(
        _ event: NSEvent,
        windowPoints: [NSPoint]
    ) -> NSEvent? {
        updateSurfaceAutocompletePopup()
        guard let popup = visibleComposerAutocompletePopup() else {
            return event
        }
        let surfacePoints = windowPoints.map { convert($0, from: nil) }
        guard let popupPoint = popupPointForScrollEvent(surfacePoints: surfacePoints, in: popup) else {
            return event
        }
        _ = popup.routeScrollWheel(at: popupPoint, event: event)
        return nil
    }

    private func popupPointForScrollEvent(surfacePoints: [NSPoint], in popup: AppKitComposerAutocompletePopupView) -> NSPoint? {
        for surfacePoint in surfacePoints {
            guard popup.frame.contains(surfacePoint) else {
                continue
            }
            return popup.convert(surfacePoint, from: self)
        }
        return nil
    }

    private func scrollEventWindowPoint(_ event: NSEvent) -> NSPoint {
        if let eventWindow = event.window, eventWindow === window {
            return eventWindow.mouseLocationOutsideOfEventStream
        }
        if let window {
            return window.mouseLocationOutsideOfEventStream
        }
        return event.locationInWindow
    }

    func mouseEventWindowPoint(_ event: NSEvent) -> NSPoint {
        // Continued scroll gestures can leave the next click carrying a stale event location; use AppKit's
        // live mouse point so the outside-click monitor does not dismiss before row selection.
        event.window === window ? window?.mouseLocationOutsideOfEventStream ?? event.locationInWindow : event.locationInWindow
    }

    func forwardScrollWheelOutsideComposerAutocomplete(_ event: NSEvent) {
        let surfacePoint = convert(scrollEventWindowPoint(event), from: nil)
        if let contentView,
           convert(contentView.bounds, from: contentView).contains(surfacePoint),
           let scrollView = scrollViewForWheelForwarding(target: contentView, surfacePoint: surfacePoint) {
            scrollView.scrollWheel(with: event)
            return
        }
        guard let target = hitTest(surfacePoint),
              target !== self,
              target !== autocompleteEventCaptureView else {
            super.scrollWheel(with: event)
            return
        }
        if let scrollView = scrollViewForWheelForwarding(target: target, surfacePoint: surfacePoint) {
            scrollView.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func scrollViewForWheelForwarding(target: NSView, surfacePoint: NSPoint) -> NSScrollView? {
        if let scrollView = target as? NSScrollView ?? target.enclosingScrollView {
            return scrollView
        }
        for subview in target.subviews.reversed() {
            let subviewFrame = convert(subview.bounds, from: subview)
            guard subviewFrame.contains(surfacePoint) else {
                continue
            }
            if let scrollView = scrollViewForWheelForwarding(target: subview, surfacePoint: surfacePoint) {
                return scrollView
            }
        }
        return nil
    }

    private func visibleComposerAutocompletePopup() -> AppKitComposerAutocompletePopupView? {
        guard let popup = surfaceAutocompletePopupView,
              popup.superview === self,
              !popup.isHidden else {
            return nil
        }
        return popup
    }

    private func hitTestSurfaceAutocomplete(at point: NSPoint) -> NSView? {
        guard let popup = visibleComposerAutocompletePopup() else {
            return nil
        }
        guard popup.frame.contains(point) else {
            return nil
        }
        return autocompleteEventCaptureView
    }

    @discardableResult
    func dismissComposerAutocompleteIfClickOutside(_ event: NSEvent) -> NSEvent {
        guard event.window === window else {
            return event
        }
        let localPoint = convert(mouseEventWindowPoint(event), from: nil)
        dismissComposerAutocompleteIfNeeded(at: localPoint)
        return event
    }

    private func dismissComposerAutocompleteIfNeeded(at point: NSPoint) {
        updateSurfaceAutocompletePopup()
        guard let popup = visibleComposerAutocompletePopup(),
              !popup.frame.contains(point),
              let composerView,
              let bodyView = visibleComposerBody(in: composerView) else {
            return
        }
        bodyView.dismissAutocomplete()
        updateSurfaceAutocompletePopup()
    }

    private func updateMouseDownMonitor() {
        guard window != nil else {
            removeMouseDownMonitor()
            return
        }
        guard mouseDownMonitor == nil else {
            return
        }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.dismissComposerAutocompleteIfClickOutside(event) ?? event
        }
        mouseDownMonitor = ChatSurfaceLocalEventMonitor(monitor)
    }

    private func removeMouseDownMonitor() {
        mouseDownMonitor = nil
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

    private func updateSurfaceAutocompletePopup() {
        guard let source = composerAutocompletePopupSource() else {
            removeSurfaceAutocompletePopup()
            return
        }

        let popup = source.popup
        if popup.superview !== self {
            popup.removeFromSuperview()
            addSubview(popup, positioned: .above, relativeTo: nil)
        }
        popup.frame = source.frame
        popup.needsLayout = true
        popup.layoutSubtreeIfNeeded()
        surfaceAutocompletePopupView = popup
        updateMouseDownMonitor()

        autocompleteEventCaptureView.configure(popup: popup)
        autocompleteEventCaptureView.frame = source.frame
        if autocompleteEventCaptureView.superview !== self || subviews.last !== autocompleteEventCaptureView {
            autocompleteEventCaptureView.removeFromSuperview()
            addSubview(autocompleteEventCaptureView, positioned: .above, relativeTo: nil)
        }
    }

    private func composerAutocompletePopupSource() -> AutocompletePopupSource? {
        guard let composerView else {
            return nil
        }
        if let bodyView = visibleComposerBody(in: composerView),
           let frame = bodyView.autocompletePopupFrame(in: self),
           !frame.isEmpty {
            return AutocompletePopupSource(popup: bodyView.autocompletePopupView, frame: frame)
        }
        if let popup = visibleAutocompletePopup(in: composerView),
           !popup.bounds.isEmpty {
            return AutocompletePopupSource(popup: popup, frame: convert(popup.bounds, from: popup))
        }
        if let popup = surfaceAutocompletePopupView,
           popup.superview === self,
           !popup.isHidden,
           !popup.bounds.isEmpty {
            return AutocompletePopupSource(popup: popup, frame: popup.frame)
        }
        return nil
    }

    private func removeSurfaceAutocompletePopup() {
        guard let popup = surfaceAutocompletePopupView else {
            return
        }
        if popup.superview === self {
            popup.removeFromSuperview()
        }
        autocompleteEventCaptureView.removeFromSuperview()
        surfaceAutocompletePopupView = nil
        removeMouseDownMonitor()
    }

    private func visibleComposerBody(in view: NSView) -> AppKitChatComposerBodyView? {
        if let bodyView = view as? AppKitChatComposerBodyView,
           !bodyView.isHidden {
            return bodyView
        }
        for subview in view.subviews where !subview.isHidden {
            if let match = visibleComposerBody(in: subview) {
                return match
            }
        }
        return nil
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
