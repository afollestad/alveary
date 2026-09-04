import Foundation

/// Which comment editor an upload's references belong to. The inline composer
/// (new comments, replies, edits) and the review footer's summary editor own
/// separate drafts, so their in-flight state must be tracked separately.
enum PullRequestAttachmentDestination: Hashable, Sendable {
    case composer
    case reviewSummary
}

extension PullRequestsViewModel {
    /// Whether an upload targeting `destination` is running. Hosts disable their
    /// save/submit action and show progress while it is true.
    func isUploadingAttachments(to destination: PullRequestAttachmentDestination) -> Bool {
        attachmentUploadsInFlight.contains(destination)
    }

    var supportsAttachmentUploads: Bool {
        attachmentUploadService != nil
    }

    /// Uploads `files`, showing a placeholder line per file in `draft` right away
    /// and swapping each placeholder for its real link when the upload lands —
    /// the same immediate feedback GitHub's own drag-and-drop gives.
    ///
    /// The work runs in an unstructured view-model-owned task: the view model is
    /// root-lived, so closing the pane or leaving the Pull requests screen cannot
    /// cancel an upload in flight. Partial failures keep successful references and
    /// withdraw remaining placeholders. Errors report through an app toast because the
    /// originating pane may be gone by the time the failure lands.
    func attachFiles(
        _ files: [URL],
        to destination: PullRequestAttachmentDestination,
        draft: PullRequestCommentDraftBox
    ) {
        guard !files.isEmpty else {
            return
        }
        guard let attachmentUploadService else {
            presentToast("Attachment uploads are unavailable.")
            return
        }
        // Capture the repository now; the session backing it may be discarded
        // while the upload runs. The target names it even before the session has
        // a summary, which an identifier-opened pane lacks until its detail lands.
        guard let repository = activePaneTarget?.identifier.nameWithOwner else {
            return
        }
        attachFiles(files, to: destination, repository: repository, draft: draft, using: attachmentUploadService)
    }

    /// GitHub's in-progress marker. Plain text, not `![…]()`: the draft round
    /// trips through `BlockInputDocument`, which rewrites image syntax.
    static func placeholder(for file: URL) -> String {
        let name = file.lastPathComponent
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return "Uploading \(name)…"
    }

    private func attachFiles(
        _ files: [URL],
        to destination: PullRequestAttachmentDestination,
        repository: String,
        draft: PullRequestCommentDraftBox,
        using attachmentUploadService: any GitHubAttachmentUploadService
    ) {
        guard !attachmentUploadsInFlight.contains(destination) else {
            return
        }

        attachmentUploadsInFlight.insert(destination)
        appendLines(files.map(Self.placeholder(for:)), to: draft)
        Task { [weak self] in
            defer { self?.attachmentUploadsInFlight.remove(destination) }
            do {
                let batch = try await attachmentUploadService.upload(files: files, repository: repository)
                // Seed before the references land in the draft: the editor
                // loads an image block as soon as its markdown appears, and the
                // fresh asset is still session-gated on GitHub's side.
                if let seeder = self?.attachmentImageSeeder {
                    for upload in batch.uploads {
                        await seeder(upload)
                    }
                }
                self?.replacePlaceholders(with: batch.uploads, in: draft)
                let remaining = Array(files.dropFirst(batch.uploads.count))
                self?.removePlaceholders(for: remaining, in: draft)
                if let failure = batch.failure, failure != .cancelled {
                    self?.presentToast(Self.attachmentFailureMessage(files: remaining, error: failure))
                }
            } catch is CancellationError {
                // A cancelled upload still owes the draft its placeholders back.
                self?.removePlaceholders(for: files, in: draft)
            } catch {
                self?.removePlaceholders(for: files, in: draft)
                if !Task.isCancelled {
                    self?.presentToast(Self.attachmentFailureMessage(files: files, error: error))
                }
            }
        }
    }

    /// Swaps each file's placeholder for its reference, in order, so duplicate
    /// filenames still map to the right link. A placeholder the user deleted
    /// while the upload ran is appended instead of silently dropped.
    private func replacePlaceholders(
        with uploads: [GitHubAttachmentUpload],
        in draft: PullRequestCommentDraftBox
    ) {
        var markdown = draft.markdown
        var unplaced: [String] = []
        for upload in uploads {
            let placeholder = Self.placeholder(for: upload.fileURL)
            if let range = markdown.range(of: placeholder) {
                markdown.replaceSubrange(range, with: upload.markdownReference)
            } else {
                unplaced.append(upload.markdownReference)
            }
        }
        draft.replaceText(markdown)
        appendLines(unplaced, to: draft)
    }

    private func removePlaceholders(for files: [URL], in draft: PullRequestCommentDraftBox) {
        guard !files.isEmpty else {
            return
        }
        var lines = draft.markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for file in files {
            let placeholder = Self.placeholder(for: file)
            if let index = lines.firstIndex(where: { $0.contains(placeholder) }),
               let range = lines[index].range(of: placeholder) {
                lines[index].removeSubrange(range)
                if lines[index].isEmpty {
                    lines.remove(at: index)
                }
            }
        }
        draft.replaceText(lines.joined(separator: "\n"))
    }

    /// Appends each entry on its own line, keeping whatever the user typed.
    private func appendLines(_ lines: [String], to draft: PullRequestCommentDraftBox) {
        guard !lines.isEmpty else {
            return
        }
        let addition = lines.joined(separator: "\n\n")
        let existing = draft.markdown
        // A blank line keeps the addition its own paragraph. No trailing newline:
        // the document round trip strips it anyway.
        let separator = existing.isEmpty ? "" : (existing.hasSuffix("\n") ? "\n" : "\n\n")
        draft.replaceText(existing + separator + addition)
    }

    private static func attachmentFailureMessage(files: [URL], error: any Error) -> String {
        let subject = files.count == 1
            ? "Uploading \(files[0].lastPathComponent) failed."
            : "Uploading \(files.count) attachments failed."
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else {
            return subject
        }
        return "\(subject) \(detail)"
    }
}
