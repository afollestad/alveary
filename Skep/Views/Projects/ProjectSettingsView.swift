import AppKit
import SwiftData
import SwiftUI

struct ProjectSettingsView: View {
    let project: Project
    let gitHubCLI: GitHubCLIService
    let providerDetection: any ProviderDetectionService
    let agentRegistry: AgentRegistry

    @Environment(\.modelContext) private var modelContext
    @State private var config: SkepProjectConfig?
    @State private var providerStatuses: [String: ProviderStatus] = [:]
    @State private var gitHubInstalledVersion: String?
    @State private var isGitHubAuthenticating = false
    @State private var gitHubDeviceCode: GitHubDeviceCode?
    @State private var screenError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let screenError {
                    InlineBanner(message: screenError, severity: .error, autoDismissAfter: nil) {
                        self.screenError = nil
                    }
                }

                projectCard
                repositoryCard
                gitHubCard
                agentsCard
                scriptsCard
                actionsCard
                configCard
            }
            .padding(28)
        }
        .task(id: project.path) {
            await loadState()
        }
    }
}

private extension ProjectSettingsView {
    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project")
                .font(.largeTitle.weight(.semibold))

            Text(project.name)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    var projectCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text(project.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()

                AppTextField("Project name", text: Binding(
                    get: { project.name },
                    set: { newValue in
                        project.name = newValue
                        saveProject()
                    }
                ))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Project", systemImage: "folder")
        }
    }

    var repositoryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Base branch", value: project.baseRef ?? "Unknown")
                LabeledContent("Remote", value: project.remoteName ?? "Local only")
                LabeledContent("Remote URL", value: project.gitRemote ?? "Not configured")
                LabeledContent("GitHub repo", value: project.githubRepository ?? "Not a GitHub remote")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Repository", systemImage: "arrow.triangle.branch")
        }
    }

    var gitHubCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if let gitHubDeviceCode {
                    Text("Enter the one-time code below in GitHub to finish connecting.")
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(gitHubDeviceCode.code)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)

                        Spacer()

                        Button("Open Browser") {
                            NSWorkspace.shared.open(gitHubDeviceCode.verificationURL)
                        }
                    }
                } else if project.githubConnected {
                    Label("Connected for PR and CI workflows.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if gitHubInstalledVersion == nil {
                    Text("Install the GitHub CLI to enable PR and CI features.")
                        .foregroundStyle(.secondary)

                    Text("brew install gh")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text("Connect GitHub for PR, CI, and agent-opened pull requests.")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if gitHubInstalledVersion != nil && !project.githubConnected {
                        Button(isGitHubAuthenticating ? "Connecting..." : "Connect GitHub") {
                            Task { await connectGitHub() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGitHubAuthenticating)
                    }

                    if let gitHubInstalledVersion {
                        Text(gitHubInstalledVersion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
        }
    }

    var agentsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if providerStatuses.isEmpty || providerStatuses.values.contains(.unchecked) {
                    ProgressView("Checking installed agents...")
                } else if allProvidersMissing {
                    Text("No AI agents found yet. Install one of the supported CLIs below, then refresh.")
                        .foregroundStyle(.secondary)

                    ForEach(agentRegistry.agents.filter { $0.provider != nil }, id: \.id) { agent in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(agent.name)
                                .font(.headline)

                            if let installCommand = agent.installCommand {
                                Text(installCommand)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                } else {
                    ForEach(agentRegistry.agents.filter { $0.provider != nil }, id: \.id) { agent in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name)
                                    .font(.headline)
                                Text(statusDescription(for: providerStatuses[agent.id] ?? .unchecked))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(shortStatusLabel(for: providerStatuses[agent.id] ?? .unchecked))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(statusColor(for: providerStatuses[agent.id] ?? .unchecked).opacity(0.16)))
                        }
                    }
                }

                Button("Refresh") {
                    Task { await refreshProviderStatuses() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("AI Agents", systemImage: "sparkles.rectangle.stack")
        }
    }

    var scriptsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Setup script")
                        .font(.headline)
                    scriptBlock(config?.setupScript, placeholder: "No setup script configured.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleanup script")
                        .font(.headline)
                    scriptBlock(config?.teardownScript, placeholder: "No cleanup script configured.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Lifecycle Scripts", systemImage: "terminal")
        }
    }

    var actionsCard: some View {
        GroupBox {
            if let actions = config?.actions, !actions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(actions, id: \.name) { action in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.name)
                                .font(.headline)
                            Text(action.command)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No custom project actions are configured yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("Actions", systemImage: "play.square")
        }
    }

    var configCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("The local `.skep.json` file controls setup scripts, preserved files, and project actions.")
                    .foregroundStyle(.secondary)

                HStack {
                    if configExists {
                        Button("Edit Local Environment") {
                            openConfigFile()
                        }
                    } else {
                        Button("Create Config") {
                            Task { await createConfigAndOpen() }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Environment Config", systemImage: "doc.text")
        }
    }

    var configExists: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    var allProvidersMissing: Bool {
        let statuses = providerStatuses.values
        return !statuses.isEmpty && statuses.allSatisfy { $0 == .missing }
    }

    var configURL: URL {
        URL(fileURLWithPath: project.path).appendingPathComponent(".skep.json")
    }

    func scriptBlock(_ script: String?, placeholder: String) -> some View {
        Group {
            if let script, !script.isEmpty {
                Text(script)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
            } else {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
        }
    }

    func loadState() async {
        config = await SkepProjectConfig(projectPath: project.path)
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
            config = await SkepProjectConfig(projectPath: project.path)
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
