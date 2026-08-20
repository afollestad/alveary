import Foundation

/// The Changes tab's image rows.
///
/// These mirror the thread Diff Viewer's `loadImagePreview` / `openImagePreview` pair so both hosts
/// drive `FlattenedDiffPreview` the same way; only the byte source differs, because a pull request
/// has no checkout to read from.
@MainActor
extension PullRequestsViewModel {
    func loadDiffImagePreview(
        _ version: DiffImageVersion,
        intent: DiffImageLoadIntent
    ) async throws -> DiffImagePreviewOutput {
        guard let imageBlobFetcher else {
            throw DiffImagePreviewLoaderError.unsupportedSource
        }
        return try await imagePreviewLoader.loadPreview(
            version: version,
            fetcher: imageBlobFetcher,
            intent: intent
        )
    }

    func openDiffImagePreview(_ version: DiffImageVersion) async throws {
        guard let imageBlobFetcher else {
            throw DiffImagePreviewLoaderError.unsupportedSource
        }
        let url = try await imagePreviewLoader.materializeForOpening(
            version: version,
            fetcher: imageBlobFetcher
        )
        imagePreviewOpener(url, version.diffFileName)
    }
}
