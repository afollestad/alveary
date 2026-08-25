@preconcurrency import AppKit
import XCTest

@testable import Alveary

/// Alert quotes measure to what they draw. The header is an extra block in the quote's child stack,
/// so a drift in either the header's geometry or its block spacing shows up as a height mismatch.
@MainActor
extension AppKitMarkdownLayoutMeasurerTests {
    func testAlertHeightMatchesHydratedRenderer() {
        assertMarkdownMeasurementParity(
            """
            > [!WARNING]
            > Do not merge yet, the release branch is frozen.
            """
        )
    }

    func testEveryAlertKindHeightMatchesHydratedRenderer() {
        for kind in AppMarkdownAlertKind.allCases {
            assertMarkdownMeasurementParity("> [!\(kind.rawValue.uppercased())]\n> Body text.")
        }
    }

    func testBodylessAlertHeightMatchesHydratedRenderer() {
        assertMarkdownMeasurementParity("> [!TIP]")
    }

    func testAlertWithBlockBodyHeightMatchesHydratedRenderer() {
        assertMarkdownMeasurementParity(
            """
            > [!CAUTION]
            > Lead paragraph that is long enough to wrap at this width and then some more text.
            >
            > - First item
            > - Second item
            """,
            width: 320
        )
    }

    func testPlainQuoteHeightStillMatchesHydratedRenderer() {
        assertMarkdownMeasurementParity(
            """
            > Not an alert, just a quote
            > spanning two lines.
            """
        )
    }
}
