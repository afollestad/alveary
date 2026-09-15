import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testReviewProposalMultilineSummary() {
        assertMacSnapshot(
            appKitRowSnapshot { ReviewProposalSnapshotFixture.widgetRow(summaryBody: Self.multilineReviewSummary) },
            size: CGSize(width: 700, height: 430), named: "review_proposal_multiline_summary"
        )
    }

    func testReviewProposalMultilineSummaryDark() {
        assertMacSnapshot(
            appKitRowSnapshot { ReviewProposalSnapshotFixture.widgetRow(summaryBody: Self.multilineReviewSummary) },
            size: CGSize(width: 700, height: 430), named: "review_proposal_multiline_summary_dark", colorScheme: .dark
        )
    }

    func testReviewProposalSummaryEditor() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let row = ReviewProposalSnapshotFixture.widgetRow(summaryBody: Self.multilineReviewSummary)
                let summary = ReviewSummaryTestFixture.descendant(in: row) { $0 is AppKitReviewProposalSummaryView }
                    as? AppKitReviewProposalSummaryView
                summary?.beginEditing()
                return row
            },
            size: CGSize(width: 700, height: 480), named: "review_proposal_summary_editor"
        )
    }

    func testReviewProposalClearedSummary() {
        assertMacSnapshot(
            appKitRowSnapshot { ReviewProposalSnapshotFixture.widgetRow(summaryBody: "") },
            size: CGSize(width: 700, height: 360), named: "review_proposal_cleared_summary"
        )
    }

    func testReviewProposalAddCommentButtonStates() {
        for colorScheme in [ColorScheme.light, .dark] {
            assertMacSnapshot(
                appKitRowSnapshot {
                    let states = ["Resting", "Hovered", "Pressed", "Disabled"].map { state in
                        let summary = ReviewSummaryTestFixture.summary(body: "")
                        let button = ReviewSummaryTestFixture.descendant(in: summary) { $0 is AppKitTranscriptApprovalButton }
                            as? AppKitTranscriptApprovalButton
                        button?.setInteractionStateForTesting(isHovering: state == "Hovered")
                        button?.isHighlighted = state == "Pressed"
                        button?.isEnabled = state != "Disabled"
                        let column = NSStackView(views: [NSTextField(labelWithString: state), summary])
                        column.orientation = .vertical
                        column.spacing = 8
                        return column
                    }
                    let stack = NSStackView(views: states)
                    stack.orientation = .horizontal
                    stack.spacing = 20
                    stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
                    return stack
                },
                size: CGSize(width: 570, height: 80),
                named: "review_proposal_add_comment_states_\(colorScheme == .dark ? "dark" : "light")",
                colorScheme: colorScheme
            )
        }
    }

    private static let multilineReviewSummary = """
        Please cover both branches in `BillsToOrdersConverterTest`, including the case where local orders are disabled.

        Verify the resulting order list as well as the feature-flag value.
        """
}
