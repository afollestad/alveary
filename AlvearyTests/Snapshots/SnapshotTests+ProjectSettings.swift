import XCTest

@testable import Alveary

extension SnapshotTests {
    func testProjectSettingsViewHidesGitHubForLocalProject() throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.89.0", gitHubAuthenticated: false)
        let project = Project(path: "/tmp/local-project", name: "Local Project")
        fixture.context.insert(project)
        try fixture.context.save()

        assertMacSnapshot(
            ProjectSettingsView(project: project)
            .modelContainer(fixture.container),
            size: CGSize(width: 1100, height: 900),
            named: "project_settings_local_project"
        )
    }

    func testProjectSettingsViewShowsGitHubRepoLink() throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.89.0", gitHubAuthenticated: false)
        let project = Project(
            path: "/tmp/github-project",
            name: "GitHub Project",
            gitRemote: "https://github.com/afollestad/personal-ai-skills.git",
            remoteName: "origin",
            gitBranch: "main",
            baseRef: "main",
            githubRepository: "afollestad/personal-ai-skills"
        )
        fixture.context.insert(project)
        try fixture.context.save()

        assertMacSnapshot(
            ProjectSettingsView(project: project)
            .modelContainer(fixture.container),
            size: CGSize(width: 1100, height: 900),
            named: "project_settings_github_project"
        )
    }
}
