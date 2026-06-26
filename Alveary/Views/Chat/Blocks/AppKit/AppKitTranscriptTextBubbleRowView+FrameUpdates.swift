@preconcurrency import AppKit
import QuartzCore

struct TextBubbleSynchronizedFrameAnimation {
    let view: NSView
    let startFrame: NSRect
    let targetFrame: NSRect
}

@MainActor
protocol AppKitTranscriptFrameAnimatable: AnyObject {
    func prepareSynchronizedFrameAnimation(from previousFrame: NSRect, to targetFrame: NSRect)
    func animateSynchronizedFrameChange()
    func finishSynchronizedFrameAnimation()
}

@MainActor
final class AppKitTranscriptExpandableClipView: NSView {
    private var targetFrame: NSRect?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    func updateFrame(width: CGFloat, targetHeight: CGFloat) {
        let updatedFrame = NSRect(
            x: 0,
            y: 0,
            width: max(width, 0),
            height: max(targetHeight, 0)
        )
        guard targetFrame == nil else {
            targetFrame = updatedFrame
            return
        }
        frame = updatedFrame
    }

    func prepareVisibleHeightAnimation(from startHeight: CGFloat, to targetHeight: CGFloat, width: CGFloat) {
        let targetFrame = NSRect(
            x: 0,
            y: 0,
            width: max(width, 0),
            height: max(targetHeight, 0)
        )
        self.targetFrame = targetFrame
        frame = NSRect(
            x: targetFrame.minX,
            y: targetFrame.minY,
            width: targetFrame.width,
            height: max(startHeight, 0)
        )
    }

    func animateVisibleHeightChange() {
        guard let targetFrame else {
            return
        }
        animator().frame = targetFrame
    }

    func finishVisibleHeightAnimation() {
        guard let targetFrame else {
            return
        }
        frame = targetFrame
        self.targetFrame = nil
    }

    var isAnimatingVisibleHeight: Bool {
        targetFrame != nil
    }

#if DEBUG
    var visibleHeightForTesting: CGFloat {
        frame.height
    }
#endif
}

extension AppKitTranscriptTextBubbleRowView: AppKitTranscriptFrameAnimatable {
    func prepareSynchronizedFrameAnimation(from previousFrame: NSRect, to targetFrame: NSRect) {
        guard let targetMetrics = lastLayoutMetrics,
              targetMetrics.overflows,
              abs(previousFrame.height - targetFrame.height) > 0.5 else {
            synchronizedFrameAnimations = []
            return
        }

        let startMetrics = layoutMetrics(targetMetrics, fittingBubbleHeight: previousFrame.height)
        let startUpdates = frameUpdates(for: startMetrics)
        let targetUpdates = frameUpdates(for: targetMetrics)
        synchronizedFrameAnimations = startUpdates.compactMap { startUpdate in
            guard let targetUpdate = targetUpdates.first(where: { $0.view === startUpdate.view }),
                  startUpdate.frame != targetUpdate.frame else {
                return nil
            }
            return TextBubbleSynchronizedFrameAnimation(
                view: startUpdate.view,
                startFrame: startUpdate.frame,
                targetFrame: targetUpdate.frame
            )
        }

        applyFrameUpdates(startUpdates, animated: false)
        updateCollapsedFadeMask(isCollapsed: targetMetrics.isCollapsed)
    }

    func animateSynchronizedFrameChange() {
        for animation in synchronizedFrameAnimations {
            animation.view.animator().frame = animation.targetFrame
        }
    }

    func finishSynchronizedFrameAnimation() {
        let animations = synchronizedFrameAnimations
        synchronizedFrameAnimations = []
        for animation in animations {
            animation.view.frame = animation.targetFrame
        }
        if let lastLayoutMetrics {
            applyFrameUpdates(frameUpdates(for: lastLayoutMetrics), animated: false)
            updateCollapsedFadeMask(isCollapsed: lastLayoutMetrics.isCollapsed)
        }
    }

    func frameUpdates(for metrics: TextBubbleLayoutMetrics) -> [(view: NSView, frame: NSRect)] {
        var frameUpdates: [(view: NSView, frame: NSRect)] = [
            (imageAttachmentStripView, metrics.imageStripFrame ?? .zero),
            (bubbleView, metrics.bubbleFrame),
            (markdownClipView, metrics.markdownClipFrame)
        ]
        if let markdownView {
            frameUpdates.append((markdownView, metrics.markdownFrame))
        }
        if metrics.overflows {
            frameUpdates.append((expansionButton, expansionButtonFrame(markdownClipFrame: metrics.markdownClipFrame)))
        }
        return frameUpdates
    }

    func layoutMetrics(
        _ metrics: TextBubbleLayoutMetrics,
        fittingBubbleHeight bubbleHeight: CGFloat
    ) -> TextBubbleLayoutMetrics {
        let toggleHeight = max(textBubbleToggleMinHeight, ceil(expansionButton.fittingSize.height))
        let visibleMarkdownHeight = max(
            0,
            bubbleHeight - (chatBubbleVerticalPadding * 2) - textBubbleControlClearance - textBubbleControlSpacing - toggleHeight
        )
        return TextBubbleLayoutMetrics(
            imageStripFrame: metrics.imageStripFrame,
            bubbleFrame: NSRect(
                x: metrics.bubbleFrame.minX,
                y: metrics.bubbleFrame.minY,
                width: metrics.bubbleFrame.width,
                height: bubbleHeight
            ),
            hasBubble: metrics.hasBubble,
            markdownClipFrame: NSRect(
                x: metrics.markdownClipFrame.minX,
                y: metrics.markdownClipFrame.minY,
                width: metrics.markdownClipFrame.width,
                height: min(visibleMarkdownHeight, metrics.markdownFrame.height)
            ),
            markdownFrame: metrics.markdownFrame,
            overflows: metrics.overflows,
            isCollapsed: metrics.isCollapsed
        )
    }

    func applyFrameUpdates(_ updates: [(view: NSView, frame: NSRect)], animated: Bool) {
        let animatedUpdates = updates.filter { update in
            animated && update.view.frame != .zero && update.view.frame != update.frame
        }
        let animatedViewIDs = Set(animatedUpdates.map { ObjectIdentifier($0.view) })
        let immediateUpdates = updates.filter { update in
            !animatedViewIDs.contains(ObjectIdentifier(update.view))
        }
        immediateUpdates.forEach { $0.view.frame = $0.frame }
        guard !animatedUpdates.isEmpty else {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = appExpansionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for update in animatedUpdates {
                update.view.animator().frame = update.frame
            }
        } completionHandler: {
            Task { @MainActor in
                for update in animatedUpdates {
                    update.view.frame = update.frame
                }
            }
        }
    }
}
