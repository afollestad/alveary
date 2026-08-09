@preconcurrency import AppKit
import XCTest

@testable import Alveary

/// The widget shell's header line: leading glyph, summary, trailing caret.
///
/// The stack aligns on a first baseline, and `NSImageView` reports its baseline at the bottom of
/// its alignment rect — so square octicon artwork hangs its whole canvas above the text unless the
/// glyph publishes an optical baseline of its own.
@MainActor
final class HostToolWidgetHeaderAlignmentTests: XCTestCase {
    /// The review-instructions card wears an octicon, the case the default baseline gets wrong.
    func testTheLeadingOcticonCentersOnItsSummaryLine() throws {
        let row = row(for: reviewInstructionsEntry())
        let icon = try XCTUnwrap(firstView(of: AppKitHostToolWidgetIconView.self, in: row))
        let summary = try XCTUnwrap(summaryField(beside: icon))

        XCTAssertEqual(
            icon.convert(icon.bounds, to: row).midY,
            capHeightCenter(of: summary, in: row),
            accuracy: 1,
            "The leading glyph should sit on the summary's optical center, not above its cap"
        )
    }

    /// Both ends take the same cap height, so a card that centers one and not the other reads
    /// lopsided even when each is individually defensible.
    func testTheLeadingGlyphAndTrailingCaretShareACenter() throws {
        let row = row(for: reviewInstructionsEntry())
        let icon = try XCTUnwrap(firstView(of: AppKitHostToolWidgetIconView.self, in: row))
        let caret = try XCTUnwrap(firstView(of: AppKitHostToolWidgetDisclosureSlotView.self, in: row))

        XCTAssertEqual(
            icon.convert(icon.bounds, to: row).midY,
            caret.convert(caret.bounds, to: row).midY,
            accuracy: 1
        )
    }

    /// A status glyph is an SF Symbol, which does have a text baseline; centering must not shove
    /// it off the line the octicon case fixed.
    func testAStatusSymbolStaysOnItsSummaryLine() throws {
        let row = row(for: threadActionEntry())
        let icon = try XCTUnwrap(firstView(of: AppKitHostToolWidgetIconView.self, in: row))
        let summary = try XCTUnwrap(summaryField(beside: icon))

        XCTAssertEqual(
            icon.convert(icon.bounds, to: row).midY,
            capHeightCenter(of: summary, in: row),
            accuracy: 1
        )
    }

    /// The summary's optical center: half a cap height above its baseline, in `row`'s space.
    private func capHeightCenter(of summary: NSTextField, in row: NSView) -> CGFloat {
        let font = summary.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let frame = summary.convert(summary.bounds, to: row)
        // `row` is flipped, so the baseline runs down from the field's top edge.
        return frame.minY + summary.firstBaselineOffsetFromTop - (font.capHeight / 2)
    }

    private func row(for entry: HostToolWidgetEntry) -> NSView {
        let view = AppKitTranscriptHostToolWidgetRowView(frame: .zero)
        view.configure(.init(entry: entry, bubbleMaxWidth: 480))
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 200)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func reviewInstructionsEntry() -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "call-1",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.reviewInstructionsToolName),
            content: .pullRequestReviewInstructions(
                ReviewInstructionsWidgetContent(
                    kind: .review,
                    identifier: Self.pullRequest,
                    instructions: "Focus on correctness.",
                    status: .loaded
                )
            ),
            isComplete: true,
            isError: false
        )
    }

    private func threadActionEntry() -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "call-2",
            toolName: ThreadHostToolCatalog.linkPullRequestToolName,
            content: .pullRequestLink(
                PullRequestLinkWidgetContent(
                    action: .link,
                    identifier: Self.pullRequest,
                    title: "Add caching",
                    message: "Linked it.",
                    status: .applied
                )
            ),
            isComplete: true,
            isError: false
        )
    }

    /// The header stack's own label — resolved through the icon's parent rather than by searching
    /// the row, which would find the detail line instead if the two ever swapped order.
    private func summaryField(beside icon: NSView) -> NSTextField? {
        icon.superview?.subviews.lazy.compactMap { $0 as? NSTextField }.first
    }

    private func firstView<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match = firstView(of: type, in: subview) {
                return match
            }
        }
        return nil
    }

    private static let pullRequest = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
}
