import SwiftUI

struct SettingsScreen: View {
    private static let sidebarLayoutMinimumWidth: CGFloat = 700
    private static let sidebarWidth: CGFloat = 180

    let viewModel: SettingsViewModel
    let gitHubCLI: GitHubCLIService
    let onClose: (() -> Void)?

    @State private var selectedTab: SettingsTab = .agents

    init(
        viewModel: SettingsViewModel,
        gitHubCLI: GitHubCLIService,
        onClose: (() -> Void)? = nil,
        initialTabRawValue: String = SettingsTab.agents.rawValue
    ) {
        self.viewModel = viewModel
        self.gitHubCLI = gitHubCLI
        self.onClose = onClose
        _selectedTab = State(initialValue: SettingsTab(rawValue: initialTabRawValue) ?? .agents)
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= Self.sidebarLayoutMinimumWidth {
                sidebarLayout(width: proxy.size.width)
            } else {
                stackedLayout(width: proxy.size.width)
            }
        }
    }

    private func sidebarLayout(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: Self.sidebarWidth)
                .layoutPriority(1)

            Divider()

            settingsDetail(width: max(width - Self.sidebarWidth - 1, 0))
                .clipped()
        }
    }

    private func stackedLayout(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Settings section", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 4)

            settingsDetail(width: width)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsSidebar: some View {
        List(SettingsTab.allCases) { tab in
            Label {
                Text(tab.title)
            } icon: {
                Image(systemName: tab.icon)
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .appSelectableRow(
                isSelected: selectedTab == tab,
                action: { selectedTab = tab }
            )
        }
    }

    private func settingsDetail(width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsScreenHeader(
                    title: selectedTab.title,
                    description: description(for: selectedTab),
                    onClose: onClose
                )

                selectedTabView
            }
            .padding(28)
            .frame(width: width, alignment: .leading)
        }
        .scrollClipDisabled(false)
    }

    @ViewBuilder
    private var selectedTabView: some View {
        switch selectedTab {
        case .agents:
            AgentsSettingsTabView(
                viewModel: viewModel,
                providerIDs: viewModel.availableProviderIDs,
                providerExtraArgsBinding: providerExtraArgsBinding
            )
        case .git:
            GitSettingsTabView(
                gitHubCLI: gitHubCLI,
                branchPrefix: binding(for: \.branchPrefix),
                worktreesBaseDirectory: binding(for: \.worktreesBaseDirectory)
            )
        case .interface:
            InterfaceSettingsTabView(
                viewModel: viewModel,
                theme: binding(for: \.theme),
                codeFontFamily: binding(for: \.codeFontFamily),
                codeFontSize: binding(for: \.codeFontSize),
                chatFontSize: binding(for: \.chatFontSize)
            )
        case .notifications:
            NotificationsSettingsTabView(
                viewModel: viewModel,
                notificationsEnabled: binding(for: \.notificationsEnabled),
                osNotificationsEnabled: binding(for: \.osNotificationsEnabled),
                soundEnabled: binding(for: \.soundEnabled),
                soundName: binding(for: \.soundName)
            )
        case .terminal:
            TerminalSettingsTabView(
                expandTerminalWhenActionsRun: binding(for: \.expandTerminalWhenActionsRun),
                maxTerminalSessions: binding(for: \.maxTerminalSessions)
            )
        case .threads:
            ThreadsSettingsTabView(
                viewModel: viewModel,
                defaultProvider: binding(for: \.defaultProvider),
                defaultModel: binding(for: \.defaultModel),
                permissionMode: binding(for: \.permissionMode),
                effort: binding(for: \.effort),
                deleteKeyAction: binding(for: \.deleteKeyAction),
                reopenLastThreadAndConversationOnLaunch: binding(for: \.reopenLastThreadAndConversationOnLaunch),
                createWorktreeByDefault: binding(for: \.createWorktreeByDefault),
                autoTrustProjects: binding(for: \.autoTrustProjects)
            )
        }
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case agents
        case git
        case interface
        case notifications
        case terminal
        case threads

        var id: String { rawValue }

        var title: String {
            switch self {
            case .agents:
                return "Agents"
            case .git:
                return "Git"
            case .interface:
                return "Interface"
            case .notifications:
                return "Notifications"
            case .terminal:
                return "Terminal"
            case .threads:
                return "Threads"
            }
        }

        var icon: String {
            switch self {
            case .agents:
                return "sparkles.rectangle.stack"
            case .git:
                return "arrow.triangle.branch"
            case .interface:
                return "swatchpalette"
            case .notifications:
                return "bell"
            case .terminal:
                return "terminal"
            case .threads:
                return "bubble.left.and.bubble.right"
            }
        }
    }
}

private extension SettingsScreen {
    private func description(for tab: SettingsTab) -> String {
        switch tab {
        case .agents:
            return "Manage agent installs and override CLI settings for each supported provider."
        case .git:
            return "Configure Git defaults and GitHub authentication for new worktrees."
        case .interface:
            return "Adjust theme and typography for the app shell."
        case .notifications:
            return "Configure notification delivery and sounds."
        case .terminal:
            return "Configure terminal pane behavior for project actions."
        case .threads:
            return "Manage thread defaults and startup behavior."
        }
    }

    func binding<Value>(for keyPath: ReferenceWritableKeyPath<SettingsViewModel, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    func providerExtraArgsBinding(for providerID: String) -> Binding<String> {
        Binding(
            get: {
                viewModel.providerExtraArgs(for: providerID) ?? ""
            },
            set: { newValue in
                viewModel.updateProviderExtraArgs(for: providerID, extraArgs: newValue.isEmpty ? nil : newValue)
            }
        )
    }
}
