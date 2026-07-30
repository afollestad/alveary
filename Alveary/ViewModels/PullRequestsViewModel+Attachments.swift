import Foundation

/// Which comment editor an upload's references belong to. The inline composer
/// (new comments, replies, edits) and the review footer's summary editor own
/// separate drafts, so their in-flight state must be tracked separately.
enum PullRequestAttachmentDestination: Hashable, Sendable {
    case composer
    case reviewSummary
}

/// A `sessionUnavailable` upload failure held for the access-guidance sheet, so
/// Retry can re-run the exact upload. Captures the repository because the pane
/// session that resolved it may be discarded before the user returns from
/// System Settings.
@MainActor
struct PullRequestAttachmentAccessRequest: Identifiable {
    let id = UUID()
    let files: [URL]
    let destination: PullRequestAttachmentDestination
    let repository: String
    let draft: PullRequestCommentDraftBox
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
    /// cancel an upload in flight. A failure withdraws the placeholders and keeps
    /// everything the user typed, then reports through an app toast, because the
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
            presentToast(GitHubAttachmentUploadError.extensionMissing.localizedDescription)
            return
        }
        // Capture the repository now; the session backing it may be discarded
        // while the upload runs.
        guard let repository = activePaneSession?.summary.repositoryNameWithOwner else {
            return
        }
        attachFiles(files, to: destination, repository: repository, draft: draft, using: attachmentUploadService)
    }

    /// Re-runs the upload the access-guidance sheet was presented for, with its
    /// captured repository — the pane that resolved it may already be closed.
    func retryAttachmentUpload() {
        guard let request = attachmentAccessRequest else {
            return
        }
        attachmentAccessRequest = nil
        guard let attachmentUploadService else {
            return
        }
        attachFiles(
            request.files,
            to: request.destination,
            repository: request.repository,
            draft: request.draft,
            using: attachmentUploadService
        )
    }

    func dismissAttachmentAccessRequest() {
        attachmentAccessRequest = nil
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
                let uploads = try await attachmentUploadService.upload(files: files, repository: repository)
                // Seed before the references land in the draft: the editor
                // loads an image block as soon as its markdown appears, and the
                // fresh asset is still session-gated on GitHub's side.
                if let seeder = self?.attachmentImageSeeder {
                    for upload in uploads {
                        await seeder(upload)
                    }
                }
                self?.replacePlaceholders(with: uploads, in: draft)
            } catch is CancellationError {
                // A cancelled upload still owes the draft its placeholders back.
                self?.removePlaceholders(for: files, in: draft)
            } catch {
                self?.removePlaceholders(for: files, in: draft)
                self?.presentUploadFailure(
                    error,
                    files: files,
                    destination: destination,
                    repository: repository,
                    draft: draft
                )
            }
        }
    }

    /// Session-unavailable failures open the access-guidance sheet — the remedy
    /// is a privacy grant or a browser sign-in, which a toast cannot walk the
    /// user through. Everything else keeps the toast.
    private func presentUploadFailure(
        _ error: any Error,
        files: [URL],
        destination: PullRequestAttachmentDestination,
        repository: String,
        draft: PullRequestCommentDraftBox
    ) {
        if case GitHubAttachmentUploadError.sessionUnavailable = error {
            attachmentAccessRequest = PullRequestAttachmentAccessRequest(
                files: files,
                destination: destination,
                repository: repository,
                draft: draft
            )
        } else {
            presentToast(Self.attachmentFailureMessage(files: files, error: error))
        }
    }

    /// GitHub's in-progress marker. Plain text, not `![…]()`: the draft round
    /// trips through `BlockInputDocument`, which rewrites image syntax.
    static func placeholder(for file: URL) -> String {
        "Uploading \(file.lastPathComponent)…"
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
        var markdown = draft.markdown
        for file in files {
            guard let range = markdown.range(of: Self.placeholder(for: file)) else {
                continue
            }
            markdown.removeSubrange(range)
        }
        // Withdrawing a placeholder leaves the line it sat on empty; collapse
        // those so the draft does not accumulate blank paragraphs.
        let lines = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        draft.replaceText(lines.joined(separator: "\n"))
    }

    /// Appends each entry on its own line, keeping whatever the user typed.
    private func appendLines(_ lines: [String], to draft: PullRequestCommentDraftBox) {
        guard !lines.isEmpty else {
            return
        }
        let addition = lines.joined(separator: "\n")
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
