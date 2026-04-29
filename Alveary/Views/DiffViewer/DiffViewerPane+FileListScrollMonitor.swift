import AppKit
import SwiftUI

struct DiffViewerFileListScrollMonitor: NSViewRepresentable {
    let fileIDs: [String]
    @Binding var verticalOffsetFromTop: CGFloat

    func makeNSView(context: Context) -> DiffViewerFileListScrollMonitorView {
        let view = DiffViewerFileListScrollMonitorView()
        view.fileIDs = fileIDs
        view.onVerticalOffsetChange = { verticalOffsetFromTop = $0 }
        return view
    }

    func updateNSView(_ nsView: DiffViewerFileListScrollMonitorView, context: Context) {
        nsView.onVerticalOffsetChange = { verticalOffsetFromTop = $0 }
        nsView.update(fileIDs: fileIDs)
    }

    static func dismantleNSView(_ nsView: DiffViewerFileListScrollMonitorView, coordinator: ()) {
        nsView.dismantle()
    }
}

@MainActor
final class DiffViewerFileListScrollMonitorView: NSView {
    var onVerticalOffsetChange: ((CGFloat) -> Void)?
    var fileIDs: [String] = []

    private weak var observedScrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?
    private var liveScrollObserver: NSObjectProtocol?
    private var lastKnownVerticalOffsetFromTop: CGFloat = 0
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
            removeBoundsObserver()
        } else {
            scheduleScrollStateRefresh(scrollToTopAfterContentChange: false)
        }
    }

    func update(fileIDs: [String]) {
        let didChangeFiles = self.fileIDs != fileIDs
        let shouldPreserveTop = didChangeFiles && lastKnownVerticalOffsetFromTop <= 1
        self.fileIDs = fileIDs
        scheduleScrollStateRefresh(scrollToTopAfterContentChange: shouldPreserveTop)
    }

    func dismantle() {
        removeBoundsObserver()
    }

    private func scheduleScrollStateRefresh(scrollToTopAfterContentChange: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshScrollState(scrollToTopAfterContentChange: scrollToTopAfterContentChange)
        }
    }

    private func refreshScrollState(scrollToTopAfterContentChange: Bool) {
        guard let scrollView = monitoredScrollView() else {
            setVerticalOffsetFromTop(0)
            // SwiftUI can create the List's backing NSScrollView after this monitor
            // appears, so retry briefly instead of permanently reporting top.
            retryScrollStateRefreshIfNeeded(scrollToTopAfterContentChange: scrollToTopAfterContentChange)
            return
        }

        unresolvedRefreshAttempts = 0
        observe(scrollView)
        if scrollToTopAfterContentChange {
            scrollToTop(scrollView)
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self,
                      let scrollView else {
                    return
                }
                self.scrollToTop(scrollView)
                self.updateVerticalOffset(scrollView)
            }
        } else {
            updateVerticalOffset(scrollView)
        }
    }

    private func observe(_ scrollView: NSScrollView) {
        guard observedScrollView !== scrollView else {
            return
        }

        removeBoundsObserver()
        observedScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            Task { @MainActor in
                guard let self,
                      let scrollView else {
                    return
                }
                self.updateVerticalOffset(scrollView)
            }
        }
        liveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            Task { @MainActor in
                guard let self,
                      let scrollView else {
                    return
                }
                self.updateVerticalOffset(scrollView)
            }
        }
    }

    private func removeBoundsObserver() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        if let liveScrollObserver {
            NotificationCenter.default.removeObserver(liveScrollObserver)
            self.liveScrollObserver = nil
        }
        observedScrollView = nil
    }

    private func retryScrollStateRefreshIfNeeded(scrollToTopAfterContentChange: Bool) {
        guard window != nil,
              unresolvedRefreshAttempts < 5 else {
            return
        }

        unresolvedRefreshAttempts += 1
        DispatchQueue.main.async { [weak self] in
            self?.refreshScrollState(scrollToTopAfterContentChange: scrollToTopAfterContentChange)
        }
    }

    private func updateVerticalOffset(_ scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else {
            setVerticalOffsetFromTop(0)
            return
        }

        let topY = topContentOriginY(scrollView: scrollView, documentView: documentView)
        let currentY = scrollView.contentView.bounds.origin.y
        let originOffset = documentView.isFlipped ? currentY - topY : topY - currentY
        // List-backed scroll views can expose stale clip bounds during live scroll.
        // The scroller value gives a second y-offset signal for the divider fade.
        let scrollerOffset = CGFloat(scrollView.verticalScroller?.doubleValue ?? 0) * scrollableHeight(
            scrollView: scrollView,
            documentView: documentView
        )
        let offset = max(originOffset, scrollerOffset)
        setVerticalOffsetFromTop(max(offset, 0))
    }

    private func setVerticalOffsetFromTop(_ verticalOffsetFromTop: CGFloat) {
        guard abs(lastKnownVerticalOffsetFromTop - verticalOffsetFromTop) > 0.5 else {
            return
        }
        lastKnownVerticalOffsetFromTop = verticalOffsetFromTop
        onVerticalOffsetChange?(verticalOffsetFromTop)
    }

    private func scrollToTop(_ scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else {
            return
        }

        let topY = topContentOriginY(scrollView: scrollView, documentView: documentView)
        let origin = NSPoint(x: scrollView.contentView.bounds.origin.x, y: topY)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        setVerticalOffsetFromTop(0)
    }

    private func topContentOriginY(scrollView: NSScrollView, documentView: NSView) -> CGFloat {
        if documentView.isFlipped {
            return 0
        }

        return max(documentView.bounds.height - scrollView.contentView.bounds.height, 0)
    }

    private func scrollableHeight(scrollView: NSScrollView, documentView: NSView) -> CGFloat {
        max(documentView.bounds.height - scrollView.contentView.bounds.height, 0)
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

    private func monitoredScrollView() -> NSScrollView? {
        enclosingScrollView() ?? overlappingScrollView()
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
        // The representable is mounted as SwiftUI background content; it is often
        // a sibling of the List's NSScrollView, not a descendant, so choose by overlap.
        return contentView
            .descendantScrollViews()
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
                let lhsIntersectionArea = lhsRect.intersection(monitorRect).area
                let rhsIntersectionArea = rhsRect.intersection(monitorRect).area

                if lhsIntersectionArea != rhsIntersectionArea {
                    return lhsIntersectionArea < rhsIntersectionArea
                }

                return lhsRect.area > rhsRect.area
            }
    }
}

private extension NSView {
    func descendantScrollViews() -> [NSScrollView] {
        var scrollViews: [NSScrollView] = []
        collectDescendantScrollViews(into: &scrollViews)
        return scrollViews
    }

    func collectDescendantScrollViews(into scrollViews: inout [NSScrollView]) {
        if let scrollView = self as? NSScrollView {
            scrollViews.append(scrollView)
        }

        for subview in subviews {
            subview.collectDescendantScrollViews(into: &scrollViews)
        }
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isEmpty else {
            return 0
        }

        return width * height
    }
}
