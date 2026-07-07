import SwiftUI

struct SettingsScreen: View {
    private static let sidebarLayoutMinimumWidth: CGFloat = 700
    private static let sidebarWidth: CGFloat = 180

    let viewModel: SettingsViewModel
    let gitHubCLI: GitHubCLIService
    let appUpdateManager: AppUpdateManager
    let targetPage: AppSettings.SettingsPage?
    let onTargetPageHandled: ((AppSettings.SettingsPage) -> Void)?
    let onClose: (() -> Void)?

    @State private var selectedPage: AppSettings.SettingsPage

    init(
        viewModel: SettingsViewModel,
        gitHubCLI: GitHubCLIService,
        appUpdateManager: AppUpdateManager,
        targetPage: AppSettings.SettingsPage? = nil,
        onTargetPageHandled: ((AppSettings.SettingsPage) -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        initialTabRawValue: String? = nil
    ) {
        self.viewModel = viewModel
        self.gitHubCLI = gitHubCLI
        self.appUpdateManager = appUpdateManager
        self.targetPage = targetPage
        self.onTargetPageHandled = onTargetPageHandled
        self.onClose = onClose
        _selectedPage = State(
            initialValue: targetPage ?? Self.initialPage(
                rawValue: initialTabRawValue,
                storedPage: viewModel.lastSettingsPage
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= Self.sidebarLayoutMinimumWidth {
                sidebarLayout(width: proxy.size.width)
            } else {
                stackedLayout(width: proxy.size.width)
            }
        }
        .task(id: selectedPage) {
            await checkAppUpdatesIfNeeded(for: selectedPage)
        }
        .task(id: targetPage) {
            await applyTargetPageIfNeeded(targetPage)
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
            Picker("Settings section", selection: selectedPageBinding) {
                ForEach(AppSettings.SettingsPage.allCases) { page in
                    Text(page.title).tag(page)
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
        List(AppSettings.SettingsPage.allCases) { page in
            Label {
                Text(page.title)
            } icon: {
                Image(systemName: page.icon)
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .appSelectableRow(
                isSelected: selectedPage == page,
                action: { selectPage(page) }
            )
        }
    }

    private func settingsDetail(width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsScreenHeader(
                    title: selectedPage.title,
                    description: selectedPage.description,
                    onClose: onClose
                )

                selectedPageView
            }
            .padding(28)
            .frame(width: width, alignment: .leading)
        }
        .scrollClipDisabled(false)
    }

    @ViewBuilder
    private var selectedPageView: some View {
        switch selectedPage {
        case .agents:
            AgentsSettingsTabView(
                viewModel: viewModel,
                providerIDs: viewModel.availableProviderIDs,
                providerExtraArgsBinding: providerExtraArgsBinding,
                contextManagementEnabled: binding(for: \.contextManagementEnabled),
                sessionHandoffWindowPercentage: binding(for: \.sessionHandoffWindowPercentage),
                handoffSteeringEnabled: binding(for: \.handoffSteeringEnabled),
                handoffSteeringCountdownSeconds: binding(for: \.handoffSteeringCountdownSeconds),
                handoffPromptSendCountdownSeconds: binding(for: \.handoffPromptSendCountdownSeconds),
                handoffContextCustomizationEnabled: binding(for: \.handoffContextCustomizationEnabled),
                sessionHandoffPrompt: binding(for: \.sessionHandoffPrompt)
            )
        case .interface:
            InterfaceSettingsTabView(
                viewModel: viewModel,
                theme: binding(for: \.theme),
                codeFontFamily: binding(for: \.codeFontFamily),
                codeFontSize: binding(for: \.codeFontSize),
                chatFontSize: binding(for: \.chatFontSize)
            )
        case .appShots:
            AppShotsSettingsTabView(
                appShotsEnabled: binding(for: \.appShotsEnabled),
                appShotShortcut: binding(for: \.appShotShortcut)
            )
        case .git:
            GitSettingsTabView(
                gitHubCLI: gitHubCLI,
                branchPrefix: binding(for: \.branchPrefix),
                commitMessageGenerationPrompt: binding(for: \.commitMessageGenerationPrompt),
                worktreesBaseDirectory: binding(for: \.worktreesBaseDirectory)
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
                defaultThreadCleanupAction: binding(for: \.defaultThreadCleanupAction),
                defaultEnterBehavior: binding(for: \.defaultEnterBehavior),
                reopenLastThreadAndConversationOnLaunch: binding(for: \.reopenLastThreadAndConversationOnLaunch),
                turnAwakeEnabled: binding(for: \.turnAwakeEnabled),
                turnAwakePreventDisplaySleep: binding(for: \.turnAwakePreventDisplaySleep),
                createWorktreeByDefault: binding(for: \.createWorktreeByDefault),
                autoTrustProjects: binding(for: \.autoTrustProjects)
            )
        case .appUpdates:
            AppUpdatesSettingsTabView(updateManager: appUpdateManager)
        }
    }
}

private extension SettingsScreen {
    static func initialPage(
        rawValue: String?,
        storedPage: AppSettings.SettingsPage
    ) -> AppSettings.SettingsPage {
        guard let rawValue else {
            return storedPage
        }
        return AppSettings.SettingsPage(rawValue: rawValue) ?? .agents
    }

    var selectedPageBinding: Binding<AppSettings.SettingsPage> {
        Binding(
            get: { selectedPage },
            set: { selectPage($0) }
        )
    }

    func selectPage(_ page: AppSettings.SettingsPage) {
        guard selectedPage != page else {
            if page == .appUpdates {
                Task { await appUpdateManager.forceCheck() }
            }
            return
        }
        selectedPage = page
        viewModel.lastSettingsPage = page
    }

    func checkAppUpdatesIfNeeded(for page: AppSettings.SettingsPage) async {
        guard page == .appUpdates,
              targetPage == nil else {
            return
        }
        await appUpdateManager.forceCheck()
    }

    func applyTargetPageIfNeeded(_ page: AppSettings.SettingsPage?) async {
        guard let page else {
            return
        }

        if selectedPage != page {
            selectedPage = page
            viewModel.lastSettingsPage = page
        }

        if page == .appUpdates {
            await appUpdateManager.forceCheck()
        }

        onTargetPageHandled?(page)
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

private extension AppSettings.SettingsPage {
    var title: String {
        switch self {
        case .agents:
            return "Agents"
        case .interface:
            return "Appearance"
        case .appShots:
            return "App shots"
        case .git:
            return "Git"
        case .notifications:
            return "Notifications"
        case .terminal:
            return "Terminal"
        case .threads:
            return "Threads"
        case .appUpdates:
            return "Updates"
        }
    }

    var icon: String {
        switch self {
        case .agents:
            return "brain"
        case .interface:
            return "paintbrush"
        case .appShots:
            return "camera.viewfinder"
        case .git:
            return "arrow.triangle.branch"
        case .notifications:
            return "bell"
        case .terminal:
            return "terminal"
        case .threads:
            return "bubble.left.and.bubble.right"
        case .appUpdates:
            return "arrow.down.circle"
        }
    }

    var description: String {
        switch self {
        case .agents:
            return "Manage agent installs and override CLI settings for each supported provider."
        case .interface:
            return "Adjust theme and typography for the app shell."
        case .appShots:
            return "Configure app-shot capture, shortcuts, and local context permissions."
        case .git:
            return "Configure Git defaults and GitHub authentication for new worktrees."
        case .notifications:
            return "Configure notification delivery and sounds."
        case .terminal:
            return "Configure terminal pane behavior for project actions."
        case .threads:
            return "Manage thread defaults and startup behavior."
        case .appUpdates:
            return "Check GitHub Releases for newer Alveary versions."
        }
    }
}
