@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testHeaderLoadingSpinnerIsSmallerThanStatusSlot() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        header.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        header.configure(
            .init(
                summary: "Running tool",
                leadingIcon: .disclosure(isExpanded: false),
                phase: .loading
            )
        )
        header.layoutSubtreeIfNeeded()

        let spinner = try XCTUnwrap(header.descendants(of: AppKitStatusIndicatorSpinner.self).first)
        XCTAssertEqual(spinner.frame.width, 12)
        XCTAssertEqual(spinner.frame.height, 12)
    }
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
