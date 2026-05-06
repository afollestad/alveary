import AppKit
import QuartzCore

@MainActor
extension AppKitTranscriptDocumentLayoutView {
    func setDocumentSize(_ size: CGSize) {
        frame.size = size
        bottomSpacerView.frame = CGRect(x: 0, y: max(size.height - 1, 0), width: size.width, height: 1)
    }

    func applyFrameUpdates(
        _ updates: [RowFrameUpdate],
        animated: Bool,
        targetDocumentSize: CGSize
    ) {
        isApplyingFrameUpdates = true
        defer { isApplyingFrameUpdates = false }

        guard animated else {
            updates.forEach { $0.view.frame = $0.frame }
            setDocumentSize(targetDocumentSize)
            activeFrameAnimationTargetDocumentSize = nil
            return
        }

        let animatedUpdates = updates.filter { update in
            guard let previousFrame = update.previousFrame else {
                return false
            }
            return previousFrame.width > 0 && previousFrame.height > 0 && previousFrame != update.frame
        }
        let animatedViewIDs = Set(animatedUpdates.map { ObjectIdentifier($0.view) })
        updates
            .filter { !animatedViewIDs.contains(ObjectIdentifier($0.view)) }
            .forEach { $0.view.frame = $0.frame }
        guard !animatedUpdates.isEmpty else {
            setDocumentSize(targetDocumentSize)
            activeFrameAnimationTargetDocumentSize = nil
            return
        }
        runFrameAnimation(animatedUpdates, targetDocumentSize: targetDocumentSize)
    }

    private func runFrameAnimation(
        _ animatedUpdates: [RowFrameUpdate],
        targetDocumentSize: CGSize
    ) {
        hasActiveFrameAnimation = true
        activeFrameAnimationTargetDocumentSize = targetDocumentSize
        NSAnimationContext.runAnimationGroup { context in
            context.duration = appExpansionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for update in animatedUpdates {
                if let previousFrame = update.previousFrame {
                    update.view.frame = previousFrame
                    (update.view as? AppKitTranscriptFrameAnimatable)?.prepareSynchronizedFrameAnimation(from: previousFrame, to: update.frame)
                }
                update.view.animator().frame = update.frame
                (update.view as? AppKitTranscriptFrameAnimatable)?.animateSynchronizedFrameChange()
            }
        } completionHandler: {
            Task { @MainActor in
                self.finishFrameAnimation(animatedUpdates, targetDocumentSize: targetDocumentSize)
            }
        }
    }

    private func finishFrameAnimation(
        _ animatedUpdates: [RowFrameUpdate],
        targetDocumentSize: CGSize
    ) {
        setDocumentSize(targetDocumentSize)
        for update in animatedUpdates {
            update.view.frame = update.frame
            (update.view as? AppKitTranscriptFrameAnimatable)?.finishSynchronizedFrameAnimation()
        }
        hasActiveFrameAnimation = false
        activeFrameAnimationTargetDocumentSize = nil
        let completions = activeFrameAnimationCompletions
        activeFrameAnimationCompletions = []
        completions.forEach { $0() }
    }
}
