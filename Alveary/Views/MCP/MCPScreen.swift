import SwiftUI

struct MCPScreen: View {
    let viewModel: MCPViewModel

    @State private var hasLoaded = false
    @State private var screenError: String?
    @State private var removalConfirmation: DestructiveConfirmationRequest?
    @State private var lastPaneTriggerID = "mcp-add"
    @State private var gridColumnCount = 2
    @FocusState private var focusedPaneTriggerID: String?

    var body: some View {
        VStack(spacing: 0) {
            MCPScreenHeader(
                searchQuery: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchQuery = $0 }
                ),
                onRefresh: {
                    Task { await viewModel.refreshProviders() }
                },
                onAddServer: openCustomServer,
                addFocus: $focusedPaneTriggerID
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
                                        lastPaneTriggerID = "mcp-edit-\(server.id)"
                                        viewModel.requestEdit(server)
                                    },
                                    onRemove: {
                                        removalConfirmation = makeServerRemovalConfirmation(for: server) {
                                            Task { await remove(server) }
                                        }
                                    },
                                    editFocus: $focusedPaneTriggerID,
                                    editFocusID: "mcp-edit-\(server.id)"
                                )
                            }
                        }
                    }

                    if !viewModel.filteredRecommended.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Recommended")
                                .font(.title3.weight(.semibold))

                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                                ForEach(viewModel.filteredRecommended) { server in
                                    RecommendedMCPCard(
                                        server: server,
                                        onAdd: {
                                            lastPaneTriggerID = "mcp-recommended-\(server.id)"
                                            viewModel.requestAddRecommended(server)
                                        },
                                        addFocus: $focusedPaneTriggerID,
                                        addFocusID: "mcp-recommended-\(server.id)"
                                    )
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
                                    openCustomServer()
                                }
                            ]
                        )
                    }
                }
                .padding(EdgeInsets(top: 28, leading: 20, bottom: 28, trailing: 28))
            }
            .id(viewModel.searchQuery)
            .onGeometryChange(for: Int.self) { proxy in
                proxy.size.width >= 544 ? 2 : 1
            } action: { newValue in
                gridColumnCount = newValue
            }
        }
        .task {
            guard !hasLoaded else {
                return
            }

            hasLoaded = true
            await viewModel.load()
        }
        .onChange(of: viewModel.paneDismissalGeneration) { _, _ in
            focusedPaneTriggerID = lastPaneTriggerID
        }
        .destructiveConfirmation($removalConfirmation)
    }
}

private extension MCPScreen {
    var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 240), spacing: 16),
            count: gridColumnCount
        )
    }

    func openCustomServer() {
        lastPaneTriggerID = "mcp-add"
        viewModel.requestAddCustom()
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
    let editFocus: FocusState<String?>.Binding
    let editFocusID: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: server.transport == .http ? "globe" : "terminal")
                .foregroundStyle(AppAccentIcon.foreground)

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
                .focused(editFocus, equals: editFocusID)
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
    let addFocus: FocusState<String?>.Binding
    let addFocusID: String

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
                .focused(addFocus, equals: addFocusID)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
