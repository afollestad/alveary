import SwiftUI

struct SettingsScreen: View {
    let viewModel: SettingsViewModel
    let onClose: (() -> Void)?

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .frame(width: 180)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedTab.title)
                                .font(.largeTitle.weight(.semibold))

                            Text(description(for: selectedTab))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let onClose {
                            Button(action: onClose) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    switch selectedTab {
                    case .general:
                        generalTab
                    case .agents:
                        agentsTab
                    case .repository:
                        repositoryTab
                    case .interface:
                        interfaceTab
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
    var generalTab: some View {
        Form {
            Section("Thread Defaults") {
                Picker("Default provider", selection: binding(for: \.defaultProvider)) {
                    ForEach(viewModel.availableProviderIDs, id: \.self) { providerID in
                        Text(providerID.capitalized).tag(providerID)
                    }
                }

                Picker("Permission mode", selection: binding(for: \.permissionMode)) {
                    ForEach(viewModel.permissionModeOptions(for: viewModel.defaultProvider), id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }

                Picker("Effort", selection: binding(for: \.effort)) {
                    ForEach(viewModel.effortOptions(for: viewModel.defaultProvider), id: \.self) { effort in
                        Text(effort.capitalized).tag(effort)
                    }
                }

                Toggle("Auto-generate thread names", isOn: binding(for: \.autoGenerateNames))
                Toggle("Create worktree by default", isOn: binding(for: \.createWorktreeByDefault))
                Toggle("Auto-trust worktrees", isOn: binding(for: \.autoTrustWorktrees))
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: binding(for: \.notificationsEnabled))
                Toggle("Use macOS notifications", isOn: binding(for: \.osNotificationsEnabled))
                    .disabled(!viewModel.notificationsEnabled)
                Toggle("Play sounds", isOn: binding(for: \.soundEnabled))
                    .disabled(!viewModel.notificationsEnabled)

                Picker("Sound", selection: binding(for: \.soundName)) {
                    ForEach(viewModel.availableSoundNames, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .disabled(!viewModel.notificationsEnabled || !viewModel.soundEnabled)
            }
        }
        .formStyle(.grouped)
    }

    var agentsTab: some View {
        Form {
            ForEach(viewModel.availableProviderIDs, id: \.self) { providerID in
                Section(providerID.capitalized) {
                    TextField("CLI override", text: providerConfigBinding(for: providerID, keyPath: \.cli))
                    TextField("Resume flag", text: providerConfigBinding(for: providerID, keyPath: \.resumeFlag))
                    TextField("Default args", text: providerConfigBinding(for: providerID, keyPath: \.defaultArgs))
                    TextField("Auto-approve flag", text: providerConfigBinding(for: providerID, keyPath: \.autoApproveFlag))
                    TextField("Initial prompt flag", text: providerConfigBinding(for: providerID, keyPath: \.initialPromptFlag))
                    TextField("Extra args", text: providerConfigBinding(for: providerID, keyPath: \.extraArgs))
                }
            }
        }
        .formStyle(.grouped)
    }

    var repositoryTab: some View {
        Form {
            Section("Branching") {
                TextField("Branch prefix", text: binding(for: \.branchPrefix))
                Toggle("Push on create", isOn: binding(for: \.pushOnCreate))
            }
        }
        .formStyle(.grouped)
    }

    var interfaceTab: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: binding(for: \.theme)) {
                    ForEach(viewModel.themeOptions, id: \.self) { theme in
                        Text(theme.capitalized).tag(theme)
                    }
                }

                TextField("Code font family", text: binding(for: \.codeFontFamily))
                Stepper(value: binding(for: \.codeFontSize), in: 10...24) {
                    Text("Code font size: \(viewModel.codeFontSize)")
                }
                Stepper(value: binding(for: \.chatFontSize), in: 11...24) {
                    Text("Chat font size: \(viewModel.chatFontSize)")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func description(for tab: SettingsTab) -> String {
        switch tab {
        case .general:
            return "Manage thread defaults and notification settings."
        case .agents:
            return "Override CLI settings for each supported provider."
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
