import AppKit
import BlockInputKit
import Foundation

extension ChatView {
    var stagedImagePreviewAttachments: [BlockInputImagePreviewAttachment] {
        let imagePreviews = viewModel.stagedImageAttachments.map { attachment in
            BlockInputImagePreviewAttachment(
                id: attachment.id,
                fileURL: attachment.fileURL,
                label: attachment.label,
                open: { preview in
                    NSWorkspace.shared.open(preview.fileURL)
                },
                remove: { preview in
                    viewModel.removeStagedImageAttachment(id: preview.id)
                }
            )
        }
        let appShotPreviews = viewModel.stagedAppShots.map { appShot in
            BlockInputImagePreviewAttachment(
                id: appShot.id,
                fileURL: appShot.screenshot.fileURL,
                label: "App shot: \(appShot.appName)",
                open: { preview in
                    NSWorkspace.shared.open(preview.fileURL)
                },
                remove: { preview in
                    viewModel.removeStagedAppShot(id: preview.id)
                }
            )
        }
        return imagePreviews + appShotPreviews
    }

    var blockInputFileDropHandler: BlockInputFileDropHandler? {
        guard composerCapabilities.supportsLocalImageInput else {
            return nil
        }
        return { context in
            await handleBlockInputFileDrop(context)
        }
    }

    func handleLocalFileURLsSelected(_ urls: [URL]) async -> LocalFileSelectionResult {
        guard composerCapabilities.supportsLocalImageInput else {
            return .useDefault
        }
        let imageURLs = urls.filter(DefaultConversationAttachmentStore.isSupportedImageURL(_:))
        guard !imageURLs.isEmpty else {
            return .useDefault
        }

        do {
            try await viewModel.stageLocalImageAttachments(from: imageURLs)
        } catch {
            viewModel.lastTurnError = "Could not attach image: \(error.localizedDescription)"
            return .useDefault
        }

        let remainingURLs = urls.filter { !DefaultConversationAttachmentStore.isSupportedImageURL($0) }
        return remainingURLs.isEmpty ? .handled : .insertDefault(remainingURLs)
    }

    func handleBlockInputFileDrop(_ context: BlockInputFileDropContext) async -> BlockInputFileDropResult {
        let imageFiles = context.files.filter { DefaultConversationAttachmentStore.isSupportedImageURL($0.url) }
        guard !imageFiles.isEmpty else {
            return .useDefault
        }

        do {
            try await viewModel.stageLocalImageAttachments(from: imageFiles.map(\.url))
        } catch {
            viewModel.lastTurnError = "Could not attach dropped image: \(error.localizedDescription)"
            return .useDefault
        }

        let remainingReferences = context.files
            .filter { !DefaultConversationAttachmentStore.isSupportedImageURL($0.url) }
            .map(\.defaultReference)
        return remainingReferences.isEmpty ? .cancel : .insert(remainingReferences)
    }
}
