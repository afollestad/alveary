@preconcurrency import AppKit
import XCTest

@testable import Alveary

/// GitHub alerts in the AppKit renderer: the tinted bar, the icon-and-title header, and the marker
/// never surviving into the body text.
@MainActor
extension AppKitMarkdownRendererTests {
    func testAlertQuoteRendersATintedBarAndHeader() {
        let view = hydratedAlertView(markdown: "> [!WARNING]\n> Do not merge yet.")

        let headers = view.descendants(of: AppKitMarkdownAlertHeaderView.self)
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers.first?.accessibilityLabel(), "Warning")

        let fills = view.descendants(of: NSBox.self).map(\.fillColor)
        XCTAssertTrue(fills.contains(AppMarkdownAlertKind.warning.accentNSColor))

        let textValues = view.descendants(of: NSTextView.self).map(\.string)
        XCTAssertTrue(textValues.contains { $0.contains("Do not merge yet.") })
        XCTAssertFalse(textValues.contains { $0.contains("[!WARNING]") })
    }

    func testEveryAlertKindRendersItsOwnAccent() {
        for kind in AppMarkdownAlertKind.allCases {
            let view = hydratedAlertView(markdown: "> [!\(kind.rawValue.uppercased())]\n> Body text.")

            let fills = view.descendants(of: NSBox.self).map(\.fillColor)
            XCTAssertTrue(fills.contains(kind.accentNSColor), "Expected the \(kind.rawValue) accent on the bar.")
            XCTAssertEqual(view.descendants(of: AppKitMarkdownAlertHeaderView.self).first?.accessibilityLabel(), kind.title)
        }
    }

    func testPlainQuoteKeepsTheSeparatorBarAndNoHeader() {
        let view = hydratedAlertView(markdown: "> Just a quote.")

        XCTAssertTrue(view.descendants(of: AppKitMarkdownAlertHeaderView.self).isEmpty)
        XCTAssertTrue(view.descendants(of: NSBox.self).map(\.fillColor).contains(.separatorColor))
    }

    /// A bodyless alert is the marker and nothing else — the renderer adds no body view, which is
    /// what `AppKitMarkdownLayoutMeasurer.measureQuote` mirrors by spending no block spacing.
    func testBodylessAlertRendersOnlyItsHeader() {
        let view = hydratedAlertView(markdown: "> [!TIP]")

        XCTAssertEqual(view.descendants(of: AppKitMarkdownAlertHeaderView.self).count, 1)
        let textValues = view.descendants(of: NSTextView.self).map(\.string)
        XCTAssertFalse(textValues.contains { $0.contains("[!TIP]") })
    }

    private func hydratedAlertView(markdown: String) -> AppKitMarkdownView {
        let document = AppMarkdownParser().documentPreservingSource(for: markdown)
        let view = AppKitMarkdownView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        view.layoutSubtreeIfNeeded()
        return view
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
