import AppKit

extension AppKitChatComposerPanelView {
    struct Layout {
        let horizontalPadding: NSEdgeInsets
        let topContentSpacing: CGFloat
        let actionRowSpacing: CGFloat
        let queuedMessagesTopPadding: CGFloat
        /// Clearance below the native action row. Keep this out of the editor
        /// body padding so the editor-to-controls gap stays at `actionRowSpacing`.
        let bottomPadding: CGFloat

        init(
            horizontalPadding: NSEdgeInsets,
            topContentSpacing: CGFloat,
            actionRowSpacing: CGFloat,
            queuedMessagesTopPadding: CGFloat = 16,
            bottomPadding: CGFloat = 0
        ) {
            self.horizontalPadding = horizontalPadding
            self.topContentSpacing = topContentSpacing
            self.actionRowSpacing = actionRowSpacing
            self.queuedMessagesTopPadding = queuedMessagesTopPadding
            self.bottomPadding = bottomPadding
        }
    }
}
