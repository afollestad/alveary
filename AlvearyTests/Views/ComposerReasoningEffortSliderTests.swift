import AppKit
import XCTest

@testable import Alveary

@MainActor
final class ComposerReasoningEffortSliderTests: XCTestCase {
    func testGeometryUsesOversizedMetricsAndInsetEndpointCenters() throws {
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High", "Extra high"],
            selectedIndex: 1
        )
        let cell = try XCTUnwrap(slider.cell as? ComposerReasoningEffortSliderCell)
        let trackRect = cell.barRect(flipped: slider.isFlipped)
        let knobRect = cell.knobRect(flipped: slider.isFlipped)
        let tickCenters = (0 ..< slider.effortTitles.count).map(slider.tickCenter(at:))

        XCTAssertEqual(slider.intrinsicContentSize.height, 33)
        XCTAssertEqual(slider.bounds, NSRect(x: 0, y: 0, width: 244, height: 33))
        XCTAssertEqual(trackRect, NSRect(x: 0, y: 6, width: 244, height: 21))
        XCTAssertEqual(knobRect.width, 25.5)
        XCTAssertEqual(knobRect.height, 25.5)
        XCTAssertEqual(ComposerReasoningEffortSliderMetrics.dotDiameter, 5.25)
        XCTAssertEqual(ComposerReasoningEffortSliderMetrics.dotAlpha, 0.72)
        XCTAssertEqual(tickCenters.first?.x, 12.75)
        XCTAssertEqual(tickCenters.last?.x, slider.bounds.maxX - 12.75)
        XCTAssertEqual(knobRect.midX, tickCenters[1].x)
        XCTAssertEqual(knobRect.midY, slider.bounds.midY)
        XCTAssertTrue(slider.hitTest(NSPoint(x: slider.bounds.minX, y: slider.bounds.midY)) === slider)
        XCTAssertTrue(slider.hitTest(NSPoint(x: slider.bounds.maxX - 0.5, y: slider.bounds.midY)) === slider)
    }

    func testDotsAndThumbStrokeUseSubtleLabelTints() throws {
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1
        )
        let resolvedDot = try XCTUnwrap(slider.debugResolvedColors.dot.usingColorSpace(.deviceRGB))
        let resolvedThumbStroke = try XCTUnwrap(slider.debugResolvedColors.thumbStroke.usingColorSpace(.deviceRGB))
        let resolvedLabel = try XCTUnwrap(
            NSColor.labelColor
                .resolved(for: slider.appKitRenderingAppearance)
                .usingColorSpace(.deviceRGB)
        )

        XCTAssertEqual(
            resolvedDot.alphaComponent,
            ComposerReasoningEffortSliderMetrics.dotAlpha,
            accuracy: 0.001
        )
        XCTAssertEqual(resolvedThumbStroke.alphaComponent, 0.18, accuracy: 0.001)
        for resolvedColor in [resolvedDot, resolvedThumbStroke] {
            XCTAssertEqual(resolvedColor.redComponent, resolvedLabel.redComponent, accuracy: 0.001)
            XCTAssertEqual(resolvedColor.greenComponent, resolvedLabel.greenComponent, accuracy: 0.001)
            XCTAssertEqual(resolvedColor.blueComponent, resolvedLabel.blueComponent, accuracy: 0.001)
        }
    }

    func testIndexSnapsToNearestTickAndClampsToEndpoints() {
        let slider = makeSlider(
            effortTitles: ["Minimal", "Low", "Medium", "High", "Extra high"],
            selectedIndex: 2
        )
        let centers = (0 ..< slider.effortTitles.count).map(slider.tickCenter(at:))
        let firstMidpoint = (centers[0].x + centers[1].x) / 2

        XCTAssertEqual(slider.index(at: NSPoint(x: -100, y: slider.bounds.midY)), 0)
        XCTAssertEqual(slider.index(at: NSPoint(x: firstMidpoint - 0.1, y: slider.bounds.midY)), 0)
        XCTAssertEqual(slider.index(at: NSPoint(x: firstMidpoint + 0.1, y: slider.bounds.midY)), 1)
        XCTAssertEqual(slider.index(at: centers[3]), 3)
        XCTAssertEqual(slider.index(at: NSPoint(x: slider.bounds.maxX + 100, y: slider.bounds.midY)), 4)
    }

    func testTrackingDeduplicatesPreviewsAndCommitsOnlyFinalChangedValue() {
        var previews: [Int] = []
        var commits: [Int] = []
        var cancelCount = 0
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High", "Extra high"],
            selectedIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) },
            onCancel: { cancelCount += 1 }
        )

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)
        slider.updateTrackingInteraction(to: 2)
        slider.updateTrackingInteraction(to: 99)
        slider.updateTrackingInteraction(to: 3)

        XCTAssertEqual(previews, [2, 3])
        XCTAssertTrue(slider.endTrackingInteraction(commit: true))
        XCTAssertEqual(commits, [3])
        XCTAssertEqual(slider.canonicalIndex, 3)
        XCTAssertEqual(slider.displayedIndex, 3)
        XCTAssertEqual(cancelCount, 0)
    }

    func testTrackingThatReturnsToItsStartingValueDoesNotCommit() {
        var previews: [Int] = []
        var commits: [Int] = []
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) }
        )

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)
        slider.updateTrackingInteraction(to: 1)

        XCTAssertFalse(slider.endTrackingInteraction(commit: true))
        XCTAssertEqual(previews, [2, 1])
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(slider.canonicalIndex, 1)
        XCTAssertEqual(slider.displayedIndex, 1)
    }

    func testCancelledTrackingRestoresCanonicalValueAndNotifiesOnce() {
        var previews: [Int] = []
        var commits: [Int] = []
        var cancelCount = 0
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High", "Extra high"],
            selectedIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) },
            onCancel: { cancelCount += 1 }
        )

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 3)

        XCTAssertFalse(slider.endTrackingInteraction(commit: false))
        XCTAssertEqual(previews, [3])
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(slider.canonicalIndex, 1)
        XCTAssertEqual(slider.displayedIndex, 1)
    }

    func testSliderCellCancelledTrackingRestoresCanonicalValueAndNotifiesOnce() throws {
        var previews: [Int] = []
        var commits: [Int] = []
        var cancelCount = 0
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) },
            onCancel: { cancelCount += 1 }
        )
        let cell = try XCTUnwrap(slider.cell as? ComposerReasoningEffortSliderCell)
        let destination = slider.tickCenter(at: 2)

        slider.beginTrackingInteraction(at: slider.tickCenter(at: 1))
        XCTAssertTrue(cell.startTracking(at: destination, in: slider))
        cell.stopTracking(
            last: destination,
            current: destination,
            in: slider,
            mouseIsUp: false
        )

        XCTAssertEqual(previews, [2])
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertFalse(slider.isTrackingInteraction)
        XCTAssertEqual(slider.canonicalIndex, 1)
        XCTAssertEqual(slider.displayedIndex, 1)
    }

    func testDiscreteStepsPreviewAndCommitOnceAtEachAvailableBoundary() {
        var previews: [Int] = []
        var commits: [Int] = []
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) }
        )

        XCTAssertTrue(slider.performDiscreteStep(by: -1))
        XCTAssertFalse(slider.performDiscreteStep(by: -1))
        XCTAssertTrue(slider.performDiscreteStep(by: 1))
        XCTAssertTrue(slider.performDiscreteStep(by: 1))
        XCTAssertFalse(slider.performDiscreteStep(by: 1))

        XCTAssertEqual(previews, [0, 1, 2])
        XCTAssertEqual(commits, [0, 1, 2])
        XCTAssertEqual(slider.canonicalIndex, 2)
        XCTAssertEqual(slider.displayedIndex, 2)
    }

    func testKeyDownLeftAndRightPerformOnePreviewCommitTransactionPerAvailableStep() {
        var previews: [Int] = []
        var commits: [Int] = []
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) }
        )

        slider.keyDown(with: effortSliderKeyEvent(keyCode: 123))
        slider.keyDown(with: effortSliderKeyEvent(keyCode: 123))
        slider.keyDown(with: effortSliderKeyEvent(keyCode: 124))
        slider.keyDown(with: effortSliderKeyEvent(keyCode: 124))
        slider.keyDown(with: effortSliderKeyEvent(keyCode: 124))

        XCTAssertEqual(previews, [0, 1, 2])
        XCTAssertEqual(commits, [0, 1, 2])
        XCTAssertEqual(slider.canonicalIndex, 2)
        XCTAssertEqual(slider.displayedIndex, 2)
    }

    func testAccessibilityIncrementAndDecrementPerformOnePreviewCommitTransactionPerAvailableStep() {
        var previews: [Int] = []
        var commits: [Int] = []
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) }
        )

        XCTAssertTrue(slider.accessibilityPerformIncrement())
        XCTAssertFalse(slider.accessibilityPerformIncrement())
        XCTAssertTrue(slider.accessibilityPerformDecrement())
        XCTAssertTrue(slider.accessibilityPerformDecrement())
        XCTAssertFalse(slider.accessibilityPerformDecrement())

        XCTAssertEqual(previews, [2, 1, 0])
        XCTAssertEqual(commits, [2, 1, 0])
        XCTAssertEqual(slider.canonicalIndex, 0)
        XCTAssertEqual(slider.displayedIndex, 0)
    }

    func testKeyDownEscapeCancelsActivePreviewWithoutCommit() {
        var previews: [Int] = []
        var commits: [Int] = []
        var cancelCount = 0
        var visibilityStates: [Bool] = []
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) },
            onCancel: { cancelCount += 1 },
            onDragDirectionVisibilityChanged: { visibilityStates.append($0) }
        )

        slider.beginTrackingInteraction(at: .zero, schedulesDragDirectionReveal: true)
        slider.updateTrackingInteraction(to: 2)
        XCTAssertTrue(slider.debugHasPendingDragDirectionReveal)

        slider.keyDown(with: effortSliderKeyEvent(keyCode: 53))

        XCTAssertEqual(previews, [2])
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertFalse(slider.isTrackingInteraction)
        XCTAssertFalse(slider.debugHasPendingDragDirectionReveal)
        XCTAssertEqual(slider.canonicalIndex, 1)
        XCTAssertEqual(slider.displayedIndex, 1)
        slider.fireDragDirectionRevealDelayForTesting()
        XCTAssertTrue(visibilityStates.isEmpty)
    }

    func testDragDirectionPresentationRequiresMovementAndDoesNotWrapKeyboardOrAccessibilitySteps() {
        var visibilityStates: [Bool] = []
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1,
            onDragDirectionVisibilityChanged: { visibilityStates.append($0) }
        )

        XCTAssertTrue(slider.performDiscreteStep(by: 1))
        XCTAssertTrue(slider.accessibilityPerformDecrement())
        XCTAssertTrue(visibilityStates.isEmpty)

        slider.beginTrackingInteraction(at: .zero)
        slider.updateTrackingInteraction(
            to: 2,
            trackingPoint: NSPoint(x: ComposerReasoningEffortSliderMetrics.dragDirectionRevealDistance - 0.1, y: 0)
        )
        XCTAssertTrue(visibilityStates.isEmpty)
        slider.updateTrackingInteraction(
            to: 2,
            trackingPoint: NSPoint(x: ComposerReasoningEffortSliderMetrics.dragDirectionRevealDistance, y: 0)
        )
        XCTAssertEqual(visibilityStates, [true])

        XCTAssertFalse(slider.endTrackingInteraction(commit: false))
        XCTAssertEqual(visibilityStates, [true, false])
    }

    func testQuickTrackClickDoesNotRevealDragDirections() {
        var visibilityStates: [Bool] = []
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1,
            onDragDirectionVisibilityChanged: { visibilityStates.append($0) }
        )

        slider.beginTrackingInteraction(at: NSPoint(x: 40, y: 20), schedulesDragDirectionReveal: true)
        slider.updateTrackingInteraction(to: 2)
        XCTAssertTrue(slider.debugHasPendingDragDirectionReveal)
        XCTAssertTrue(slider.endTrackingInteraction(commit: true))

        XCTAssertTrue(visibilityStates.isEmpty)
        XCTAssertFalse(slider.debugHasPendingDragDirectionReveal)
        slider.fireDragDirectionRevealDelayForTesting()
        XCTAssertTrue(visibilityStates.isEmpty)
    }

    func testStationaryHoldRevealsDragDirectionsAfterDelay() {
        var visibilityStates: [Bool] = []
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1,
            onDragDirectionVisibilityChanged: { visibilityStates.append($0) }
        )

        XCTAssertEqual(ComposerReasoningEffortSliderMetrics.dragDirectionRevealDelay, 0.15)
        slider.beginTrackingInteraction(at: NSPoint(x: 40, y: 20), schedulesDragDirectionReveal: true)
        slider.fireDragDirectionRevealDelayForTesting()

        XCTAssertEqual(visibilityStates, [true])
        XCTAssertTrue(slider.debugShowsDragDirections)
        XCTAssertFalse(slider.endTrackingInteraction(commit: true))
        XCTAssertEqual(visibilityStates, [true, false])
    }

    func testZeroOptionsHidesSliderAndRemovesItFromInteractionAndAccessibility() {
        let slider = makeSlider(effortTitles: [], selectedIndex: 4)

        XCTAssertTrue(slider.isHidden)
        XCTAssertFalse(slider.isEnabled)
        XCTAssertFalse(slider.acceptsFirstResponder)
        XCTAssertFalse(slider.isAccessibilityElement())
        XCTAssertFalse(slider.performDiscreteStep(by: 1))
        XCTAssertEqual(slider.numberOfTickMarks, 0)
    }

    func testOneOptionShowsCenteredDisabledSlider() throws {
        let slider = makeSlider(effortTitles: ["Medium"], selectedIndex: 10)
        let cell = try XCTUnwrap(slider.cell as? ComposerReasoningEffortSliderCell)
        let center = slider.tickCenter(at: 0)
        let knobRect = cell.knobRect(flipped: slider.isFlipped)

        XCTAssertFalse(slider.isHidden)
        XCTAssertFalse(slider.isEnabled)
        XCTAssertFalse(slider.acceptsFirstResponder)
        XCTAssertTrue(slider.isAccessibilityElement())
        XCTAssertEqual(slider.numberOfTickMarks, 1)
        XCTAssertEqual(center, NSPoint(x: slider.bounds.midX, y: slider.bounds.midY))
        XCTAssertEqual(knobRect.midX, slider.bounds.midX)
        XCTAssertEqual(knobRect.midY, slider.bounds.midY)
        XCTAssertEqual(slider.canonicalIndex, 0)
        XCTAssertFalse(slider.performDiscreteStep(by: 1))
    }

    func testChangedAuthoritativeConfigurationCancelsActivePreview() {
        var originalPreviews: [Int] = []
        var originalCommits: [Int] = []
        var originalCancelCount = 0
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High", "Extra high"],
            selectedIndex: 1,
            onPreview: { originalPreviews.append($0) },
            onCommit: { originalCommits.append($0) },
            onCancel: { originalCancelCount += 1 }
        )

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 3)
        slider.configure(
            effortTitles: ["Low", "Medium", "High", "Extra high"],
            selectedIndex: 2,
            isEnabled: true,
            onPreview: { _ in XCTFail("Authoritative configuration should not preview") },
            onCommit: { _ in XCTFail("Authoritative configuration should not commit") },
            onCancel: { XCTFail("Authoritative configuration should cancel silently") }
        )

        XCTAssertEqual(originalPreviews, [3])
        XCTAssertTrue(originalCommits.isEmpty)
        XCTAssertEqual(originalCancelCount, 0)
        XCTAssertFalse(slider.isTrackingInteraction)
        XCTAssertEqual(slider.canonicalIndex, 2)
        XCTAssertEqual(slider.displayedIndex, 2)
    }

    func testAccessibilityDescribesCurrentReasoningEffort() {
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1
        )

        XCTAssertEqual(slider.accessibilityRole(), .slider)
        XCTAssertEqual(slider.accessibilityLabel(), "Reasoning effort")
        XCTAssertEqual(slider.accessibilityHelp(), "Adjust reasoning effort")
        XCTAssertEqual(slider.accessibilityValueDescription(), "Medium")

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)

        XCTAssertEqual(slider.accessibilityValueDescription(), "High")
    }
}

