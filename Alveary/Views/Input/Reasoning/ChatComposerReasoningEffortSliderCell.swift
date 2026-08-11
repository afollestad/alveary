import AppKit

@MainActor
final class ComposerReasoningEffortSliderCell: NSSliderCell {
    struct ResolvedColors {
        let accentTrack: NSColor
        let neutralTrack: NSColor
        let dot: NSColor
        let thumb: NSColor
        let thumbStroke: NSColor
    }

    override var knobThickness: CGFloat {
        ComposerReasoningEffortSliderMetrics.thumbDiameter
    }

    override init() {
        super.init()
        sliderType = .linear
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func barRect(flipped: Bool) -> NSRect {
        guard let slider = controlView as? ComposerReasoningEffortSlider else {
            return super.barRect(flipped: flipped)
        }
        return NSRect(
            x: slider.bounds.minX,
            y: slider.bounds.midY - ComposerReasoningEffortSliderMetrics.trackHeight / 2,
            width: slider.bounds.width,
            height: ComposerReasoningEffortSliderMetrics.trackHeight
        )
    }

    override func knobRect(flipped: Bool) -> NSRect {
        guard let slider = controlView as? ComposerReasoningEffortSlider else {
            return super.knobRect(flipped: flipped)
        }
        let center = slider.tickCenter(at: slider.displayedIndex)
        let diameter = ComposerReasoningEffortSliderMetrics.thumbDiameter
        return NSRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard controlView is ComposerReasoningEffortSlider else {
            super.draw(withFrame: cellFrame, in: controlView)
            return
        }
        drawBar(inside: barRect(flipped: controlView.isFlipped), flipped: controlView.isFlipped)
        drawTickMarks()
        drawKnob(knobRect(flipped: controlView.isFlipped))
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard let slider = controlView as? ComposerReasoningEffortSlider else {
            super.drawBar(inside: rect, flipped: flipped)
            return
        }
        let colors = resolvedColors(for: slider)
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: ComposerReasoningEffortSliderMetrics.trackHeight / 2,
            yRadius: ComposerReasoningEffortSliderMetrics.trackHeight / 2
        )
        colors.neutralTrack.setFill()
        path.fill()

        let knobCenterX = knobRect(flipped: flipped).midX
        let filledRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: max(0, min(rect.maxX, knobCenterX) - rect.minX),
            height: rect.height
        )
        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()
        colors.accentTrack.setFill()
        filledRect.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    override func drawTickMarks() {
        guard let slider = controlView as? ComposerReasoningEffortSlider else {
            super.drawTickMarks()
            return
        }
        let colors = resolvedColors(for: slider)
        colors.dot.setFill()
        for index in 0 ..< slider.effortTitles.count {
            let center = slider.tickCenter(at: index)
            let diameter = ComposerReasoningEffortSliderMetrics.dotDiameter
            NSBezierPath(ovalIn: NSRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )).fill()
        }
    }

    override func drawKnob(_ knobRect: NSRect) {
        guard let slider = controlView as? ComposerReasoningEffortSlider else {
            super.drawKnob(knobRect)
            return
        }
        let colors = resolvedColors(for: slider)
        let knobPath = NSBezierPath(ovalIn: knobRect)
        colors.thumb.setFill()
        knobPath.fill()
        colors.thumbStroke.setStroke()
        knobPath.lineWidth = 1
        knobPath.stroke()

        if slider.isPressed {
            NSColor.labelColor.appKitResolvedColor(in: slider, alpha: 0.08).setFill()
            knobPath.fill()
        }

        if slider.window?.firstResponder === slider, slider.isEnabled {
            AppAccentFill.primaryNSColor.appKitResolvedColor(in: slider, alpha: 0.45).setStroke()
            let focusPath = NSBezierPath(ovalIn: knobRect.insetBy(dx: 1.5, dy: 1.5))
            focusPath.lineWidth = 2
            focusPath.stroke()
        }
    }

    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        guard let slider = controlView as? ComposerReasoningEffortSlider else {
            return super.startTracking(at: startPoint, in: controlView)
        }
        slider.updateTrackingInteraction(to: slider.index(at: startPoint))
        return true
    }

    override func continueTracking(
        last lastPoint: NSPoint,
        current currentPoint: NSPoint,
        in controlView: NSView
    ) -> Bool {
        guard let slider = controlView as? ComposerReasoningEffortSlider else {
            return super.continueTracking(last: lastPoint, current: currentPoint, in: controlView)
        }
        slider.updateTrackingInteraction(to: slider.index(at: currentPoint), trackingPoint: currentPoint)
        return true
    }

    override func stopTracking(
        last lastPoint: NSPoint,
        current stopPoint: NSPoint,
        in controlView: NSView,
        mouseIsUp flag: Bool
    ) {
        if let slider = controlView as? ComposerReasoningEffortSlider {
            if flag {
                slider.updateTrackingInteraction(to: slider.index(at: stopPoint))
            } else {
                slider.cancelInteraction()
            }
        }
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
        if let slider = controlView as? ComposerReasoningEffortSlider, flag {
            // `NSSliderCell` may apply its native value mapping while stopping. Reapply
            // the snapped value so accessibility and drawing share the same integer.
            slider.updateTrackingInteraction(to: slider.displayedIndex)
        }
    }

    func resolvedColors(for slider: ComposerReasoningEffortSlider) -> ResolvedColors {
        let appearance = slider.appKitRenderingAppearance
        return ResolvedColors(
            accentTrack: AppAccentFill.primaryNSColor.resolved(for: appearance),
            neutralTrack: NSColor.unemphasizedSelectedContentBackgroundColor.resolved(for: appearance),
            dot: NSColor.labelColor.resolved(for: appearance).withAlphaComponent(ComposerReasoningEffortSliderMetrics.dotAlpha),
            thumb: NSColor.highlightColor.resolved(for: appearance),
            thumbStroke: NSColor.labelColor.resolved(for: appearance).withAlphaComponent(0.18)
        )
    }
}
