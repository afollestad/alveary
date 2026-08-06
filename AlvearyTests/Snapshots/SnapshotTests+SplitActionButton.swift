import SwiftUI
import XCTest

@testable import Alveary

// `SplitActionButton` chrome across its emphases and states. The menu is never
// popped: a live `NSMenu` host is the same hazard as a live popover host
// (`AlvearyTests/AGENTS.md`), and the caret half renders identically either way.
extension SnapshotTests {
    private func splitButton(
        title: String,
        emphasis: SplitActionButtonEmphasis,
        icon: ActionIcon? = nil,
        expandsHorizontally: Bool = false
    ) -> some View {
        SplitActionButton(
            title: title,
            icon: icon,
            emphasis: emphasis,
            expandsHorizontally: expandsHorizontally,
            selectedOption: "first",
            options: ["first", "second"],
            optionTitle: { $0 },
            action: {},
            selectOption: { _ in }
        )
    }

    func testSplitActionButtonEmphases() {
        // Text-only labels, the shape the pane footers use; the secondary fill
        // must match `secondaryActionButtonStyle()` beside it.
        let stacked = VStack(alignment: .leading, spacing: 12) {
            splitButton(title: "Approve", emphasis: .primary)

            HStack(spacing: 12) {
                splitButton(title: "Mark ready for review", emphasis: .secondary)
                Button("Close PR") {}
                    .secondaryActionButtonStyle()
            }

            HStack(spacing: 12) {
                splitButton(title: "Close PR", emphasis: .destructive)
                Button("Close PR") {}
                    .destructiveActionButtonStyle()
            }

            splitButton(title: "Disabled", emphasis: .secondary)
                .disabled(true)
        }
        .padding(16)

        assertMacSnapshot(
            stacked,
            size: CGSize(width: 420, height: 210),
            named: "split_action_button_emphases"
        )
    }

    func testSplitActionButtonExpanded() {
        // The even-split footer row: the label centers in its half instead of
        // hugging the leading edge.
        let row = HStack(spacing: ContextualPaneLayout.actionSpacing) {
            splitButton(title: "Mark ready for review", emphasis: .secondary, expandsHorizontally: true)
                .frame(maxWidth: .infinity)
            Button("Submit review...") {}
                .primaryActionButtonStyle(expandsHorizontally: true)
                .frame(maxWidth: .infinity)
        }
        .padding(16)

        assertMacSnapshot(
            row,
            size: CGSize(width: 460, height: 62),
            named: "split_action_button_expanded"
        )
    }

    func testSplitActionButtonWithSymbol() {
        // The symbol is optional; supplying one restores the approval-style label.
        assertMacSnapshot(
            splitButton(title: "Allow", emphasis: .primary, icon: .system("checkmark")).padding(16),
            size: CGSize(width: 300, height: 62),
            named: "split_action_button_symbol"
        )
    }
}
