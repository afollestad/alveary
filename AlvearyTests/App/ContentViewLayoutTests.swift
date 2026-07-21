import SwiftUI
import XCTest

@testable import Alveary

final class ContentViewLayoutTests: XCTestCase {
    func testRightPaneBoundsReserveMainPaneWidth() {
        let bounds = RightPaneWidthPolicy.bounds(availableWidth: 1_000)

        XCTAssertEqual(bounds.lowerBound, AppSettings.supportedDiffViewerWidthRange.lowerBound)
        XCTAssertEqual(
            bounds.upperBound,
            1_000
                - RightPaneWidthPolicy.minimumMainPaneWidth
                - RightPaneWidthPolicy.resizeHandleThickness
        )
    }

    func testRightPaneBoundsNeverDropBelowSupportedLowerBound() {
        let bounds = RightPaneWidthPolicy.bounds(availableWidth: 500)

        XCTAssertEqual(bounds.lowerBound, AppSettings.supportedDiffViewerWidthRange.lowerBound)
        XCTAssertEqual(bounds.upperBound, AppSettings.supportedDiffViewerWidthRange.lowerBound)
    }

    func testRightPaneBoundsNeverExceedSupportedUpperBound() {
        let bounds = RightPaneWidthPolicy.bounds(availableWidth: 2_000)

        XCTAssertEqual(bounds.upperBound, AppSettings.supportedDiffViewerWidthRange.upperBound)
    }

    func testEffectiveRightPaneWidthClampsStoredWidthToAvailableSpace() {
        let width = RightPaneWidthPolicy.effectiveWidth(storedWidth: 960, availableWidth: 1_000)

        XCTAssertEqual(
            width,
            1_000
                - RightPaneWidthPolicy.minimumMainPaneWidth
                - RightPaneWidthPolicy.resizeHandleThickness
        )
    }

    func testEffectiveRightPaneWidthClampsStoredWidthToSupportedLowerBound() {
        let width = RightPaneWidthPolicy.effectiveWidth(storedWidth: 100, availableWidth: 1_000)

        XCTAssertEqual(width, AppSettings.supportedDiffViewerWidthRange.lowerBound)
    }

    func testPresentedRightPaneLaneIncludesResizeHandle() {
        let width = RightPaneWidthPolicy.presentationLaneWidth(paneWidth: 380, progress: 1)

        XCTAssertEqual(width, 380 + RightPaneWidthPolicy.resizeHandleThickness)
    }

    func testHiddenRightPaneLaneTakesNoLayoutSpace() {
        let width = RightPaneWidthPolicy.presentationLaneWidth(paneWidth: 380, progress: 0)

        XCTAssertEqual(width, 0)
    }

    func testRightPaneLaneAndOffsetAdvanceInSync() {
        let paneWidth: CGFloat = 380
        let laneWidth = RightPaneWidthPolicy.presentationLaneWidth(paneWidth: paneWidth, progress: 0.4)
        let offset = RightPaneWidthPolicy.presentationOffset(paneWidth: paneWidth, progress: 0.4)

        XCTAssertEqual(laneWidth + offset, paneWidth + RightPaneWidthPolicy.resizeHandleThickness)
    }

    func testRightPanePresentationIdentityIncludesSessionGeneration() {
        let destination = RightPaneDestination.skills(.newSkill)
        let first = RightPanePresentationIdentity(
            destination: destination,
            generation: UUID()
        )
        let reopened = RightPanePresentationIdentity(
            destination: destination,
            generation: UUID()
        )

        XCTAssertNotEqual(first, reopened)
    }

    @MainActor
    func testRightPaneInitializationDoesNotResolveObservablePresentationGeneration() {
        var generationResolutionCount = 0

        _ = ResizableRightPane(
            destination: RightPaneDestination.skills(.newSkill),
            width: .constant(380),
            onWidthCommit: { _ in },
            presentationGeneration: { _ in
                generationResolutionCount += 1
                return UUID()
            },
            onDismiss: { _, _ in },
            mainContent: { EmptyView() },
            paneContent: { _, _ in EmptyView() }
        )

        XCTAssertEqual(generationResolutionCount, 0)
    }

    func testRightPaneResizeRejectsAnInterruptedPreviousRouteDrag() {
        let captured = RightPanePresentationIdentity(
            destination: RightPaneDestination.skills(.newSkill),
            generation: UUID()
        )
        let active = RightPanePresentationIdentity(
            destination: RightPaneDestination.mcp(.addCustom),
            generation: UUID()
        )

        XCTAssertFalse(RightPanePresentationPolicy.canResize(
            active: active,
            displayed: captured,
            captured: captured
        ))
        XCTAssertFalse(RightPanePresentationPolicy.canResize(
            active: captured,
            displayed: active,
            captured: captured
        ))
        XCTAssertTrue(RightPanePresentationPolicy.canResize(
            active: captured,
            displayed: captured,
            captured: captured
        ))
    }

    func testReactivatingSamePresentationCancelsPendingDismissal() {
        let presentation = RightPanePresentationIdentity(
            destination: RightPaneDestination.skills(.newSkill),
            generation: UUID()
        )
        let otherPresentation = RightPanePresentationIdentity(
            destination: RightPaneDestination.mcp(.addCustom),
            generation: UUID()
        )

        XCTAssertTrue(RightPanePresentationPolicy.shouldCancelDismissal(
            active: presentation,
            pending: presentation
        ))
        XCTAssertFalse(RightPanePresentationPolicy.shouldCancelDismissal(
            active: presentation,
            pending: otherPresentation
        ))
        XCTAssertFalse(RightPanePresentationPolicy.shouldCancelDismissal(
            active: presentation,
            pending: nil
        ))
    }

    func testRightPaneDismissalTearsDownOnlyItsCapturedPresentation() {
        let dismissed = RightPanePresentationIdentity(
            destination: RightPaneDestination.skills(.newSkill),
            generation: UUID()
        )
        let reopened = RightPanePresentationIdentity(
            destination: RightPaneDestination.skills(.newSkill),
            generation: UUID()
        )

        XCTAssertTrue(RightPanePresentationPolicy.shouldTearDown(
            displayed: dismissed,
            completedDismissal: dismissed
        ))
        XCTAssertFalse(RightPanePresentationPolicy.shouldTearDown(
            displayed: reopened,
            completedDismissal: dismissed
        ))
        XCTAssertFalse(RightPanePresentationPolicy.shouldTearDown(
            displayed: nil,
            completedDismissal: dismissed
        ))
    }

    func testPaneFocusRestorationKeepsVisibleInvokingControl() {
        let resolved = ContextualPaneFocusRestoration.resolve(
            preferredID: "skills-details-visible",
            visibleTriggerIDs: ["skills-new", "skills-details-visible"],
            fallbackID: "skills-new"
        )

        XCTAssertEqual(resolved, "skills-details-visible")
    }

    func testPaneFocusRestorationFallsBackWhenInvokingControlDisappears() {
        let filteredRow = ContextualPaneFocusRestoration.resolve(
            preferredID: "scheduled-edit-filtered",
            visibleTriggerIDs: ["scheduled-new"],
            fallbackID: "scheduled-new"
        )
        let removedEmptyAction = ContextualPaneFocusRestoration.resolve(
            preferredID: "mcp-add-empty",
            visibleTriggerIDs: ["mcp-add", "mcp-edit-new-server"],
            fallbackID: "mcp-add"
        )

        XCTAssertEqual(filteredRow, "scheduled-new")
        XCTAssertEqual(removedEmptyAction, "mcp-add")
    }
}
