import AppKit
import Foundation

/// Routes a clicked diff image into the app's image preview modal, so the Diff Viewer and the pull
/// request Changes tab behave like every other click-an-image surface (chat transcript, composer
/// attachments, markdown blocks, tool output, comment bodies) rather than launching Preview.app.
///
/// Both diff view models already expose an `imagePreviewOpener` seam, so this replaces what that
/// closure *does* without touching the diff's own load, cache, or row code.
@MainActor
enum DiffImagePreviewPresentation {
    /// An image the modal's own loader would refuse still opens the way it always has.
    ///
    /// `AppImagePreviewLoader.maximumSourceBytes` is 20 MB, while a *confirmed* remote diff load
    /// reaches `DiffImagePreviewSupport.remoteMaxSourceBytes` (100 MB) — Git LFS exists to hold
    /// files that big. Without this fallback, redirecting to the modal would take away viewing an
    /// image the diff had already rendered inline, which is a regression rather than a redirect.
    /// `displayName` is the image's path in the diff, not the URL's own last component: a
    /// materialized blob is named by its cache identity (`abc123-Assets-logo.png-new-1a2b3c4d.png`),
    /// which is what the modal would otherwise show as the title.
    static func opener(
        appState: AppState,
        openInWorkspace: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) -> @MainActor (URL, String) -> Void {
        { url, displayName in
            guard canPresentInModal(url) else {
                openInWorkspace(url)
                return
            }
            appState.presentImagePreview(.fileURL(url, title: displayName))
        }
    }

    /// Whether the modal's loader can be expected to decode this file.
    ///
    /// An unreadable size is treated as presentable: the modal owns the real limit and reports its
    /// own error, which is a better outcome than silently bouncing a readable image to another app
    /// because a stat failed.
    static func canPresentInModal(_ url: URL) -> Bool {
        guard let byteSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return true
        }
        return byteSize <= AppImagePreviewLoader.maximumSourceBytes
    }
}
