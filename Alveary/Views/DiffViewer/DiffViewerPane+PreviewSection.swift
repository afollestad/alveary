import SwiftUI

struct DiffViewerPreviewSection: View {
    let selectedFile: FileStatus?
    let selectedFileCount: Int
    let parsedDiff: DiffFile?
    let imagePreview: DiffImagePreview?
    let rawDiffContent: String
    let errorMessage: String?
    let isPending: Bool
    let isLoading: Bool
    let fileDisplayName: (FileStatus) -> String
    let statusTitle: (FileStatus.Status) -> String
    let diffPreviewIdentity: (FileStatus) -> String
    let loadImage: (DiffImageVersion) async throws -> DiffImagePreviewOutput
    let openImage: (DiffImageVersion) async throws -> Void

    var body: some View {
        Group {
            if selectedFileCount > 1 {
                EmptyStateView(
                    icon: "doc.on.doc",
                    heading: "\(selectedFileCount) files selected",
                    subtext: "Select one file to preview its diff.",
                    actions: []
                )
            } else if let selectedFile {
                VStack(alignment: .leading, spacing: 4) {
                    DiffPreviewHeader(
                        title: fileDisplayName(selectedFile),
                        fileStatus: selectedFile,
                        parsedDiff: parsedDiff,
                        statusTitle: statusTitle(selectedFile.status)
                    )

                    DiffPreviewContent(
                        parsedDiff: parsedDiff,
                        imagePreview: imagePreview,
                        rawDiffContent: rawDiffContent,
                        errorMessage: errorMessage,
                        isPending: isPending,
                        isLoading: isLoading,
                        loadImage: loadImage,
                        openImage: openImage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(diffPreviewIdentity(selectedFile))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                EmptyStateView(
                    icon: "doc.plaintext",
                    heading: "Select a file",
                    subtext: "Choose a changed file to preview its diff.",
                    actions: []
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
