import AppKit
import SwiftUI

enum DiffViewerTopListKeyCode {
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
}

struct DiffViewerTopListKeyboardMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onKeyDown: @MainActor (NSEvent) -> Bool

    func makeNSView(context: Context) -> DiffViewerTopListKeyboardMonitorView {
        let view = DiffViewerTopListKeyboardMonitorView()
        view.isEnabled = isEnabled
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: DiffViewerTopListKeyboardMonitorView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onKeyDown = onKeyDown
        nsView.scheduleScrollViewRefresh()
    }

    static func dismantleNSView(_ nsView: DiffViewerTopListKeyboardMonitorView, coordinator: ()) {
        nsView.dismantle()
    }
}

@MainActor
final class DiffViewerTopListKeyboardMonitorView: NSView {
    var isEnabled = false
    var onKeyDown: ((NSEvent) -> Bool)?

    private weak var monitoredScrollView: NSScrollView?
    private var eventMonitor: Any?
    private var unresolvedRefreshAttempts = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventMonitor()
            monitoredScrollView = nil
        } else {
            installEventMonitor()
            scheduleScrollViewRefresh()
        }
    }

    func scheduleScrollViewRefresh() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshScrollView()
        }
    }

    func dismantle() {
        removeEventMonitor()
        monitoredScrollView = nil
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else {
            return
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            guard self.shouldHandle(event),
                  self.onKeyDown?(event) == true else {
                return event
            }
            return nil
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else {
            return
        }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard isEnabled,
              event.window === window else {
            return false
        }

        guard let responderView = window?.firstResponder as? NSView,
              !responderView.diffViewerIsTextInputResponder,
              let scrollView = monitoredScrollView ?? resolvedScrollView() else {
            return false
        }

        return responderView.isDescendant(of: scrollView)
    }

    private func refreshScrollView() {
        guard let scrollView = resolvedScrollView() else {
            retryScrollViewRefreshIfNeeded()
            return
        }

        unresolvedRefreshAttempts = 0
        monitoredScrollView = scrollView
    }

    private func retryScrollViewRefreshIfNeeded() {
        guard window != nil,
              unresolvedRefreshAttempts < 5 else {
            return
        }

        unresolvedRefreshAttempts += 1
        DispatchQueue.main.async { [weak self] in
            self?.refreshScrollView()
        }
    }

    private func resolvedScrollView() -> NSScrollView? {
        enclosingScrollView() ?? overlappingScrollView()
    }

    private func enclosingScrollView() -> NSScrollView? {
        var currentView: NSView? = self
        while let view = currentView {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            currentView = view.superview
        }
        return nil
    }

    private func overlappingScrollView() -> NSScrollView? {
        guard let contentView = window?.contentView else {
            return nil
        }

        let monitorRect = convert(bounds, to: nil)
        guard !monitorRect.isEmpty else {
            return nil
        }

        let monitorCenter = NSPoint(x: monitorRect.midX, y: monitorRect.midY)
        return contentView
            .diffViewerDescendantScrollViews()
            .filter { scrollView in
                guard scrollView.documentView != nil else {
                    return false
                }

                let scrollRect = scrollView.convert(scrollView.bounds, to: nil)
                return scrollRect.contains(monitorCenter) || scrollRect.intersects(monitorRect)
            }
            .max { lhs, rhs in
                let lhsRect = lhs.convert(lhs.bounds, to: nil)
                let rhsRect = rhs.convert(rhs.bounds, to: nil)
                let lhsIntersectionArea = lhsRect.intersection(monitorRect).diffViewerArea
                let rhsIntersectionArea = rhsRect.intersection(monitorRect).diffViewerArea

                if lhsIntersectionArea != rhsIntersectionArea {
                    return lhsIntersectionArea < rhsIntersectionArea
                }

                return lhsRect.diffViewerArea > rhsRect.diffViewerArea
            }
    }
}

private extension NSView {
    func diffViewerDescendantScrollViews() -> [NSScrollView] {
        var scrollViews: [NSScrollView] = []
        collectDiffViewerDescendantScrollViews(into: &scrollViews)
        return scrollViews
    }

    func collectDiffViewerDescendantScrollViews(into scrollViews: inout [NSScrollView]) {
        if let scrollView = self as? NSScrollView {
            scrollViews.append(scrollView)
        }

        for subview in subviews {
            subview.collectDiffViewerDescendantScrollViews(into: &scrollViews)
        }
    }

    func isDescendant(of ancestor: NSView) -> Bool {
        var currentView: NSView? = self
        while let view = currentView {
            if view === ancestor {
                return true
            }
            currentView = view.superview
        }
        return false
    }

    var diffViewerIsTextInputResponder: Bool {
        self is NSText
    }
}

private extension NSRect {
    var diffViewerArea: CGFloat {
        guard !isEmpty else {
            return 0
        }

        return width * height
    }
}
