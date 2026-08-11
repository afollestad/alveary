import AppKit

extension AppKitChatSurfaceView {
    /// Picks the scroll view a wheel event belongs to, preferring the vertical transcript owner
    /// whenever the event is mostly vertical.
    ///
    /// The deepest-scroll-view rule alone would hand a vertical flick over a markdown table or code
    /// block to that nested horizontal scroll view, which then has to replay it upward — and AppKit
    /// drops the scroll momentum on the replay, so the transcript stops dead mid-gesture.
    func scrollViewForWheelForwarding(target: NSView, surfacePoint: NSPoint, event: NSEvent) -> NSScrollView? {
        if shouldPreferVerticalScrollOwner(for: event),
           let verticalScrollView = verticalScrollViewForWheelForwarding(target: target, surfacePoint: surfacePoint) {
            return verticalScrollView
        }
        return deepestScrollViewForWheelForwarding(target: target, surfacePoint: surfacePoint)
    }

    private func deepestScrollViewForWheelForwarding(target: NSView, surfacePoint: NSPoint) -> NSScrollView? {
        if let targetScrollView = target as? NSScrollView,
           let documentView = targetScrollView.documentView,
           convert(documentView.bounds, from: documentView).contains(surfacePoint),
           let nestedScrollView = deepestScrollViewForWheelForwarding(target: documentView, surfacePoint: surfacePoint) {
            return nestedScrollView
        }
        for subview in target.subviews.reversed() {
            let subviewFrame = convert(subview.bounds, from: subview)
            guard subviewFrame.contains(surfacePoint) else {
                continue
            }
            if let scrollView = deepestScrollViewForWheelForwarding(target: subview, surfacePoint: surfacePoint) {
                return scrollView
            }
        }
        return target as? NSScrollView ?? target.enclosingScrollView
    }

    private func verticalScrollViewForWheelForwarding(target: NSView, surfacePoint: NSPoint) -> NSScrollView? {
        if let scrollView = verticalScrollViewAncestor(from: target) {
            return scrollView
        }
        for subview in target.subviews.reversed() {
            let subviewFrame = convert(subview.bounds, from: subview)
            guard subviewFrame.contains(surfacePoint) else {
                continue
            }
            if let scrollView = verticalScrollViewForWheelForwarding(target: subview, surfacePoint: surfacePoint) {
                return scrollView
            }
        }
        return nil
    }

    private func verticalScrollViewAncestor(from view: NSView) -> NSScrollView? {
        var candidate: NSView? = view
        while let current = candidate {
            if let scrollView = current as? NSScrollView,
               scrollView.hasVerticalScroller {
                return scrollView
            }
            candidate = current.superview
        }
        return nil
    }

    private func shouldPreferVerticalScrollOwner(for event: NSEvent) -> Bool {
        let deltaY = abs(event.scrollingDeltaY)
        return deltaY > 0 && deltaY >= abs(event.scrollingDeltaX)
    }

}
