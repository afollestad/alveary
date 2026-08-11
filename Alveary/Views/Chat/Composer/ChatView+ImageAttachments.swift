import AppKit
import Foundation

extension ChatView {
    var stagedComposerAttachments: [ComposerAttachment] {
        viewModel.stagedImageAttachments.map(ComposerAttachment.image) +
            viewModel.stagedFileAttachments.map(ComposerAttachment.file) +
            viewModel.stagedAppShots.map(ComposerAttachment.appShot)
    }

    func openComposerAttachment(_ attachment: ComposerAttachment) {
        switch attachment {
        case .image(let image):
            appState.presentImagePreview(.fileURL(image.fileURL, title: image.label))
        case .file(let file):
            NSWorkspace.shared.open(file.fileURL)
        case .appShot(let appShot):
            appState.presentImagePreview(
                .appShotFileURL(
                    appShot.screenshot.fileURL,
                    title: "App shot: \(appShot.appName)",
                    axTreeText: appShot.axTreeText
                )
            )
        }
    }

    func removeComposerAttachment(_ attachment: ComposerAttachment) {
        guard !voiceInputCoordinator.isDraftInteractionLocked else {
            return
        }
        voiceInputCoordinator.invalidatePendingActivationIntent()
        switch attachment {
        case .image(let image):
            viewModel.removeStagedImageAttachment(id: image.id)
        case .file(let file):
            viewModel.removeStagedFileAttachment(id: file.id)
        case .appShot(let appShot):
            viewModel.removeStagedAppShot(id: appShot.id)
        }
    }

    func handleLocalFileURLsSelected(_ urls: [URL]) async -> LocalFileSelectionResult {
        guard !voiceInputCoordinator.isDraftInteractionLocked else {
            return .handled
        }
        if !urls.isEmpty {
            voiceInputCoordinator.invalidatePendingActivationIntent()
        }
        let imageURLs = urls.filter(DefaultConversationAttachmentStore.isSupportedImageURL(_:))
        let fileURLs = urls.filter { !DefaultConversationAttachmentStore.isSupportedImageURL($0) }
        let existingImageIDs = Set(viewModel.stagedImageAttachments.map(\.id))

        do {
            try await viewModel.stageLocalImageAttachments(from: imageURLs)
        } catch {
            viewModel.lastTurnError = "Could not attach image: \(error.localizedDescription)"
            return .handled
        }

        guard !voiceInputCoordinator.isDraftInteractionLocked else {
            for attachment in viewModel.stagedImageAttachments where !existingImageIDs.contains(attachment.id) {
                viewModel.removeStagedImageAttachment(id: attachment.id)
            }
            return .handled
        }

        viewModel.stageLocalFileAttachments(from: fileURLs)
        return .handled
    }

    @discardableResult
    func openComposerEditorURL(_ url: URL) -> Bool {
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(url, workingDirectory: workingDirectory)
        if let request = AppImagePreviewRequest.supportedURL(resolved) {
            appState.presentImagePreview(request)
            return true
        }
        return NSWorkspace.shared.open(resolved)
    }
}
