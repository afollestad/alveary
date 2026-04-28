import XCTest

@testable import Alveary

@MainActor
final class ChatBubbleLayoutTests: XCTestCase {
    func testAdaptiveTranscriptBubbleMaxWidthPrefersTwoThirdsOnWideTranscript() {
        XCTAssertEqual(adaptiveTranscriptBubbleMaxWidth(for: 1_200), 800)
    }

    func testAdaptiveTranscriptBubbleMaxWidthStopsAtTrailingInsetOnCompactTranscript() {
        XCTAssertEqual(adaptiveTranscriptBubbleMaxWidth(for: 620), 596)
    }

    func testTranscriptTypographyDerivesSizesFromSettings() {
        var settings = AppSettings()
        settings.chatFontSize = 18
        settings.codeFontFamily = "Monaco"
        settings.codeFontSize = 16

        let typography = TranscriptTypography(settings: settings)

        XCTAssertEqual(typography.chatFontSize, 18)
        XCTAssertEqual(typography.codeFontFamily, "Monaco")
        XCTAssertEqual(typography.codeFontSize, 16)
        XCTAssertEqual(typography.size(for: .body), 18)
        XCTAssertEqual(typography.size(for: .headline), 19)
        XCTAssertEqual(typography.size(for: .subheadline), 17)
        XCTAssertEqual(typography.size(for: .caption), 16)
        XCTAssertEqual(typography.size(for: .toolSummary), 17)
        XCTAssertEqual(typography.size(for: .approvalBody), 16)
    }

    func testToolStatusIndicatorDebouncerDelaysTerminalState() async throws {
        let debouncer = ToolStatusIndicatorDebouncer(
            initialPhase: .loading,
            debounceDelay: .milliseconds(50)
        )

        debouncer.update(to: .success)

        XCTAssertEqual(debouncer.displayedPhase, .loading)

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(debouncer.displayedPhase, .success)
    }

    func testToolStatusIndicatorDebouncerCancelsPendingTerminalStateWhenLoadingReturns() async throws {
        let debouncer = ToolStatusIndicatorDebouncer(
            initialPhase: .loading,
            debounceDelay: .milliseconds(80)
        )

        debouncer.update(to: .success)
        try await Task.sleep(for: .milliseconds(20))
        debouncer.update(to: .loading)

        XCTAssertEqual(debouncer.displayedPhase, .loading)

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(debouncer.displayedPhase, .loading)
    }
}
