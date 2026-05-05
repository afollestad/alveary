@preconcurrency import AppKit

extension AppKitTextView {
    /// Sizes the text container before AppKit performs layout-dependent measurement or drawing.
    @discardableResult
    func updateTextContainerForCurrentBounds() -> Bool {
        let containerWidth = safeTextContainerWidth
        guard containerWidth.isFinite,
              containerWidth > 0,
              let textContainer else {
            return false
        }

        layoutManager?.allowsNonContiguousLayout = false

        let containerSize = textContainer.containerSize
        guard !containerSize.width.isFinite || abs(containerSize.width - containerWidth) > 0.5 else {
            return true
        }

        textContainer.containerSize = NSSize(
            width: containerWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textLayoutReadyForDrawing = false
        return true
    }

    /// Returns whether layout-dependent drawing can safely run without mutating text layout during paint.
    func prepareForSafeTextLayout() -> Bool {
        let containerWidth = safeTextContainerWidth
        guard containerWidth.isFinite,
              containerWidth > 0,
              let textContainer else {
            return false
        }

        let currentWidth = textContainer.containerSize.width
        return currentWidth.isFinite
            && currentWidth > 0
            && abs(currentWidth - containerWidth) <= 0.5
    }

    /// Marks the next draw pass as unsafe until measurement/layout primes the layout manager again.
    func markTextLayoutNeedsPriming() {
        textLayoutReadyForDrawing = false
        textLayoutPrimedWidth = 0
    }

    /// Primes text layout before user interaction tries to draw selection or caret state.
    func primeTextLayoutForInteraction() {
        updateTextContainerForCurrentBounds()
        primeTextLayoutForDrawing()
    }

    /// Performs the layout manager work that `draw(_:)` must not do during AppKit display.
    @discardableResult
    func primeTextLayoutForDrawing() -> Bool {
        guard prepareForSafeTextLayout(),
              let layoutManager,
              let textContainer else {
            textLayoutReadyForDrawing = false
            return false
        }

        layoutManager.ensureLayout(for: textContainer)
        textLayoutReadyForDrawing = true
        textLayoutPrimedWidth = safeTextContainerWidth
        return true
    }

    /// Returns whether `NSTextView.draw(_:)` can run without filling layout holes during paint.
    func canDrawTextLayoutSafely() -> Bool {
        string.isEmpty ||
            (
                textLayoutReadyForDrawing &&
                    prepareForSafeTextLayout() &&
                    abs(textLayoutPrimedWidth - safeTextContainerWidth) <= 0.5
            )
    }

    var isTextLayoutReadyForDrawingForTesting: Bool {
        canDrawTextLayoutSafely()
    }

    private var safeTextContainerWidth: CGFloat {
        max(bounds.width - (textContainerInset.width * 2), 0)
    }
}
