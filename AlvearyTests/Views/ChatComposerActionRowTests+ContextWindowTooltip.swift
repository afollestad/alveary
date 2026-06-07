import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    func testContextWindowTooltipFitsReportedTokenLine() throws {
        let tooltip = AppKitContextWindowTooltipView(
            summary: ConversationUsageSummary(
                contextUsedTokens: 70_060,
                contextWindowSize: 121_600,
                totalCostUsd: 0,
                hasReportedCost: false,
                hasReportedUsage: true,
                isUsingCachedContextWindow: false
            )
        )
        tooltip.applyPreferredSize()

        let fields = tooltip.descendants(of: NSTextField.self)
        XCTAssertEqual(fields.count, 3)
        XCTAssertNil(fields.first { $0.stringValue.hasPrefix("Session spend:") })
        XCTAssertGreaterThanOrEqual(tooltip.preferredSize.width, 204)

        let detailField = try XCTUnwrap(
            fields.first {
                $0.stringValue == "70.1k / 121.6k tokens used"
            }
        )
        XCTAssertGreaterThanOrEqual(detailField.frame.width, measuredTextWidth(for: detailField))
    }

    func testContextWindowTooltipIncludesReportedCostLine() throws {
        let tooltip = AppKitContextWindowTooltipView(
            summary: ConversationUsageSummary(
                contextUsedTokens: 70_060,
                contextWindowSize: 121_600,
                totalCostUsd: 0,
                hasReportedCost: true,
                hasReportedUsage: true,
                isUsingCachedContextWindow: false
            )
        )
        tooltip.applyPreferredSize()

        let fields = tooltip.descendants(of: NSTextField.self)
        XCTAssertEqual(fields.count, 4)
        XCTAssertNotNil(fields.first { $0.stringValue == "Session spend: $0.00" })
    }

    func testContextWindowTooltipHandlesUnknownContextWindowSize() throws {
        let tooltip = AppKitContextWindowTooltipView(summary: .unreported)

        tooltip.applyPreferredSize()

        let fields = tooltip.descendants(of: NSTextField.self)
        XCTAssertNotNil(fields.first { $0.stringValue == "No usage yet" })
        XCTAssertNotNil(fields.first { $0.stringValue == "Context window size not reported" })
        XCTAssertNil(fields.first { $0.stringValue == "0 token window" })
    }

    func testContextWindowTooltipUpdatesExistingContent() throws {
        let tooltip = AppKitContextWindowTooltipView(
            summary: ConversationUsageSummary(
                contextUsedTokens: 1_000,
                contextWindowSize: 100_000,
                totalCostUsd: 0,
                hasReportedCost: false,
                hasReportedUsage: true,
                isUsingCachedContextWindow: false
            )
        )
        tooltip.applyPreferredSize()

        tooltip.update(
            summary: ConversationUsageSummary(
                contextUsedTokens: 70_060,
                contextWindowSize: 121_600,
                totalCostUsd: 0,
                hasReportedCost: false,
                hasReportedUsage: true,
                isUsingCachedContextWindow: false
            )
        )
        tooltip.applyPreferredSize()

        XCTAssertNil(tooltip.descendants(of: NSTextField.self).first { $0.stringValue == "1k / 100k tokens used" })
        let detailField = try XCTUnwrap(
            tooltip.descendants(of: NSTextField.self).first {
                $0.stringValue == "70.1k / 121.6k tokens used"
            }
        )
        XCTAssertGreaterThanOrEqual(detailField.frame.width, measuredTextWidth(for: detailField))
    }

    func testContextWindowTooltipKeepsContentCenteredAfterUpdate() throws {
        let tooltip = AppKitContextWindowTooltipView(
            summary: ConversationUsageSummary(
                contextUsedTokens: 70_060,
                contextWindowSize: 121_600,
                totalCostUsd: 0,
                hasReportedCost: false,
                hasReportedUsage: true,
                isUsingCachedContextWindow: false
            )
        )
        tooltip.applyPreferredSize()

        tooltip.update(
            summary: ConversationUsageSummary(
                contextUsedTokens: 414_600,
                contextWindowSize: 121_600,
                totalCostUsd: 0,
                hasReportedCost: false,
                hasReportedUsage: true,
                isUsingCachedContextWindow: false
            )
        )
        tooltip.applyPreferredSize()

        let fields = tooltip.descendants(of: NSTextField.self)
        XCTAssertEqual(fields.count, 3)
        XCTAssertNil(fields.first { $0.stringValue.hasPrefix("Session spend:") })
        XCTAssertTrue(fields.allSatisfy { abs($0.frame.midX - tooltip.bounds.midX) <= 1 })

        let topInset = try XCTUnwrap(fields.map(\.frame.minY).min())
        let bottomInset = try XCTUnwrap(fields.map(\.frame.maxY).max()).distance(to: tooltip.bounds.maxY)
        XCTAssertEqual(topInset, bottomInset, accuracy: 1)
    }

    func testContextIndicatorStaysAttachedAcrossEquivalentReconfiguration() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 900, height: 30))
        let summary = ConversationUsageSummary(
            contextUsedTokens: 70_060,
            contextWindowSize: 121_600,
            totalCostUsd: 0,
            hasReportedCost: false,
            hasReportedUsage: true,
            isUsingCachedContextWindow: false
        )
        row.configure(makeConfiguration(mode: .idle, usageSummary: summary))
        row.layoutSubtreeIfNeeded()

        let indicator = try XCTUnwrap(row.descendants(of: AppKitContextWindowIndicatorView.self).first)
        let originalSuperview = try XCTUnwrap(indicator.superview)

        row.configure(makeConfiguration(mode: .idle, usageSummary: summary))
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(indicator.superview === originalSuperview)
        XCTAssertTrue(row.descendants(of: AppKitContextWindowIndicatorView.self).first === indicator)
    }

    func testUnreportedUsageSummaryKeepsContextIndicatorAttached() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 900, height: 30))
        row.configure(makeConfiguration(mode: .idle, usageSummary: .unreported))
        row.layoutSubtreeIfNeeded()

        let indicator = try XCTUnwrap(row.descendants(of: AppKitContextWindowIndicatorView.self).first)

        XCTAssertFalse(indicator.isHidden)
        XCTAssertEqual(indicator.accessibilityValue() as? String, "No usage reported yet")
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

@MainActor
private func measuredTextWidth(for field: NSTextField) -> CGFloat {
    let font = field.font ?? .preferredFont(forTextStyle: .callout)
    let textWidth = (field.stringValue as NSString).size(withAttributes: [.font: font]).width
    let cellWidth = field.cell?.cellSize.width ?? 0
    let intrinsicWidth = field.intrinsicContentSize.width
    return ceil(max(textWidth, cellWidth, intrinsicWidth)) + 4
}
