import SwiftUI

struct MCPScreen: View {
    let viewModel: MCPViewModel

    @State private var hasLoaded = false
    @State private var screenError: String?
    @State private var formDraft: MCPServerDraft?
    @State private var removalConfirmation: DestructiveConfirmationRequest?

    private let columns = [
        GridItem(.flexible(minimum: 240), spacing: 16),
        GridItem(.flexible(minimum: 240), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MCPScreenHeader(
                    searchQuery: Binding(
                        get: { viewModel.searchQuery },
                        set: { viewModel.searchQuery = $0 }
                    ),
                    onRefresh: {
                        Task { await viewModel.refreshProviders() }
                    },
                    onAddServer: {
                        formDraft = MCPServerDraft(availableAgents: viewModel.availableAgents)
                    }
                )

                if let screenError {
                    InlineBanner(
                        message: screenError,
                        severity: .error,
                        autoDismissAfter: nil,
                        onDismiss: { self.screenError = nil }
                    )
                }

                if viewModel.servers.isEmpty && !viewModel.recommended.isEmpty {
                    NoMCPServersAddedLabel()
                }

                if !viewModel.filteredServers.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Added")
                            .font(.title3.weight(.semibold))

                        ForEach(viewModel.filteredServers) { server in
                            MCPServerRow(
                                server: server,
                                onEdit: {
                                    formDraft = MCPServerDraft(server: server, availableAgents: viewModel.availableAgents)
                                },
                                onRemove: {
                                    removalConfirmation = makeServerRemovalConfirmation(for: server) {
                                        Task { await remove(server) }
                                    }
                                }
                            )
                        }
                    }
                }

                if !viewModel.filteredRecommended.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recommended")
                            .font(.title3.weight(.semibold))

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(viewModel.filteredRecommended) { server in
                                RecommendedMCPCard(server: server) {
                                    formDraft = MCPServerDraft(recommended: server, availableAgents: viewModel.availableAgents)
                                }
                            }
                        }
                    }
                }

                if viewModel.servers.isEmpty && viewModel.recommended.isEmpty && hasLoaded {
                    EmptyStateView(
                        icon: "server.rack",
                        heading: "No MCP servers available",
                        subtext: "Recommended servers are unavailable right now, but you can still add a custom one.",
                        actions: [
                            .init(title: "Add Server", systemImage: "plus", style: .primary) {
                                formDraft = MCPServerDraft(availableAgents: viewModel.availableAgents)
                            }
                        ]
                    )
                }
            }
            .padding(28)
        }
        .task {
            guard !hasLoaded else {
                return
            }

            hasLoaded = true
            await viewModel.load()
        }
        .sheet(item: $formDraft) { draft in
            MCPServerFormSheet(draft: draft) { updatedDraft in
                Task {
                    await save(updatedDraft)
                }
            }
        }
        .destructiveConfirmation($removalConfirmation)
    }
}

private extension MCPScreen {
    func save(_ draft: MCPServerDraft) async {
        do {
            try await viewModel.addServer(draft.makeServer(), for: Array(draft.selectedAgents))
            formDraft = nil
        } catch {
            screenError = error.localizedDescription
        }
    }

    func remove(_ server: MCPServer) async {
        do {
            try await viewModel.removeServer(server)
        } catch {
            screenError = error.localizedDescription
        }
    }
}

