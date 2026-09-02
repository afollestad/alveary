import SwiftUI

/// Has no empty state, deliberately: the built-in section is always present, so the screen
/// never has nothing to show even with no servers added and no recommendations loaded.
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

                    let activeTarget = viewModel.activePaneTarget
                    let filteredBuiltInToolGroups = viewModel.filteredBuiltInToolGroups

                    if !filteredBuiltInToolGroups.isEmpty {
                        BuiltInMCPToolsSection(
                            groups: filteredBuiltInToolGroups,
                            columns: gridColumns,
                            selectedGroupID: selectedBuiltInToolGroupID(activeTarget),
                            focusedPaneTrigger: $focusedPaneTriggerID,
                            onOpen: { group in
                                viewModel.requestBuiltInToolGroupDetails(group)
                            }
                        )
                    }

                    if viewModel.servers.isEmpty && !viewModel.recommended.isEmpty {
                        NoMCPServersAddedLabel()
                    }

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
            // Remembers the offset across the screen's unmount, and applies the
            // `.scrollPosition(_:)` the reset below drives.
            .restoresScrollOffset(viewModel.listScrollOffset, position: $scrollPosition)
            // Resets to the top on a new query. Keying the scroll view by the query
            // instead would rebuild this whole subtree on every keystroke.
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
        ids.formUnion(viewModel.filteredBuiltInToolGroups.map {
            MCPPaneTarget.builtInToolGroup($0.id).defaultFocusRestorationID
        })
        return ids
    }

    /// The built-in group whose details pane is open, so its card can render selected.
    func selectedBuiltInToolGroupID(_ activeTarget: MCPPaneTarget?) -> String? {
        guard case .builtInToolGroup(let groupID) = activeTarget else {
            return nil
        }
        return groupID
    }

    var gridColumns: [GridItem] {
        AdaptiveCardGridLayout.columns(count: gridColumnCount)
    }

    func openCustomServer() {
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
