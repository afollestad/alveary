import AppKit
import SwiftData
import SwiftUI

struct ProjectSettingsView: View {
    let project: Project
    let gitHubCLI: GitHubCLIService

    @Environment(\.modelContext) private var modelContext
    @State private var config: AlvearyProjectConfig?
    @State private var gitHubInstalledVersion: String?
    @State private var isGitHubAuthenticating = false
    @State private var gitHubDeviceCode: GitHubDeviceCode?
    @State private var screenError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProjectSettingsHeader(
                    projectPath: project.path,
                    projectName: Binding(
                        get: { project.name },
                        set: { newValue in
                            project.name = newValue
                            saveProject()
                        }
                    )
                )

                if let screenError {
                    InlineBanner(message: screenError, severity: .error, autoDismissAfter: nil) {
                        self.screenError = nil
                    }
                }

                if project.isGitRepository {
                    ProjectSettingsRepositoryCard(project: project)

                    ProjectSettingsGitHubCard(
                        gitHubDeviceCode: gitHubDeviceCode,
                        isGitHubConnected: project.githubConnected,
                        gitHubInstalledVersion: gitHubInstalledVersion,
                        isGitHubAuthenticating: isGitHubAuthenticating,
                        onOpenBrowser: {
                            guard let verificationURL = gitHubDeviceCode?.verificationURL else {
                                return
                            }
                            NSWorkspace.shared.open(verificationURL)
                        },
                        onConnectGitHub: {
                            Task { await connectGitHub() }
                        }
                    )
                }

                ProjectSettingsScriptsCard(
                    setupScript: config?.setupScript,
                    teardownScript: config?.teardownScript
                )

                ProjectSettingsActionsCard(actions: config?.actions ?? [])

                ProjectSettingsConfigCard(
                    configExists: configExists,
                    onEditLocalEnvironment: openConfigFile,
                    onCreateConfig: {
                        Task { await createConfigAndOpen() }
                    }
                )
            }
            .padding(28)
        }
        .task(id: project.path) {
            await loadState()
        }
    }
}

private extension ProjectSettingsView {
    var configExists: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    var configURL: URL {
        URL(fileURLWithPath: project.path).appendingPathComponent(".alveary.json")
    }

    func loadState() async {
        config = await AlvearyProjectConfig(projectPath: project.path)
        gitHubInstalledVersion = project.isGitRepository ? await gitHubCLI.checkInstalled() : nil
    }

    func connectGitHub() async {
        guard !isGitHubAuthenticating else {
            return
        }

        isGitHubAuthenticating = true
        defer { isGitHubAuthenticating = false }

        do {
            let deviceCode = try await gitHubCLI.authenticate()
            gitHubDeviceCode = deviceCode
            NSWorkspace.shared.open(deviceCode.verificationURL)

            let didAuthenticate = try await gitHubCLI.awaitAuthentication()
            gitHubDeviceCode = nil
            guard didAuthenticate else {
                screenError = "GitHub authentication did not complete."
                return
            }

            project.githubConnected = true
            saveProject()
        } catch {
            gitHubDeviceCode = nil
            screenError = error.localizedDescription
        }
    }

    func createConfigAndOpen() async {
        do {
            try defaultConfigTemplate.write(to: configURL, atomically: true, encoding: .utf8)
            config = await AlvearyProjectConfig(projectPath: project.path)
            openConfigFile()
        } catch {
            screenError = error.localizedDescription
        }
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configURL)
    }

    func saveProject() {
        do {
            try modelContext.save()
        } catch {
            screenError = error.localizedDescription
        }
    }

    var defaultConfigTemplate: String {
        """
        {
          "scripts": {
            "setup": "",
            "teardown": ""
          },
          "preservePatterns": [
            ".env",
            ".env.local"
          ],
          "actions": []
        }
        """
    }
}
