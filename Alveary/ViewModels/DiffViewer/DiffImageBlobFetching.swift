import Foundation

/// Where a diff image's bytes live.
///
/// The Diff Viewer reads them out of the thread's checkout; the pull request Changes tab has no
/// checkout to read (`gh pr diff` runs with no working directory, and a review thread is
/// deliberately project-less), so it addresses them on GitHub instead. Both families flow through
/// one `DiffImageVersion` so the cache, identity, and decode path stay shared.
enum DiffImageBlobSource: Sendable, Hashable {
    case git(GitImageBlobSource)
    case gitHub(GitHubImageBlobSource)
}

/// Whether a load is the automatic one a slot starts on scroll, or one the user asked for after the
/// size gate held it back. `confirmed` is what lifts the auto-load ceiling to the hard cap.
enum DiffImageLoadIntent: Sendable, Equatable {
    case automatic
    case confirmed
}

/// Raised when an image is past the ceiling that applies to the current intent. `byteSize` is the
/// discovered size when the transport learned it, so the slot can name it in the confirmation card
/// and decide whether confirming could even help.
struct DiffImageBlobTooLargeError: Error, LocalizedError, Equatable {
    let byteSize: Int?

    var errorDescription: String? {
        "This image is larger than the preview limit."
    }
}

/// Resolves a diff image's bytes. One implementation reads the local checkout, the other GitHub.
protocol DiffImageBlobFetching: Sendable {
    func blob(for source: DiffImageBlobSource, maxBytes: Int) async throws -> Data

    /// A file already on disk holding exactly these bytes, so opening can skip a temp copy. Nil
    /// whenever the bytes must be materialized first — which is always true for remote sources.
    func existingFileURL(for source: DiffImageBlobSource) -> URL?
}

/// Reads image blobs out of a checkout through `GitService`.
struct GitDiffImageBlobFetcher: DiffImageBlobFetching {
    let directory: String
    let gitService: GitService

    func blob(for source: DiffImageBlobSource, maxBytes: Int) async throws -> Data {
        guard case .git(let gitSource) = source else {
            throw DiffImagePreviewLoaderError.unsupportedSource
        }
        return try await gitService.imageBlob(source: gitSource, maxBytes: maxBytes, in: directory)
    }

    func existingFileURL(for source: DiffImageBlobSource) -> URL? {
        guard case .git(.worktree(let path)) = source else {
            return nil
        }
        return URL(fileURLWithPath: directory).appendingPathComponent(path)
    }
}
