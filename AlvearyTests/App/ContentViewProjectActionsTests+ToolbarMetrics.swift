import XCTest

@testable import Alveary

/// Width reservation and optical spacing for the primary toolbar button group.
@MainActor
extension ContentViewProjectActionsTests {
    func testPrimaryToolbarGroupWidthIncludesAnimatedProjectActionSlot() {
        let symbols = ["safari", "hammer"]
        let twoActionStripWidth = PrimaryToolbarGroupWidth.projectActionStripWidth(symbols: symbols)
        XCTAssertEqual(
            twoActionStripWidth,
            PrimaryToolbarMetrics.iconButtonSize * 2
                + PrimaryToolbarGlyphInk.spacing(after: "safari", before: "hammer")
        )

        let twoActionSlotWidth = PrimaryToolbarGroupWidth.projectActionsSlotWidth(symbols: symbols)
        XCTAssertEqual(
            twoActionSlotWidth,
            twoActionStripWidth + PrimaryToolbarGlyphInk.spacing(
                after: PrimaryToolbarGlyphInk.width(ofSymbol: "hammer"),
                before: PrimaryToolbarGlyphInk.terminalInk
            )
        )

        let groupWidth = PrimaryToolbarGroupWidth.groupWidth(
            projectActionsSlotWidth: twoActionSlotWidth,
            pullRequestSlotWidth: 0,
            diffStatusWidth: 42
        )
        XCTAssertEqual(
            groupWidth,
            PrimaryToolbarMetrics.containerHorizontalInset * 2
                + PrimaryToolbarMetrics.iconButtonSize * 3
                + PrimaryToolbarOpticalSpacing.beforeDiffViewer
                + PrimaryToolbarOpticalSpacing.beforeSettings
                + twoActionSlotWidth
                + 42
        )
    }

    /// Every boundary spaces optically because the glyphs differ in ink width, so a
    /// uniform gap looks uneven. Each fixed value tightens `buttonSpacing`, and none
    /// may go negative — a negative one would overlap two hover selectors, which is
    /// not how this row buys room.
    func testToolbarBoundariesTightenTheUniformSpacingWithoutOverlapping() {
        for spacing in [
            PrimaryToolbarOpticalSpacing.beforeDiffViewer,
            PrimaryToolbarOpticalSpacing.beforePullRequest,
            PrimaryToolbarOpticalSpacing.beforeSettings
        ] {
            XCTAssertGreaterThanOrEqual(spacing, 0)
            XCTAssertLessThan(spacing, PrimaryToolbarMetrics.buttonSpacing)
        }

        XCTAssertGreaterThan(PrimaryToolbarMetrics.octiconSize, 16)
        XCTAssertLessThan(PrimaryToolbarMetrics.octiconSize, PrimaryToolbarMetrics.iconButtonSize)
    }

    /// The measured widths the project-action spacing is derived from. These are the
    /// values read off the recorded toolbar baselines by thresholding pixel columns;
    /// if SwiftUI's rendering of these symbols moves, the spacing derived from it
    /// moves too, and this is the test that says so.
    func testGlyphInkMatchesTheWidthsMeasuredFromRecordedBaselines() {
        let expected: [String: CGFloat] = [
            "terminal": 18.5,
            "gearshape": 17.0,
            "safari": 16.0,
            "hammer": 20.0
        ]

        for (symbol, baseline) in expected {
            let measured = PrimaryToolbarGlyphInk.width(ofSymbol: symbol)
            XCTAssertEqual(
                measured,
                baseline,
                accuracy: 0.5,
                "\(symbol) measured \(measured), baselines show \(baseline)"
            )
        }
    }

    /// The point of deriving this boundary rather than fixing it: symbols that differ
    /// by 4pt of ink must still produce the same visible gap. A fixed spacing put
    /// `safari` 2pt looser than `hammer`.
    func testProjectActionSpacingEvensTheGapAcrossSymbolWidths() {
        let terminalInk = PrimaryToolbarGlyphInk.terminalInk

        let gaps = ["safari", "hammer", "play.fill"].map { symbol -> CGFloat in
            let ink = PrimaryToolbarGlyphInk.width(ofSymbol: symbol)
            let spacing = PrimaryToolbarGlyphInk.spacing(after: ink, before: terminalInk)
            // What the eye sees between the two marks, box size included.
            return PrimaryToolbarMetrics.iconButtonSize + spacing - (ink + terminalInk) / 2
        }

        for gap in gaps {
            XCTAssertEqual(gap, gaps[0], accuracy: 0.01)
        }
    }

    /// An unknown symbol still has to space like something, and a project config can
    /// name one this OS does not publish.
    func testGlyphInkFallsBackForAnUnrenderableSymbol() {
        let width = PrimaryToolbarGlyphInk.width(ofSymbol: "not.a.real.sf.symbol.name")

        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThanOrEqual(width, PrimaryToolbarMetrics.iconButtonSize)
    }

    /// The pull-request button is conditional, so it rides its own animated slot
    /// rather than the fixed core-button count — otherwise the group reserves
    /// width for a button that is not mounted and its trailing edge shifts. The
    /// slot reserves its own leading spacing too, so a collapse removes both.
    func testPullRequestSlotWidensTheGroupOnlyWhenTheButtonIsMounted() {
        XCTAssertEqual(PrimaryToolbarGroupWidth.pullRequestSlotWidth(isVisible: false), 0)
        XCTAssertEqual(
            PrimaryToolbarGroupWidth.pullRequestSlotWidth(isVisible: true),
            PrimaryToolbarMetrics.iconButtonSize + PrimaryToolbarOpticalSpacing.beforePullRequest
        )

        let hidden = PrimaryToolbarGroupWidth.groupWidth(
            projectActionsSlotWidth: 0,
            pullRequestSlotWidth: PrimaryToolbarGroupWidth.pullRequestSlotWidth(isVisible: false),
            diffStatusWidth: 0
        )
        let visible = PrimaryToolbarGroupWidth.groupWidth(
            projectActionsSlotWidth: 0,
            pullRequestSlotWidth: PrimaryToolbarGroupWidth.pullRequestSlotWidth(isVisible: true),
            diffStatusWidth: 0
        )
        XCTAssertEqual(
            visible - hidden,
            PrimaryToolbarMetrics.iconButtonSize + PrimaryToolbarOpticalSpacing.beforePullRequest
        )
    }
}
