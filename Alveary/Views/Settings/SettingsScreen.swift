import SwiftUI

struct SettingsScreen: View {
    let viewModel: SettingsViewModel
    let onClose: (() -> Void)?

    @State private var selectedTab: SettingsTab = .general

    init(
        viewModel: SettingsViewModel,
        onClose: (() -> Void)? = nil,
        initialTabRawValue: String = SettingsTab.general.rawValue
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        _selectedTab = State(initialValue: SettingsTab(rawValue: initialTabRawValue) ?? .general)
    }

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                .appSelectionRowBackground(isSelected: selectedTab == tab)
            }
            .frame(width: 180)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsScreenHeader(
                        title: selectedTab.title,
                        description: description(for: selectedTab),
                        onClose: onClose
                    )

                    switch selectedTab {
                    case .general:
                        GeneralSettingsTabView(
                            viewModel: viewModel,
                            defaultProvider: binding(for: \.defaultProvider),
                            permissionMode: binding(for: \.permissionMode),
                            effort: binding(for: \.effort),
                            autoGenerateNames: binding(for: \.autoGenerateNames),
                            createWorktreeByDefault: binding(for: \.createWorktreeByDefault),
                            autoTrustWorktrees: binding(for: \.autoTrustWorktrees),
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
                    case .repository:
                        RepositorySettingsTabView(
                            branchPrefix: binding(for: \.branchPrefix),
                            pushOnCreate: binding(for: \.pushOnCreate)
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
                .padding(28)
            }
        }
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case agents
        case repository
        case interface

        var id: String { rawValue }

        var title: String {
            rawValue.capitalized
        }

        var icon: String {
            switch self {
            case .general:
                return "slider.horizontal.3"
            case .agents:
                return "sparkles.rectangle.stack"
            case .repository:
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
            return "Manage thread defaults and notification settings."
        case .agents:
            return "Manage agent installs and override CLI settings for each supported provider."
        case .repository:
            return "Configure branch creation defaults for new worktrees."
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
