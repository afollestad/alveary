import Foundation

@MainActor
extension DiffViewerViewModel {
    func loadImagePreview(
        _ version: DiffImageVersion,
        intent: DiffImageLoadIntent = .automatic
    ) async throws -> DiffImagePreviewOutput {
        try await imagePreviewLoader.loadPreview(
            version: version,
            fetcher: try imageBlobFetcher(),
            intent: intent
        )
    }

    func openImagePreview(_ version: DiffImageVersion) async throws {
        let url = try await imagePreviewLoader.materializeForOpening(
            version: version,
            fetcher: try imageBlobFetcher()
        )
        imagePreviewOpener(url, version.diffFileName)
    }

    private func imageBlobFetcher() throws -> DiffImageBlobFetching {
        guard let directory = activeDirectory else {
            throw GitError.commandFailed("No active directory is available for image preview.")
        }
        return GitDiffImageBlobFetcher(directory: directory, gitService: gitService)
    }
}
