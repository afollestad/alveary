import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testMarkdownAlerts() {
        assertMacSnapshot(
            markdownAlertsFixture(),
            size: CGSize(width: 460, height: 340),
            named: "markdown_alerts"
        )
    }

    func testMarkdownAlertsDark() {
        assertMacSnapshot(
            markdownAlertsFixture(),
            size: CGSize(width: 460, height: 340),
            named: "markdown_alerts_dark",
            colorScheme: .dark
        )
    }

    /// All five GitHub alert kinds plus a plain quote, so the accent bars and the untinted
    /// separator bar are compared side by side in one image.
    ///
    /// Each body is one short line on purpose — a wrapped line sitting at its break point moves
    /// between macOS versions and fails on CI (see this scope's coverage rules).
    private func markdownAlertsFixture() -> some View {
        let markdown = """
        > [!NOTE]
        > Useful information.

        > [!TIP]
        > Helpful advice.

        > [!IMPORTANT]
        > Key information.

        > [!WARNING]
        > Urgent content.

        > [!CAUTION]
        > Negative outcomes.

        > A plain quote.
        """
        return AppMarkdownText(markdown: markdown)
            .padding(16)
    }
}
