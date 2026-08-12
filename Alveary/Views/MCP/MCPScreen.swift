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

                    let activeTarget = viewModel.activePaneTarget

                    if !viewModel.filteredServers.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Added")
                                .font(.title3.weight(.semibold))

                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                                ForEach(viewModel.filteredServers) { server in
                                    MCPServerRow(
                                        server: server,
                                        isSelected: activeTarget == .edit(server.name),
                                        onEdit: {
                                            viewModel.requestEdit(server)
                                        },
                                        onRemove: {
                                            removalConfirmation = makeServerRemovalConfirmation(for: server) {
                                                Task { await remove(server) }
                                            }
                                        },
                                        editFocus: $focusedPaneTriggerID,
                                        editFocusID: MCPPaneTarget.edit(server.name).defaultFocusRestorationID
                                    )
                                    .equatable()
                                }
                            }
                            .adaptiveCardGridReflow(columnCount: gridColumnCount)
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
                                        isSelected: activeTarget == .addRecommended(server.id),
                                        onAdd: {
                                            viewModel.requestAddRecommended(server)
                                        },
                                        addFocus: $focusedPaneTriggerID,
                                        addFocusID: MCPPaneTarget.addRecommended(server.id).defaultFocusRestorationID
                                    )
                                    .equatable()
                                }
                            }
                            .adaptiveCardGridReflow(columnCount: gridColumnCount)
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
            .adaptiveCardGridColumnCount($gridColumnCount)
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
        AdaptiveCardGridLayout.columns(count: gridColumnCount)
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
