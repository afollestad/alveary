import AppKit
import SwiftData
import SwiftUI

struct ProjectSettingsView: View {
    let project: Project
    let gitHubCLI: GitHubCLIService
    let providerDetection: any ProviderDetectionService
    let agentRegistry: AgentRegistry

    @Environment(\.modelContext) private var modelContext
    @State private var config: AlvearyProjectConfig?
    @State private var providerStatuses: [String: ProviderStatus] = [:]
    @State private var gitHubInstalledVersion: String?
    @State private var isGitHubAuthenticating = false
    @State private var gitHubDeviceCode: GitHubDeviceCode?
    @State private var screenError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProjectSettingsHeader(projectName: project.name)

                if let screenError {
                    InlineBanner(message: screenError, severity: .error, autoDismissAfter: nil) {
                        self.screenError = nil
                    }
                }

                ProjectSettingsProjectCard(
                    projectPath: project.path,
                    projectName: Binding(
                        get: { project.name },
                        set: { newValue in
                            project.name = newValue
                            saveProject()
                        }
                    )
                )
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
                ProjectSettingsAgentsCard(
                    agentRegistry: agentRegistry,
                    providerStatuses: providerStatuses,
                    allProvidersMissing: allProvidersMissing,
                    statusDescription: statusDescription,
                    shortStatusLabel: shortStatusLabel,
                    statusColor: statusColor,
                    onRefresh: {
                        Task { await refreshProviderStatuses() }
                    }
                )
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

    var allProvidersMissing: Bool {
        let statuses = providerStatuses.values
        return !statuses.isEmpty && statuses.allSatisfy { $0 == .missing }
    }

    var configURL: URL {
        URL(fileURLWithPath: project.path).appendingPathComponent(".alveary.json")
    }

    func loadState() async {
        config = await AlvearyProjectConfig(projectPath: project.path)
        gitHubInstalledVersion = await gitHubCLI.checkInstalled()
        await refreshProviderStatuses()
    }

    func refreshProviderStatuses() async {
        await providerDetection.checkAllProviders()
        var newStatuses: [String: ProviderStatus] = [:]
        for agent in agentRegistry.agents where agent.provider != nil {
            newStatuses[agent.id] = await providerDetection.status(for: agent.id)
        }
        providerStatuses = newStatuses
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

    func shortStatusLabel(for status: ProviderStatus) -> String {
        switch status {
        case .connected:
            return "Connected"
        case .needsKey:
            return "Needs Key"
        case .missing:
            return "Missing"
        case .error:
            return "Error"
        case .unchecked:
            return "Checking"
        }
    }

    func statusDescription(for status: ProviderStatus) -> String {
        switch status {
        case .connected(let path, let version):
            return "\(version) at \(path)"
        case .needsKey:
            return "CLI found, but it still needs authentication or an API key."
        case .missing:
            return "Not installed on this Mac yet."
        case .error(let message):
            return message
        case .unchecked:
            return "Checking installation status."
        }
    }

    func statusColor(for status: ProviderStatus) -> Color {
        switch status {
        case .connected:
            return .green
        case .needsKey:
            return .orange
        case .missing:
            return .secondary
        case .error:
            return .red
        case .unchecked:
            return .blue
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
