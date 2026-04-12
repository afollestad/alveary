import SwiftData
import SwiftUI

struct ProjectSettingsView: View {
    let project: Project

    @Environment(\.modelContext) private var modelContext
    @State private var config: AlvearyProjectConfig?
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
