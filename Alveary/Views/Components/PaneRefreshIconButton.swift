import SwiftUI

/// Header refresh affordance shared by the Skills, MCP, and Pull Requests screens:
/// the icon action button swaps to a working spinner in the same 30pt footprint
/// while a refresh is in flight, so layout never shifts.
struct PaneRefreshIconButton: View {
    let isRefreshing: Bool
    let accessibilityLabel: String
    let action: () -> Void

    init(
        isRefreshing: Bool,
        accessibilityLabel: String = "Refresh",
        action: @escaping () -> Void
    ) {
        self.isRefreshing = isRefreshing
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        if isRefreshing {
            StatusIndicatorSpinner(color: .secondary, diameter: 14, lineWidth: 1.5)
                .frame(width: 30, height: 30)
                .accessibilityLabel("Refreshing")
        } else {
            Button(action: action) {
                Image(systemName: "arrow.clockwise")
            }
            .iconActionButtonStyle()
            .help(accessibilityLabel)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}
