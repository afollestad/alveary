import SwiftUI

struct TerminalSessionChip: View {
    let session: TerminalSession
    let isSelected: Bool
    let action: () -> Void
    let onClose: () -> Void

    var body: some View {
        SelectableTabChip(
            displayName: session.chipLabel,
            statusIndicator: statusIndicator,
            isSelected: isSelected,
            selectAccessibilityLabel: accessibilityLabel,
            closeAccessibilityLabel: "Close \(plainChipLabel)",
            selectShortcut: nil,
            onSelect: action,
            onClose: onClose
        )
    }
}

private extension TerminalSessionChip {
    var statusIndicator: TabChipStatusIndicator {
        switch session.status {
        case .running:
            return session.kind == .projectAction ? .spinner(.secondary) : .none
        case .succeeded:
            return .dot(.green)
        case .failed:
            return .dot(.red)
        case .cancelled:
            return .dot(.orange)
        }
    }

    var accessibilityLabel: String {
        "\(plainChipLabel), \(session.status.rawValue)"
    }

    var plainChipLabel: String {
        AppMarkdownInlineLabel.plainText(from: session.chipLabel)
    }
}
