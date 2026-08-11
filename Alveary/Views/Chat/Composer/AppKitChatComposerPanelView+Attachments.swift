@preconcurrency import AppKit

@MainActor
extension AppKitChatComposerPanelView {
    func configureAttachmentStrip(_ configuration: AppKitChatComposerBodyConfiguration) {
        attachmentStripView.configure(configuration.attachments)
        attachmentStripView.onOpenAttachment = configuration.isVoiceInteractionLocked ? nil : configuration.onOpenAttachment
        attachmentStripView.onRemoveAttachment = configuration.isVoiceInteractionLocked ? nil : configuration.onRemoveAttachment
        attachmentStripView.isHidden = configuration.attachments.isEmpty
    }

    func layoutAttachmentStrip(
        configuration: AppKitChatComposerPanelConfiguration,
        contentWidth: CGFloat,
        currentY: CGFloat
    ) -> CGFloat {
        guard !attachmentStripView.isEmpty else {
            attachmentStripView.frame = .zero
            return currentY
        }
        let stripHeight = attachmentStripView.measuredHeight(width: contentWidth)
        attachmentStripView.frame = NSRect(
            x: configuration.layout.horizontalPadding.left,
            y: currentY,
            width: contentWidth,
            height: stripHeight
        )
        return currentY + stripHeight
    }
}
