@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testHeaderLoadingUsesPulsingSummaryInsteadOfStatusSpinner() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        var settings = AppSettings()
        settings.chatFontSize = 18
        let typography = TranscriptTypography(settings: settings)
        let metrics = transcriptInlineToolRowMetrics(for: typography)
        header.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        header.configure(
            .init(
                summary: "Running tool",
                leadingIcon: .genericTool,
                phase: .loading,
                typography: typography
            )
        )
        header.layoutSubtreeIfNeeded()

        let statusView = try XCTUnwrap(header.descendants(of: AppKitTranscriptToolStatusIndicatorView.self).first)
        let pulseColor = try XCTUnwrap(header.summaryPulseHighlightColorForTesting)
        let baseColor = transcriptInlineToolRowColor.resolved(for: header.appKitRenderingAppearance)

        XCTAssertTrue(header.descendants(of: AppKitStatusIndicatorSpinner.self).isEmpty)
        XCTAssertTrue(header.isSummaryPulseVisibleForTesting)
        XCTAssertEqual(
            try XCTUnwrap(header.summaryPulseMaskLocationsForTesting),
            [0.06, 0.24, 0.42, 0.60, 0.78].map(NSNumber.init(value:))
        )
        XCTAssertEqual(statusView.frame.width, metrics.controlSize)
        XCTAssertEqual(statusView.frame.height, metrics.controlSize)
        XCTAssertNil(statusView.statusSymbolSystemNameForTesting)
        XCTAssertNotEqual(pulseColor.resolved(for: header.appKitRenderingAppearance), baseColor)
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
