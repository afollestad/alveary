import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Paperclip control that picks local files and hands them to an uploader,
/// swapping to a spinner while the upload runs. Shared by the inline comment
/// editors and the review footer's summary editor.
struct PullRequestCommentAttachButton: View {
    let isUploading: Bool
    let onPick: ([URL]) -> Void

    var body: some View {
        Group {
            if isUploading {
                // Same footprint as the button so the row cannot shift.
                StatusIndicatorSpinner(color: .secondary, diameter: 14, lineWidth: 2)
                    .frame(width: 26, height: 20)
                    .accessibilityLabel("Uploading attachments")
            } else {
                Button {
                    presentPicker()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach files")
                .accessibilityLabel("Attach files")
            }
        }
    }

    private func presentPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose files to attach to this comment"
        panel.prompt = "Attach"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else {
            return
        }
        onPick(panel.urls)
    }
}

extension View {
    /// Accepts dropped files as comment attachments.
    ///
    /// Apply this to the editor's *container*, never to `PullRequestCommentEditor`
    /// itself: the editor derives its height from `BlockInputEditor.sizeThatFits`,
    /// and wrapping it changes the size proposal it answers, which silently
    /// collapses the editor by a visible line.
    func pullRequestAttachmentDropTarget(
        isEnabled: Bool,
        onDrop: @escaping ([URL]) -> Void
    ) -> some View {
        modifier(PullRequestAttachmentDropModifier(isEnabled: isEnabled, onDrop: onDrop))
    }
}

private struct PullRequestAttachmentDropModifier: ViewModifier {
    let isEnabled: Bool
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false

    private var targetedBinding: Binding<Bool> {
        Binding(
            get: { isTargeted },
            set: { isTargeted = isEnabled && $0 }
        )
    }

    /// Item providers deliver file URLs asynchronously; collect them all, then
    /// hand the batch over on the main actor in the drag's original order.
    private func loadFileURLs(from providers: [NSItemProvider]) {
        let collector = DroppedFileCollector(expected: providers.count, onComplete: onDrop)
        for (index, provider) in providers.enumerated() {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    collector.accept(url, at: index)
                }
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: targetedBinding) { providers in
                guard isEnabled else {
                    return false
                }
                loadFileURLs(from: providers)
                return true
            }
    }
}

/// Gathers asynchronously resolved drop URLs and reports them once, in the
/// drag's original order, dropping entries that failed to resolve.
@MainActor
private final class DroppedFileCollector {
    private var urls: [Int: URL] = [:]
    private var remaining: Int
    private let onComplete: ([URL]) -> Void

    init(expected: Int, onComplete: @escaping ([URL]) -> Void) {
        remaining = expected
        self.onComplete = onComplete
    }

    func accept(_ url: URL?, at index: Int) {
        if let url, url.isFileURL {
            urls[index] = url
        }
        remaining -= 1
        guard remaining <= 0 else {
            return
        }
        let ordered = urls.keys.sorted().compactMap { urls[$0] }
        guard !ordered.isEmpty else {
            return
        }
        onComplete(ordered)
    }
}
