import SwiftUI

struct ProjectSettingsRepositoryCard: View {
    let project: Project

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Base branch", value: project.baseRef ?? "Unknown")
                LabeledContent("Remote", value: project.remoteName ?? "Local only")
                LabeledContent("Remote URL", value: project.gitRemote ?? "Not configured")
                LabeledContent("GitHub repo", value: project.githubRepository ?? "Not a GitHub remote")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
        } label: {
            Label("Repository", systemImage: "arrow.triangle.branch")
        }
    }
}
