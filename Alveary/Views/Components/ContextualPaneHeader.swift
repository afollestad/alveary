import SwiftUI

enum ContextualPaneFocusRestoration {
    static func resolve(
        preferredID: String,
        visibleTriggerIDs: Set<String>,
        fallbackID: String
    ) -> String {
        visibleTriggerIDs.contains(preferredID) ? preferredID : fallbackID
    }
}

struct ContextualPaneHeader: View {
    let title: String
    let closeAccessibilityLabel: String
    let onClose: () -> Void

    init(
        _ title: String,
        closeAccessibilityLabel: String,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.closeAccessibilityLabel = closeAccessibilityLabel
        self.onClose = onClose
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            ModalCloseButton(closeAccessibilityLabel, action: onClose)
                .contextualPaneTrailingGlyphLane(controlWidth: ActionButtonMetrics.iconButtonDiameter)
        }
        .frame(minHeight: PaneHeaderLayout.height - 32)
        .contextualPaneHorizontalInsets()
        .padding(.vertical, 16)
        .frame(height: PaneHeaderLayout.height)
        .background(.bar)
        .overlay(alignment: .bottom) {
            AppSeparatorHairline(surface: .paneHeader)
                .contextualPaneHorizontalInsets()
        }
    }
}
