import AppKit
import SwiftUI
import XCTest

@testable import Alveary

/// The instructions card: collapsed it names the pull request being worked on, expanded it shows
/// the instructions the agent received. Both tools that return instructions share it, so the
/// address-feedback baseline is what catches a summary that stopped naming its own work.
@MainActor
extension SnapshotTests {
    func testReviewInstructionsWidgetCollapsed() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewInstructionsSnapshotFixture.widgetRow()
            },
            size: CGSize(width: 700, height: 90),
            named: "review_instructions_widget_collapsed"
        )
    }

    func testReviewInstructionsWidgetExpanded() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewInstructionsSnapshotFixture.widgetRow(expanded: true)
            },
            size: CGSize(width: 700, height: 260),
            named: "review_instructions_widget_expanded"
        )
    }

    func testReviewInstructionsWidgetRunning() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewInstructionsSnapshotFixture.widgetRow(status: .running, isComplete: false)
            },
            size: CGSize(width: 700, height: 90),
            named: "review_instructions_widget_running"
        )
    }

    /// The same card for the sibling tool; only the summary line differs.
    func testAddressFeedbackInstructionsWidgetCollapsed() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewInstructionsSnapshotFixture.widgetRow(kind: .addressFeedback)
            },
            size: CGSize(width: 700, height: 90),
            named: "address_feedback_instructions_widget_collapsed"
        )
    }

    func testAddressFeedbackInstructionsWidgetRunning() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewInstructionsSnapshotFixture.widgetRow(
                    kind: .addressFeedback,
                    status: .running,
                    isComplete: false
                )
            },
            size: CGSize(width: 700, height: 90),
            named: "address_feedback_instructions_widget_running"
        )
    }
}

/// Builds instructions cards from fixed content, so a baseline never depends on settings.
@MainActor
enum ReviewInstructionsSnapshotFixture {
    static let instructions = """
    Focus on correctness, regressions, and misleading code; raise style only where it obscures meaning.

    ## Pull request
    - Pull request: `octo/alpha#7`
    - Title: Improve parser
    """

    static func widgetRow(
        kind: ReviewInstructionsWidgetContent.Kind = .review,
        status: ReviewInstructionsWidgetContent.Status = .loaded,
        isComplete: Bool = true,
        expanded: Bool = false
    ) -> AppKitTranscriptHostToolWidgetRowView {
        let toolName = kind == .review
            ? PullRequestHostToolCatalog.reviewInstructionsToolName
            : PullRequestHostToolCatalog.addressFeedbackInstructionsToolName
        let view = AppKitTranscriptHostToolWidgetRowView(frame: .zero)
        view.configure(
            .init(
                entry: HostToolWidgetEntry(
                    id: "instructions-snapshot",
                    toolName: HostToolTranscriptCatalog.toolName(toolName),
                    content: .pullRequestReviewInstructions(
                        ReviewInstructionsWidgetContent(
                            kind: kind,
                            identifier: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
                            instructions: status == .loaded ? instructions : nil,
                            status: status
                        )
                    ),
                    isComplete: isComplete
                ),
                bubbleMaxWidth: 660
            )
        )
        if expanded {
            performDisclosurePress(in: view)
        }
        return view
    }

    /// The disclosure is view-local state toggled by pressing the card itself, so the expanded
    /// baseline goes through the same activation a user's click does.
    private static func performDisclosurePress(in view: NSView) {
        guard let card = pressableCard(in: view) else {
            XCTFail("Expected the instructions card to be pressable")
            return
        }
        _ = card.accessibilityPerformPress()
    }

    private static func pressableCard(in view: NSView) -> NSView? {
        if view.accessibilityRole() == .button {
            return view
        }
        for subview in view.subviews {
            if let card = pressableCard(in: subview) {
                return card
            }
        }
        return nil
    }
}
