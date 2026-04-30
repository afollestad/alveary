import Foundation

@MainActor
extension DiffViewerViewModel {
    func loadImagePreview(_ version: DiffImageVersion) async throws -> DiffImagePreviewOutput {
        guard let directory = activeDirectory else {
            throw GitError.commandFailed("No active directory is available for image preview.")
        }

        return try await imagePreviewLoader.loadPreview(
            version: version,
            directory: directory,
            gitService: gitService
        )
    }

    func openImagePreview(_ version: DiffImageVersion) async throws {
        guard let directory = activeDirectory else {
            throw GitError.commandFailed("No active directory is available for image preview.")
        }

        let url = try await imagePreviewLoader.materializeForOpening(
            version: version,
            directory: directory,
            gitService: gitService
        )
        imagePreviewOpener(url)
    }
}