private struct NoMCPServersAddedLabel: View {
    var body: some View {
        Text("No MCP servers added")
            .font(.headline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }
}

private func makeServerRemovalConfirmation(
    for server: MCPServer,
    confirm: @escaping () -> Void
) -> DestructiveConfirmationRequest {
    let message: String
    if server.providers.isEmpty {
        message = "This deletes the saved configuration for \(server.name)."
    } else {
        message = "This deletes the saved configuration for \(server.name) and removes it from \(server.providers.joined(separator: ", "))."
    }

    return DestructiveConfirmationRequest(
        title: "Remove server?",
        message: message,
        confirmTitle: "Remove",
        confirm: confirm
    )
}

private struct MCPServerRow: View {
    let server: MCPServer
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: server.transport == .http ? "globe" : "terminal")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 6) {
                Text(server.name)
                    .font(.headline)

                Text(server.transport == .http ? (server.url ?? "HTTP server") : (server.command ?? "stdio server"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !server.providers.isEmpty {
                    Text("Agents: \(server.providers.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Edit", action: onEdit)
                .secondaryActionButtonStyle()
            Button("Remove", role: .destructive, action: onRemove)
                .destructiveActionButtonStyle()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct RecommendedMCPCard: View {
    let server: RecommendedMCPServer
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(server.template.name)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                Text(server.template.transport.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
            }

            Text(server.description)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer()

            Button("Add", action: onAdd)
                .primaryActionButtonStyle()
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct MCPServerDraft: Identifiable {
    let id = UUID()
    var name: String
    var transport: MCPServer.Transport
    var command: String
    var argsText: String
    var url: String
    var headersText: String
    var envText: String
    var selectedAgents: Set<String>
    let availableAgents: [MCPAgentAvailability]

    init(availableAgents: [MCPAgentAvailability]) {
        self.name = ""
        self.transport = .stdio
        self.command = ""
        self.argsText = ""
        self.url = ""
        self.headersText = ""
        self.envText = ""
        self.selectedAgents = Set(availableAgents.map(\.agentId))
        self.availableAgents = availableAgents
    }

    init(server: MCPServer, availableAgents: [MCPAgentAvailability]) {
        self.name = server.name
        self.transport = server.transport
        self.command = server.command ?? ""
        self.argsText = server.args?.joined(separator: " ") ?? ""
        self.url = server.url ?? ""
        self.headersText = Self.serialize(dictionary: server.headers)
        self.envText = Self.serialize(dictionary: server.env)
        self.selectedAgents = Set(server.providers)
        self.availableAgents = availableAgents
    }

    init(recommended: RecommendedMCPServer, availableAgents: [MCPAgentAvailability]) {
        self.init(server: recommended.template, availableAgents: availableAgents)
        if !recommended.headerPrompts.isEmpty {
            self.headersText = recommended.headerPrompts.map { "\($0)=" }.joined(separator: "\n")
        }
        self.selectedAgents = Set(availableAgents.filter {
            $0.supportedTransports.contains(recommended.template.transport)
        }.map(\.agentId))
    }

    func makeServer() -> MCPServer {
        let parsedArgs = argsText.split(whereSeparator: \.isWhitespace).map(String.init)

        return MCPServer(
            name: name,
            transport: transport,
            command: command.isEmpty ? nil : command,
            args: parsedArgs.isEmpty ? nil : parsedArgs,
            url: url.isEmpty ? nil : url,
            headers: Self.parse(lines: headersText),
            env: Self.parse(lines: envText),
            providers: Array(selectedAgents).sorted()
        )
    }

    private static func parse(lines: String) -> [String: String]? {
        let pairs = lines
            .split(separator: "\n")
            .compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard let key = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !key.isEmpty else {
                    return nil
                }
                let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                return (key, value)
            }

        guard !pairs.isEmpty else {
            return nil
        }

        return Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
    }

    private static func serialize(dictionary: [String: String]?) -> String {
        dictionary?
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n") ?? ""
    }
}

private struct MCPServerFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: MCPServerDraft
    let onSave: (MCPServerDraft) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Text(draft.name.isEmpty ? "Add MCP Server" : draft.name)
                        .font(.title2.weight(.semibold))

                    Spacer()

                    ModalCloseButton("Close MCP server form") {
                        dismiss()
                    }
                }

                AppTextField("Server name", text: $draft.name)

                Picker("Transport", selection: $draft.transport) {
                    ForEach(MCPServer.Transport.allCases, id: \.self) { transport in
                        Text(transport.rawValue.uppercased()).tag(transport)
                    }
                }

                if draft.transport == .http {
                    AppTextField("URL", text: $draft.url)
                } else {
                    AppTextField("Command", text: $draft.command)
                    AppTextField("Args", text: $draft.argsText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Headers (KEY=value)")
                        .font(.headline)
                    AppTextEditor(text: $draft.headersText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Environment (KEY=value)")
                        .font(.headline)
                    AppTextEditor(text: $draft.envText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sync to agents")
                        .font(.headline)

                    ForEach(draft.availableAgents) { agent in
                        let isSupported = agent.supportedTransports.contains(draft.transport)
                        Toggle(isOn: Binding(
                            get: { draft.selectedAgents.contains(agent.agentId) },
                            set: { isOn in
                                if isOn {
                                    draft.selectedAgents.insert(agent.agentId)
                                } else {
                                    draft.selectedAgents.remove(agent.agentId)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name)
                                if !isSupported {
                                    Text("Does not support \(draft.transport.rawValue.uppercased()) transport")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!isSupported)
                    }
                }

                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .secondaryActionButtonStyle()

                    Spacer()

                    Button("Save") {
                        onSave(draft)
                    }
                    .primaryActionButtonStyle()
                    .disabled(
                        draft.name.isEmpty
                            || draft.selectedAgents.isEmpty
                            || (draft.transport == .http ? draft.url.isEmpty : draft.command.isEmpty)
                    )
                }
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 560)
    }
}
