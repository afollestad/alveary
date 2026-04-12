import SwiftUI

struct DiffViewerPreviewSection: View {
    let selectedFile: FileStatus?
    let parsedDiff: DiffFile?
    let rawDiffContent: String
    let isLoading: Bool
    let fileDisplayName: (FileStatus) -> String
    let statusTitle: (FileStatus.Status) -> String
    let diffPreviewIdentity: (FileStatus) -> String

    var body: some View {
        Group {
            if let selectedFile {
                VStack(alignment: .leading, spacing: 4) {
                    DiffPreviewHeader(
                        title: fileDisplayName(selectedFile),
                        fileStatus: selectedFile,
                        parsedDiff: parsedDiff,
                        statusTitle: statusTitle(selectedFile.status)
                    )

                    DiffPreviewContent(
                        parsedDiff: parsedDiff,
                        rawDiffContent: rawDiffContent,
                        isLoading: isLoading
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
