@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testCollapsedHeaderShowsDisclosureOnlyOnHoverAndFadesOnExit() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        header.configure(
            .init(
                summary: "Ran `swift test`",
                leadingIcon: .terminal,
                phase: .success,
                isExpanded: false
            )
        )
        header.frame = NSRect(x: 0, y: 0, width: 220, height: 32)
        header.layoutSubtreeIfNeeded()

        let statusView = try XCTUnwrap(header.descendantsForDisclosureTests(of: AppKitTranscriptToolStatusIndicatorView.self).first)
        XCTAssertNil(statusView.statusSymbolSystemNameForTesting)
        XCTAssertEqual(statusView.statusSymbolRotationForTesting, 0)

        header.setDisclosureHoveredForTesting(true)
        XCTAssertEqual(statusView.statusSymbolSystemNameForTesting, "chevron.right")
        XCTAssertEqual(statusView.statusSymbolRotationForTesting, 0)
        XCTAssertEqual(
            try XCTUnwrap(statusView.statusSymbolLayerPositionForTesting).x,
            statusView.bounds.width / 2,
            accuracy: 0.5
        )

        header.setDisclosureHoveredForTesting(false, animated: true)
        XCTAssertNil(statusView.statusSymbolSystemNameForTesting)
        XCTAssertEqual(statusView.statusSymbolRotationForTesting, 0)
        let fadeOutAnimation = try XCTUnwrap(statusView.statusSymbolFadeOutAnimationForTesting)
        XCTAssertEqual(try XCTUnwrap(animationCGFloatValue(fadeOutAnimation.fromValue)), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(animationCGFloatValue(fadeOutAnimation.toValue)), 0, accuracy: 0.001)
    }

    func testExpandedHeaderKeepsDisclosureVisibleAfterHoverExitAndRotatesOnPress() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        var isExpanded = false
        func configureHeader() {
            header.configure(
                .init(
                    summary: "Ran `swift test`",
                    leadingIcon: .terminal,
                    phase: .success,
                    isExpanded: isExpanded
                )
            )
        }
        header.onToggle = {
            isExpanded.toggle()
            configureHeader()
        }
        configureHeader()
        header.frame = NSRect(x: 0, y: 0, width: 220, height: 32)
        header.layoutSubtreeIfNeeded()

        let statusView = try XCTUnwrap(header.descendantsForDisclosureTests(of: AppKitTranscriptToolStatusIndicatorView.self).first)
        header.setDisclosureHoveredForTesting(true)
        header.layoutSubtreeIfNeeded()
        let collapsedPosition = try XCTUnwrap(statusView.statusSymbolLayerPositionForTesting)
        XCTAssertEqual(statusView.statusSymbolSystemNameForTesting, "chevron.right")
        XCTAssertEqual(statusView.statusSymbolRotationForTesting, 0)

        statusView.performDisclosurePressForTesting()
        XCTAssertTrue(isExpanded)
        XCTAssertEqual(header.accessibilityValue() as? String, "expanded")
        XCTAssertEqual(statusView.statusSymbolSystemNameForTesting, "chevron.right")
        XCTAssertEqual(statusView.statusSymbolRotationForTesting, -.pi / 2)
        XCTAssertEqual(try XCTUnwrap(statusView.statusSymbolLayerPositionForTesting), collapsedPosition)
        let expandAnimation = try XCTUnwrap(statusView.statusSymbolRotationAnimationForTesting)
        XCTAssertEqual(try XCTUnwrap(animationCGFloatValue(expandAnimation.fromValue)), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(animationCGFloatValue(expandAnimation.toValue)), -.pi / 2, accuracy: 0.001)

        header.setDisclosureHoveredForTesting(false, animated: true)
        XCTAssertEqual(statusView.statusSymbolSystemNameForTesting, "chevron.right")
        XCTAssertEqual(statusView.statusSymbolRotationForTesting, -.pi / 2)
        XCTAssertNil(statusView.statusSymbolFadeOutAnimationForTesting)

        header.setDisclosureHoveredForTesting(true)
        statusView.performDisclosurePressForTesting()
        XCTAssertFalse(isExpanded)
        XCTAssertEqual(header.accessibilityValue() as? String, "collapsed")
        XCTAssertEqual(statusView.statusSymbolSystemNameForTesting, "chevron.right")
        XCTAssertEqual(statusView.statusSymbolRotationForTesting, 0)
        XCTAssertEqual(try XCTUnwrap(statusView.statusSymbolLayerPositionForTesting), collapsedPosition)
        let collapseAnimation = try XCTUnwrap(statusView.statusSymbolRotationAnimationForTesting)
        XCTAssertEqual(try XCTUnwrap(animationCGFloatValue(collapseAnimation.fromValue)), -.pi / 2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(animationCGFloatValue(collapseAnimation.toValue)), 0, accuracy: 0.001)
    }
}

private extension NSView {
    func descendantsForDisclosureTests<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendantsForDisclosureTests(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

private func animationCGFloatValue(_ value: Any?) -> CGFloat? {
    if let value = value as? CGFloat {
        return value
    }
    if let value = value as? NSNumber {
        return CGFloat(truncating: value)
    }
    return nil
}
