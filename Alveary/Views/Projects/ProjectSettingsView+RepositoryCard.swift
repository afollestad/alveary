import SwiftUI

struct ProjectSettingsRepositoryCard: View {
    let sourceFolder: SourceFolderSnapshot
    init(sourceFolder: SourceFolderSnapshot) { self.sourceFolder = sourceFolder }

    init(project: Project) {
        self.init(sourceFolder: project.primaryFolder?.snapshot ?? SourceFolderSnapshot(path: ""))
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                branchLabel.fixedSize()
                repositoryLink.fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                branchLabel
                repositoryLink
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var branchLabel: some View {
        Label {
            Text("Base branch: \(sourceFolder.baseRef ?? "Unknown")")
        } icon: {
            OcticonImage(octicon: .gitBranch16, size: 14)
        }
        .font(.callout)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var repositoryLink: some View {
        if let repository = sourceFolder.githubRepository,
           let url = URL(string: "https://github.com/" + repository) {
            Link(repository, destination: url)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
