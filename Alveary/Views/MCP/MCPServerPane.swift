import SwiftUI

struct MCPServerPane: View {
    let viewModel: MCPViewModel

    @FocusState private var isNameFocused: Bool

    private var draft: Binding<MCPServerDraft> {
        Binding(
            get: {
                guard let target = viewModel.activePaneTarget,
                      let session = viewModel.paneSessions[target] else {
                    return MCPServerDraft(availableAgents: viewModel.availableAgents)
                }
                return session.draft
            },
            set: { viewModel.updateActiveDraft($0) }
        )
    }

    private var session: MCPPaneSession? {
        viewModel.activePaneTarget.flatMap { viewModel.paneSessions[$0] }
    }

    private var title: String {
        switch viewModel.activePaneTarget {
        case .edit:
            session?.draft.name.isEmpty == false ? session?.draft.name ?? "Edit Server" : "Edit Server"
        case .addCustom, .addRecommended:
            "Add Server"
        case nil:
            "Add Server"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ContextualPaneHeader(
                title,
                closeAccessibilityLabel: "Close MCP server pane",
                onClose: viewModel.dismissActivePane
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let errorMessage = session?.errorMessage {
                        InlineBanner(
                            message: errorMessage,
                            severity: .error,
                            autoDismissAfter: nil,
                            onDismiss: viewModel.clearActivePaneError
                        )
                    }

                    AppTextField("Server name", text: draft.name)
                        .focused($isNameFocused)

                    Picker("Transport", selection: draft.transport) {
                        ForEach(MCPServer.Transport.allCases, id: \.self) { transport in
                            Text(transport.rawValue.uppercased()).tag(transport)
                        }
                    }

                    if draft.wrappedValue.transport == .http {
                        AppTextField("URL", text: draft.url)
                    } else {
                        AppTextField("Command", text: draft.command)
                        AppTextField("Args", text: draft.argsText)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Headers (KEY=value)")
                            .font(.headline)
                        AppTextEditor(text: draft.headersText, minHeight: 120)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment (KEY=value)")
                            .font(.headline)
                        AppTextEditor(text: draft.envText, minHeight: 120)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sync to agents")
                            .font(.headline)

                        ForEach(viewModel.availableAgents) { agent in
                            let isSupported = agent.supportedTransports.contains(draft.wrappedValue.transport)
                            Toggle(isOn: selectedAgentBinding(agent.agentId)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                    if !isSupported {
                                        Text("Does not support \(draft.wrappedValue.transport.rawValue.uppercased()) transport")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(!isSupported)
                        }
                    }
                }
                .padding(20)
            }

            footer
        }
        .onAppear {
            isNameFocused = true
        }
        .onExitCommand(perform: viewModel.dismissActivePane)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Button("Cancel", action: viewModel.dismissActivePane)
                    .secondaryActionButtonStyle()
                Spacer()
                saveButton
            }

            VStack(alignment: .leading, spacing: 10) {
                saveButton
                Button("Cancel", action: viewModel.dismissActivePane)
                    .secondaryActionButtonStyle()
            }
        }
        .padding(16)
        .background(.bar)
        .overlay(alignment: .top) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }

    private var saveButton: some View {
        Button("Save") {
            Task { await viewModel.submitActivePane() }
        }
        .primaryActionButtonStyle()
        .disabled(!isValid || session?.isSubmitting == true)
    }

    private var isValid: Bool {
        let draft = draft.wrappedValue
        return !draft.name.isEmpty
            && !draft.selectedAgents.isEmpty
            && (draft.transport == .http ? !draft.url.isEmpty : !draft.command.isEmpty)
    }

    private func selectedAgentBinding(_ agentID: String) -> Binding<Bool> {
        Binding(
            get: { draft.wrappedValue.selectedAgents.contains(agentID) },
            set: { isSelected in
                var updated = draft.wrappedValue
                if isSelected {
                    updated.selectedAgents.insert(agentID)
                } else {
                    updated.selectedAgents.remove(agentID)
                }
                draft.wrappedValue = updated
            }
        )
    }
}
