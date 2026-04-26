import SwiftUI

struct SettingsScreen: View {
    private static let sidebarLayoutMinimumWidth: CGFloat = 700
    private static let sidebarWidth: CGFloat = 180

    let viewModel: SettingsViewModel
    let gitHubCLI: GitHubCLIService
    let onClose: (() -> Void)?

    @State private var selectedTab: SettingsTab = .general

    init(
        viewModel: SettingsViewModel,
        gitHubCLI: GitHubCLIService,
        onClose: (() -> Void)? = nil,
        initialTabRawValue: String = SettingsTab.general.rawValue
    ) {
        self.viewModel = viewModel
        self.gitHubCLI = gitHubCLI
        self.onClose = onClose
        _selectedTab = State(initialValue: SettingsTab(rawValue: initialTabRawValue) ?? .general)
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
        case .general:
            GeneralSettingsTabView(
                viewModel: viewModel,
                defaultProvider: binding(for: \.defaultProvider),
                defaultModel: binding(for: \.defaultModel),
                permissionMode: binding(for: \.permissionMode),
                effort: binding(for: \.effort),
                deleteKeyAction: binding(for: \.deleteKeyAction),
                reopenLastThreadAndConversationOnLaunch: binding(for: \.reopenLastThreadAndConversationOnLaunch),
                createWorktreeByDefault: binding(for: \.createWorktreeByDefault),
                autoTrustProjects: binding(for: \.autoTrustProjects),
                notificationsEnabled: binding(for: \.notificationsEnabled),
                osNotificationsEnabled: binding(for: \.osNotificationsEnabled),
                soundEnabled: binding(for: \.soundEnabled),
                soundName: binding(for: \.soundName)
            )
        case .agents:
            AgentsSettingsTabView(
                viewModel: viewModel,
                providerIDs: viewModel.availableProviderIDs,
                providerConfigBinding: providerConfigBinding
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
        }
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case agents
        case git
        case interface

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:
                return "General"
            case .agents:
                return "Agents"
            case .git:
                return "Git"
            case .interface:
                return "Interface"
            }
        }

        var icon: String {
            switch self {
            case .general:
                return "slider.horizontal.3"
            case .agents:
                return "sparkles.rectangle.stack"
            case .git:
                return "arrow.triangle.branch"
            case .interface:
                return "swatchpalette"
            }
        }
    }
}

private extension SettingsScreen {
    private func description(for tab: SettingsTab) -> String {
        switch tab {
        case .general:
            return "Manage thread defaults, startup behavior, and notification settings."
        case .agents:
            return "Manage agent installs and override CLI settings for each supported provider."
        case .git:
            return "Configure Git defaults and GitHub authentication for new worktrees."
        case .interface:
            return "Adjust theme and typography for the app shell."
        }
    }

    func binding<Value>(for keyPath: ReferenceWritableKeyPath<SettingsViewModel, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    func providerConfigBinding(
        for providerID: String,
        keyPath: WritableKeyPath<ProviderCustomConfig, String?>
    ) -> Binding<String> {
        Binding(
            get: {
                viewModel.providerConfig(for: providerID)[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                viewModel.updateProviderConfig(for: providerID) { config in
                    config[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
                }
            }
        )
    }
}
