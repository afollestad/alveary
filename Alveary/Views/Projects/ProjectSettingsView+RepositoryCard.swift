import SwiftUI

/// The `GroupBox` label sits a size below body text, so the branch glyph takes
/// a smaller box than the settings sidebar's.
private let repositoryCardOcticonSize: CGFloat = 14

struct ProjectSettingsRepositoryCard: View {
    let sourceFolder: SourceFolderSnapshot

    init(sourceFolder: SourceFolderSnapshot) { self.sourceFolder = sourceFolder }

    init(project: Project) {
        sourceFolder = project.primaryFolder?.snapshot ?? SourceFolderSnapshot(path: "")
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Base branch", value: sourceFolder.baseRef ?? "Unknown")
                LabeledContent("Remote", value: sourceFolder.remoteName ?? "Local only")
                LabeledContent("Remote URL", value: sourceFolder.gitRemote ?? "Not configured")
                LabeledContent("GitHub repo") {
                    if let githubRepository = sourceFolder.githubRepository,
                       let githubRepositoryURL = URL(string: "https://github.com/" + githubRepository) {
                        Link(githubRepository, destination: githubRepositoryURL)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Not a GitHub remote")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
        } label: {
            Label {
                Text("Git")
            } icon: {
                OcticonImage(octicon: .gitBranch16, size: repositoryCardOcticonSize)
            }
        }
    }
}
