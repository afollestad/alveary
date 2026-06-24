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
        try assertBasicAnimation(
            statusView.statusSymbolFadeOutAnimationForTesting,
            from: 1,
            to: 0
        )
    }

    func testLoadingCollapsedHeaderShowsDisclosureOnHoverWithoutSpinner() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        header.configure(
            .init(
                summary: "Running `swift test`",
                leadingIcon: .terminal,
                phase: .loading,
                isExpanded: false
            )
        )
        header.frame = NSRect(x: 0, y: 0, width: 220, height: 32)
        header.layoutSubtreeIfNeeded()

        let statusView = try XCTUnwrap(header.descendantsForDisclosureTests(of: AppKitTranscriptToolStatusIndicatorView.self).first)
        XCTAssertTrue(header.descendantsForDisclosureTests(of: AppKitStatusIndicatorSpinner.self).isEmpty)
        XCTAssertTrue(header.isSummaryPulseVisibleForTesting)
        XCTAssertNil(statusView.statusSymbolSystemNameForTesting)

        header.setDisclosureHoveredForTesting(true)

        try assertDisclosureSymbol(statusView, rotation: 0)
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
        try assertDisclosureSymbol(statusView, rotation: 0)

        statusView.performDisclosurePressForTesting()
        XCTAssertTrue(isExpanded)
        XCTAssertEqual(header.accessibilityValue() as? String, "expanded")
        try assertDisclosureSymbol(statusView, rotation: -.pi / 2, position: collapsedPosition)
        try assertBasicAnimation(
            statusView.statusSymbolRotationAnimationForTesting,
            from: 0,
            to: -.pi / 2
        )

        header.setDisclosureHoveredForTesting(false, animated: true)
        try assertDisclosureSymbol(statusView, rotation: -.pi / 2)
        XCTAssertNil(statusView.statusSymbolFadeOutAnimationForTesting)

        header.setDisclosureHoveredForTesting(true)
        statusView.performDisclosurePressForTesting()
        XCTAssertFalse(isExpanded)
        XCTAssertEqual(header.accessibilityValue() as? String, "collapsed")
        try assertDisclosureSymbol(statusView, rotation: 0, position: collapsedPosition)
        try assertBasicAnimation(
            statusView.statusSymbolRotationAnimationForTesting,
            from: -.pi / 2,
            to: 0
        )
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

@MainActor
private func assertDisclosureSymbol(
    _ statusView: AppKitTranscriptToolStatusIndicatorView,
    rotation expectedRotation: CGFloat,
    position expectedPosition: CGPoint? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    XCTAssertEqual(statusView.statusSymbolSystemNameForTesting, "chevron.right", file: file, line: line)
    XCTAssertEqual(statusView.statusSymbolRotationForTesting, expectedRotation, file: file, line: line)
    if let expectedPosition {
        XCTAssertEqual(
            try XCTUnwrap(statusView.statusSymbolLayerPositionForTesting, file: file, line: line),
            expectedPosition,
            file: file,
            line: line
        )
    }
}

private func assertBasicAnimation(
    _ animation: CABasicAnimation?,
    from expectedFromValue: CGFloat,
    to expectedToValue: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        XCTAssertNil(animation, file: file, line: line)
        return
    }

    let animation = try XCTUnwrap(animation, file: file, line: line)
    XCTAssertEqual(
        try XCTUnwrap(animationCGFloatValue(animation.fromValue), file: file, line: line),
        expectedFromValue,
        accuracy: 0.001,
        file: file,
        line: line
    )
    XCTAssertEqual(
        try XCTUnwrap(animationCGFloatValue(animation.toValue), file: file, line: line),
        expectedToValue,
        accuracy: 0.001,
        file: file,
        line: line
    )
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
