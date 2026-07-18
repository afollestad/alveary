import XCTest

@testable import Alveary

@MainActor
extension ComposerReasoningEffortSliderTests {
    func testUnmatchedFallbackClickPreviewsAndCommitsDespiteUnchangedThumbPosition() {
        var previews: [Int] = []
        var commits: [Int] = []
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: nil,
            fallbackIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) }
        )

        XCTAssertEqual(slider.canonicalIndex, 1)
        XCTAssertEqual(slider.displayedIndex, 1)
        XCTAssertFalse(slider.debugCanonicalValueIsRepresented)

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 1)

        XCTAssertTrue(slider.endTrackingInteraction(commit: true))
        XCTAssertEqual(previews, [1])
        XCTAssertEqual(commits, [1])
        XCTAssertTrue(slider.debugCanonicalValueIsRepresented)
    }

    func testUnmatchedDragAwayAndBackCommitsFallbackOnce() {
        var previews: [Int] = []
        var commits: [Int] = []
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: nil,
            fallbackIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) }
        )

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)
        slider.updateTrackingInteraction(to: 1)

        XCTAssertTrue(slider.endTrackingInteraction(commit: true))
        XCTAssertEqual(previews, [2, 1])
        XCTAssertEqual(commits, [1])
        XCTAssertEqual(slider.canonicalIndex, 1)
        XCTAssertTrue(slider.debugCanonicalValueIsRepresented)
    }

    func testCancellingUnmatchedInteractionRestoresFallbackWithoutRepresentingIt() {
        var previews: [Int] = []
        var commits: [Int] = []
        var cancelCount = 0
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: nil,
            fallbackIndex: 1,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) },
            onCancel: { cancelCount += 1 }
        )

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)

        XCTAssertFalse(slider.endTrackingInteraction(commit: false))
        XCTAssertEqual(previews, [2])
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(slider.displayedIndex, 1)
        XCTAssertFalse(slider.debugCanonicalValueIsRepresented)
    }

    func testUnmatchedBoundaryKeyboardAndAccessibilityStepsSelectFallback() {
        var keyboardCommits: [Int] = []
        let keyboardSlider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: nil,
            onCommit: { keyboardCommits.append($0) }
        )

        XCTAssertTrue(keyboardSlider.performDiscreteStep(by: -1))
        XCTAssertFalse(keyboardSlider.performDiscreteStep(by: -1))
        XCTAssertEqual(keyboardCommits, [0])

        var accessibilityCommits: [Int] = []
        let accessibilitySlider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: nil,
            onCommit: { accessibilityCommits.append($0) }
        )

        XCTAssertTrue(accessibilitySlider.accessibilityPerformDecrement())
        XCTAssertFalse(accessibilitySlider.accessibilityPerformDecrement())
        XCTAssertTrue(accessibilitySlider.accessibilityPerformIncrement())
        XCTAssertEqual(accessibilityCommits, [0, 1])
    }

    func testEquivalentUnmatchedConfigurationPreservesPreviewAndRepresentedUpdateCancelsIt() {
        let slider = makeSlider(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: nil,
            fallbackIndex: 1
        )
        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)

        slider.configure(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: nil,
            fallbackIndex: 1,
            isEnabled: true,
            onPreview: { _ in },
            onCommit: { _ in },
            onCancel: {}
        )

        XCTAssertTrue(slider.isTrackingInteraction)
        XCTAssertEqual(slider.displayedIndex, 2)
        XCTAssertFalse(slider.debugCanonicalValueIsRepresented)

        slider.configure(
            effortTitles: ["Low", "Medium", "High"],
            selectedIndex: 1,
            fallbackIndex: 1,
            isEnabled: true,
            onPreview: { _ in },
            onCommit: { _ in },
            onCancel: {}
        )

        XCTAssertFalse(slider.isTrackingInteraction)
        XCTAssertEqual(slider.displayedIndex, 1)
        XCTAssertTrue(slider.debugCanonicalValueIsRepresented)
    }

    func testUnmatchedSingleOptionRemainsInert() {
        var previews: [Int] = []
        var commits: [Int] = []
        let slider = makeSlider(
            effortTitles: ["Medium"],
            selectedIndex: nil,
            onPreview: { previews.append($0) },
            onCommit: { commits.append($0) }
        )

        XCTAssertFalse(slider.isEnabled)
        XCTAssertFalse(slider.acceptsFirstResponder)
        XCTAssertFalse(slider.debugCanonicalValueIsRepresented)

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 0)

        XCTAssertFalse(slider.endTrackingInteraction(commit: true))
        XCTAssertTrue(previews.isEmpty)
        XCTAssertTrue(commits.isEmpty)
        XCTAssertFalse(slider.debugCanonicalValueIsRepresented)
        XCTAssertFalse(slider.isEnabled)
        XCTAssertFalse(slider.acceptsFirstResponder)
    }
}
