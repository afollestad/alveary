@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testHeaderLoadingSpinnerIsSmallerThanStatusSlot() throws {
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

        let spinner = try XCTUnwrap(header.descendants(of: AppKitStatusIndicatorSpinner.self).first)
        let expectedColor = transcriptInlineToolRowColor.resolved(for: spinner.appKitRenderingAppearance)
        XCTAssertEqual(spinner.frame.width, metrics.statusIconSize)
        XCTAssertEqual(spinner.frame.height, metrics.statusIconSize)
        XCTAssertEqual(spinner.arcStrokeColorForTesting, expectedColor)
        XCTAssertEqual(
            spinner.trackStrokeColorForTesting,
            expectedColor.withAlphaComponent(expectedColor.alphaComponent * 0.25)
        )
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
