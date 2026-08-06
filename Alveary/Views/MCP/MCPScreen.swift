import SwiftUI

struct MCPScreen: View {
    let viewModel: MCPViewModel

    @State private var hasLoaded = false
    @State private var screenError: String?
    @State private var removalConfirmation: DestructiveConfirmationRequest?
    @State private var gridColumnCount = 2
    @State private var scrollPosition = ScrollPosition()
    @FocusState private var focusedPaneTriggerID: String?

    var body: some View {
        VStack(spacing: 0) {
            MCPScreenHeader(
                searchQuery: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchQuery = $0 }
                ),
                isRefreshing: viewModel.isRefreshingProviders,
                onRefresh: {
                    Task { await viewModel.refreshProviders() }
                },
                onAddServer: { openCustomServer() },
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
                                .equatable()
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
                                            viewModel.requestAddRecommended(server)
                                        },
                                        addFocus: $focusedPaneTriggerID,
                                        addFocusID: "mcp-recommended-\(server.id)"
                                    )
                                    .equatable()
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
                                .init(
                                    title: "Add Server",
                                    systemImage: "plus",
                                    style: .primary,
                                    focusID: "mcp-add-empty"
                                ) {
                                    openCustomServer(focusRestorationID: "mcp-add-empty")
                                }
                            ],
                            actionFocus: $focusedPaneTriggerID
                        )
                    }
                }
                .padding(
                    EdgeInsets(
                        top: 28,
                        leading: PaneHeaderLayout.leadingInset,
                        bottom: 28,
                        trailing: PaneHeaderLayout.trailingInset
                    )
                )
            }
            // Resets to the top on a new query. Keying the scroll view by the query
            // instead would rebuild this whole subtree on every keystroke.
            .scrollPosition($scrollPosition)
            .onChange(of: viewModel.searchQuery) { _, _ in
                scrollPosition.scrollTo(edge: .top)
            }
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
            focusedPaneTriggerID = ContextualPaneFocusRestoration.resolve(
                preferredID: viewModel.paneFocusRestorationID,
                visibleTriggerIDs: visiblePaneTriggerFocusIDs,
                fallbackID: MCPPaneTarget.addCustom.defaultFocusRestorationID
            )
        }
        .destructiveConfirmation($removalConfirmation)
    }
}

private extension MCPScreen {
    var visiblePaneTriggerFocusIDs: Set<String> {
        var ids = Set([MCPPaneTarget.addCustom.defaultFocusRestorationID])
        ids.formUnion(viewModel.filteredServers.map {
            MCPPaneTarget.edit($0.name).defaultFocusRestorationID
        })
        ids.formUnion(viewModel.filteredRecommended.map {
            MCPPaneTarget.addRecommended($0.id).defaultFocusRestorationID
        })
        if viewModel.servers.isEmpty, viewModel.recommended.isEmpty, hasLoaded {
            ids.insert("mcp-add-empty")
        }
        return ids
    }

    var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 240), spacing: 16),
            count: gridColumnCount
        )
    }

    func openCustomServer(focusRestorationID: String? = nil) {
        viewModel.requestAddCustom(focusRestorationID: focusRestorationID)
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

private struct MCPServerRow: View, Equatable {
    let server: MCPServer
    let onEdit: () -> Void
    let onRemove: () -> Void
    let editFocus: FocusState<String?>.Binding
    let editFocusID: String

    /// The actions and the focus binding are excluded: the actions close over the `server`
    /// compared here plus the screen's view-model reference and its `@State` confirmation
    /// box, and the binding reads the screen's `@FocusState` storage — none of which a
    /// captured copy can serve staler than a fresh one.
    nonisolated static func == (lhs: MCPServerRow, rhs: MCPServerRow) -> Bool {
        lhs.server == rhs.server && lhs.editFocusID == rhs.editFocusID
    }

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

            Button(action: onEdit) {
                ActionButtonLabel(title: "Edit", icon: .system("pencil"))
            }
            .secondaryActionButtonStyle()
            .focused(editFocus, equals: editFocusID)
            Button(role: .destructive, action: onRemove) {
                ActionButtonLabel(title: "Remove", icon: .system("trash"))
            }
            .destructiveActionButtonStyle()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct RecommendedMCPCard: View, Equatable {
    let server: RecommendedMCPServer
    let onAdd: () -> Void
    let addFocus: FocusState<String?>.Binding
    let addFocusID: String

    /// The action and the focus binding are excluded, for the same reasons as
    /// `MCPServerRow`.
    nonisolated static func == (lhs: RecommendedMCPCard, rhs: RecommendedMCPCard) -> Bool {
        lhs.server == rhs.server && lhs.addFocusID == rhs.addFocusID
    }

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

            Button(action: onAdd) {
                ActionButtonLabel(title: "Add", icon: .system("plus"))
            }
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