@MainActor
func makeSlider(
    effortTitles: [String],
    selectedIndex: Int?,
    fallbackIndex: Int = 0,
    isEnabled: Bool = true,
    onPreview: @escaping (Int) -> Void = { _ in },
    onCommit: @escaping (Int) -> Void = { _ in },
    onCancel: @escaping () -> Void = {},
    onDragDirectionVisibilityChanged: @escaping (Bool) -> Void = { _ in }
) -> ComposerReasoningEffortSlider {
    let slider = ComposerReasoningEffortSlider(
        frame: NSRect(x: 0, y: 0, width: 244, height: ComposerReasoningEffortSliderMetrics.controlHeight)
    )
    slider.configure(
        effortTitles: effortTitles,
        selectedIndex: selectedIndex,
        fallbackIndex: fallbackIndex,
        isEnabled: isEnabled,
        onPreview: onPreview,
        onCommit: onCommit,
        onCancel: onCancel,
        onDragDirectionVisibilityChanged: onDragDirectionVisibilityChanged
    )
    return slider
}

@MainActor
private func effortSliderKeyEvent(keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: keyCode == 53 ? "\u{1b}" : "\t",
        charactersIgnoringModifiers: keyCode == 53 ? "\u{1b}" : "\t",
        isARepeat: false,
        keyCode: keyCode
    ) ?? NSEvent()
}
