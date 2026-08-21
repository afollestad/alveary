@preconcurrency import AppKit
import XCTest

@testable import Alveary

/// Disclosure measurement.
///
/// A `<details>` block is the one markdown block whose height changes after it is drawn, so these
/// tests are what stand between a collapse and a pane that keeps reserving the expanded height —
/// dead space under the last comment in the pull request pane.
extension AppKitMarkdownLayoutMeasurerTests {
    private static let detailsMarkdown = """
        Intro paragraph.

        <details><summary>Test run logs</summary>

        Hidden paragraph one.

        - hidden bullet
        - another hidden bullet

        </details>

        Trailing paragraph.
        """

    func testCollapsedDetailsHeightMatchesHydratedRenderer() {
        AppMarkdownDetailsExpansionStore.removeAll()

        assertMarkdownMeasurementParity(Self.detailsMarkdown)
    }

    func testExpandedDetailsHeightMatchesHydratedRenderer() {
        AppMarkdownDetailsExpansionStore.removeAll()
        let document = detailsDocument()
        setExpansion(true, in: document)

        assertMarkdownMeasurementParity(Self.detailsMarkdown)
    }

    func testOpenAttributeMeasuresExpandedWithoutAStoredValue() {
        AppMarkdownDetailsExpansionStore.removeAll()

        assertMarkdownMeasurementParity(
            "<details open><summary>Shown</summary>\n\nRevealed body.\n\n</details>"
        )
    }

    /// The phantom-space regression, stated directly: a collapsed disclosure costs its header and
    /// nothing else. If the measurer kept the body's height, or spent a `blockSpacing` the view
    /// removes along with the body, the collapsed measurement would exceed the header.
    func testCollapsedDetailsCostsOnlyItsHeader() {
        AppMarkdownDetailsExpansionStore.removeAll()
        let document = AppMarkdownParser().documentPreservingSource(
            for: "<details><summary>Only a header</summary>\n\n\(String(repeating: "Body line.\n\n", count: 12))</details>"
        )

        let collapsed = AppKitMarkdownLayoutMeasurer(document: document).measure(width: 420)
        let headerOnly = AppKitMarkdownLayoutMeasurer(
            document: AppMarkdownParser().documentPreservingSource(for: "<details><summary>Only a header</summary></details>")
        )
        .measure(width: 420)

        XCTAssertEqual(collapsed.contentHeight, headerOnly.contentHeight, accuracy: 0.5)
    }

    /// Expanding then collapsing has to land back on the original height exactly. A drift here is
    /// the pane keeping a sliver of the expanded body after every close.
    func testCollapsingReturnsToTheOriginalHeight() {
        AppMarkdownDetailsExpansionStore.removeAll()
        let document = detailsDocument()
        let measurer = AppKitMarkdownLayoutMeasurer(document: document)

        let collapsed = measurer.measure(width: 420).contentHeight
        setExpansion(true, in: document)
        let expanded = measurer.measure(width: 420).contentHeight
        setExpansion(false, in: document)
        let recollapsed = measurer.measure(width: 420).contentHeight

        XCTAssertGreaterThan(expanded, collapsed)
        XCTAssertEqual(recollapsed, collapsed, accuracy: 0.01)
    }

    /// The prepared-layout cache answers from a key that knows nothing about a disclosure, so
    /// without the store's generation a collapsed row would be served its expanded height.
    func testTogglingADisclosureInvalidatesThePreparedLayoutKey() {
        AppMarkdownDetailsExpansionStore.removeAll()
        let before = preparedLayoutKey()
        AppMarkdownDetailsExpansionStore.set(true, for: "details:probe:0")
        let after = preparedLayoutKey()

        XCTAssertNotEqual(before, after)
    }

    /// Driving the real view, not just the measurer: a toggle has to republish the row's height,
    /// or every row below it stays at the old offset.
    func testTogglingTheRenderedDisclosureReportsAHeightChange() {
        AppMarkdownDetailsExpansionStore.removeAll()
        let document = detailsDocument()
        var invalidations = 0
        let view = AppKitMarkdownView(document: document)
        view.onHeightInvalidated = { invalidations += 1 }
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 2_000)
        view.layoutSubtreeIfNeeded()

        let collapsedHeight = view.intrinsicContentSize.height
        let header = try? XCTUnwrap(detailsHeaderView(in: view))
        invalidations = 0
        _ = header?.accessibilityPerformPress()
        view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(invalidations, 0)
        XCTAssertGreaterThan(view.intrinsicContentSize.height, collapsedHeight)

        _ = header?.accessibilityPerformPress()
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.intrinsicContentSize.height, collapsedHeight, accuracy: 0.5)
    }

    private func detailsDocument() -> AppMarkdownDocument {
        AppMarkdownParser().documentPreservingSource(for: Self.detailsMarkdown)
    }

    /// The disclosure is the second document block, so its source-order path is `1`.
    private func setExpansion(_ isExpanded: Bool, in document: AppMarkdownDocument) {
        AppMarkdownDetailsExpansionStore.set(
            isExpanded,
            for: AppMarkdownDetailsExpansionStore.key(namespace: document.taskStateNamespace, path: "1")
        )
    }

    private func preparedLayoutKey() -> AppKitMarkdownPreparedLayoutKey {
        AppKitMarkdownPreparedLayoutKey(
            rowID: "row",
            markdown: Self.detailsMarkdown,
            role: "assistant",
            availableWidth: 420,
            bubbleMaxWidth: 420,
            typography: .default,
            inlineCodeStyle: .standard,
            appearanceName: "light",
            isExpanded: true,
            showsRetry: false
        )
    }

    private func detailsHeaderView(in view: NSView) -> AppKitMarkdownDetailsHeaderView? {
        if let header = view as? AppKitMarkdownDetailsHeaderView {
            return header
        }
        for subview in view.subviews {
            if let header = detailsHeaderView(in: subview) {
                return header
            }
        }
        return nil
    }
}
