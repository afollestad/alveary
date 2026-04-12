import XCTest

@testable import Alveary

extension SnapshotTests {
    func testProjectSettingsViewHidesGitHubForLocalProject() throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.89.0", gitHubAuthenticated: false)
        let project = Project(path: "/tmp/local-project", name: "Local Project")
        fixture.context.insert(project)
        try fixture.context.save()

        assertMacSnapshot(
            ProjectSettingsView(
                project: project,
                gitHubCLI: fixture.gitHubCLI,
                providerDetection: StubProviderDetectionService(),
                agentRegistry: DefaultAgentRegistry()
            )
            .modelContainer(fixture.container),
            size: CGSize(width: 1100, height: 900),
            named: "project_settings_local_project"
        )
    }

    func testDiffViewerPaneHeaderOpenPRAction() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                contextualAction: .openPR,
                selectedFile: nil,
                areAgentActionsEnabled: true,
                onRefresh: {},
                onCommitRequested: {},
                onOpenPRRequested: {},
                onViewPRRequested: { _ in },
                onStageSelectedFile: {},
                onUnstageSelectedFile: {},
                onDiscardSelectedFile: {}
            ),
            size: CGSize(width: 460, height: 92),
            named: "diff_viewer_header_open_pr"
        )
    }
}
