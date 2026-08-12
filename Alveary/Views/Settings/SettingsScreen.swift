import SwiftUI

struct SettingsScreen: View {
    private static let sidebarLayoutMinimumWidth: CGFloat = 700
    private static let sidebarWidth: CGFloat = 180
    /// Resolved once rather than per body run: the compact strip is built inside a
    /// `GeometryReader`, and these titles never change.
    private static let compactNavigationItems = AppSettings.SettingsPage.allCases.map {
        SettingsScreenCompactNavigationItem(page: $0, title: $0.title)
    }
    /// A couple of points over the row's body font, because octicon artwork
    /// under-fills its canvas beside the SF Symbols in the sibling rows.
    private static let sidebarOcticonSize: CGFloat = 16

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
            SettingsScreenCompactNavigation(
                items: Self.compactNavigationItems,
                selection: selectedPage,
                onSelect: selectPage
            )
            .equatable()
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
                ActionIconImage(icon: page.icon, octiconSize: Self.sidebarOcticonSize)
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
                    refresh: headerRefresh,
                    onClose: onClose
                )

                selectedPageView
            }
            .padding(SettingsScreenLayout.settingsContentInset)
            .frame(width: width, alignment: .leading)
        }
        .scrollClipDisabled(false)
    }

    /// Only the Agents page offers a header refresh; it re-checks every provider status.
    private var headerRefresh: SettingsScreenHeaderRefresh? {
        guard selectedPage == .agents else {
            return nil
        }
        return SettingsScreenHeaderRefresh(
            accessibilityLabel: "Refresh agent statuses",
            isRefreshing: !viewModel.hasLoadedProviderStatuses,
            action: {
                Task {
                    await viewModel.refreshProviderStatuses()
                }
            }
        )
    }

    @ViewBuilder
    private var selectedPageView: some View {
        switch selectedPage {
        case .agents:
            AgentsSettingsTabView(
                viewModel: viewModel,
                providerIDs: viewModel.availableProviderIDs,
                providerExtraArgsBinding: providerExtraArgsBinding
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
                appShotShortcut: binding(for: \.appShotShortcut),
                voiceInputShortcut: viewModel.voiceInputShortcut
            )
        case .git:
            GitSettingsTabView(
                gitHubCLI: gitHubCLI,
                viewModel: viewModel,
                branchPrefix: binding(for: \.branchPrefix),
                commitMessageGenerationPrompt: binding(for: \.commitMessageGenerationPrompt),
                pullRequestGenerationPrompt: binding(for: \.pullRequestGenerationPrompt),
                pullRequestReviewPrompt: binding(for: \.pullRequestReviewPrompt),
                pullRequestAddressFeedbackPrompt: binding(for: \.pullRequestAddressFeedbackPrompt),
                worktreesBaseDirectory: binding(for: \.worktreesBaseDirectory),
                createWorktreeByDefault: binding(for: \.createWorktreeByDefault),
                pullRequestsEnabled: binding(for: \.pullRequestsEnabled),
                automaticallyLinkPullRequests: binding(for: \.automaticallyLinkPullRequests)
            )
        case .handoff:
            HandoffSettingsTabView(
                contextManagementEnabled: binding(for: \.contextManagementEnabled),
                sessionHandoffWindowPercentage: binding(for: \.sessionHandoffWindowPercentage),
                handoffSteeringEnabled: binding(for: \.handoffSteeringEnabled),
                handoffSteeringCountdownSeconds: binding(for: \.handoffSteeringCountdownSeconds),
                handoffPromptSendCountdownSeconds: binding(for: \.handoffPromptSendCountdownSeconds),
                handoffContextCustomizationEnabled: binding(for: \.handoffContextCustomizationEnabled),
                sessionHandoffPrompt: binding(for: \.sessionHandoffPrompt)
            )
        case .menuBar:
            MenuBarSettingsTabView(
                viewModel: viewModel,
                showsMenuBarIcon: binding(for: \.showsMenuBarIcon)
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
                autoTrustProjects: binding(for: \.autoTrustProjects),
                reopenLastThreadAndConversationOnLaunch: binding(for: \.reopenLastThreadAndConversationOnLaunch),
                turnAwakeEnabled: binding(for: \.turnAwakeEnabled),
                turnAwakePreventDisplaySleep: binding(for: \.turnAwakePreventDisplaySleep),
                voiceInputShortcut: binding(for: \.voiceInputShortcut)
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
        case .handoff:
            return "Handoff"
        case .menuBar:
            return "Menu bar"
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

    var icon: ActionIcon {
        switch self {
        case .agents:
            return .system("brain")
        case .interface:
            return .system("paintbrush")
        case .appShots:
            return .system("camera.viewfinder")
        case .git:
            return .octicon(.gitBranch16)
        case .handoff:
            return .system("hand.palm.facing")
        case .menuBar:
            return .system("menubar.rectangle")
        case .notifications:
            return .system("bell")
        case .terminal:
            return .system("terminal")
        case .threads:
            return .system("bubble.left.and.bubble.right")
        case .appUpdates:
            return .system("arrow.down.circle")
        }
    }

    var description: String {
        switch self {
        case .agents:
            return "Manage agent installs and CLI settings."
        case .interface:
            return "Adjust theme and typography for the app shell."
        case .appShots:
            return "Configure app-shot capture, shortcuts, and local context permissions."
        case .git:
            return "Configure Git defaults, pull requests, and GitHub authentication."
        case .handoff:
            return "Configure Alveary's Amp-inspired take on compaction: automatic session handoff, steering, and context customization."
        case .menuBar:
            return "Show Alveary in the system menu bar, and choose whether it opens at login."
        case .notifications:
            return "Configure notification delivery and sounds."
        case .terminal:
            return "Configure terminal pane behavior for shells and project actions."
        case .threads:
            return "Manage thread defaults, project trust, and startup behavior."
        case .appUpdates:
            return "Check GitHub Releases for newer Alveary versions."
        }
    }
}
