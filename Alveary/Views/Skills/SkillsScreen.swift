import AppKit
import SwiftUI

struct SkillsScreen: View {
    let viewModel: SkillsViewModel

    @State private var hasLoaded = false
    @State private var screenError: String?
    @State private var uninstallConfirmation: DestructiveConfirmationRequest?
    @State private var gridColumnCount = 2
    @State private var scrollPosition = ScrollPosition()
    @FocusState private var focusedPaneTriggerID: String?

    var body: some View {
        VStack(spacing: 0) {
            SkillsScreenHeader(
                searchQuery: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchQuery = $0 }
                ),
                isRefreshing: viewModel.isRefreshingCatalog,
                onRefresh: {
                    Task {
                        await viewModel.refreshCatalog()
                    }
                },
                onCreate: { openNewSkill() },
                createFocus: $focusedPaneTriggerID
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

                    if viewModel.installed.isEmpty && !viewModel.catalog.isEmpty && !viewModel.hasActiveSearch {
                        NoSkillsInstalledLabel()
                    }

                    let filteredInstalled = viewModel.filteredInstalled
                    let filteredRecommended = viewModel.filteredRecommended
                    let selectedSkillID = activeDetailSkillID

                    if viewModel.hasActiveSearch {
                        // Read inside the branch: it is the only consumer, and the
                        // combined list is the one shaping step the view model defers.
                        let combinedSearchResults = viewModel.searchDisplayResults
                        if combinedSearchResults.isEmpty {
                            if viewModel.isSearchingSkillsSh {
                                SearchingSkillsLabel()
                            } else if hasLoaded {
                                CenteredSkillsStatusLabel("No search results")
                            }
                        } else {
                            SkillsSection(
                                title: "Results",
                                skills: combinedSearchResults,
                                columns: gridColumns,
                                activeDetailSkillID: selectedSkillID,
                                focusedPaneTrigger: $focusedPaneTriggerID,
                                onOpen: { skill in
                                    openDetails(skill)
                                },
                                onPrimaryAction: { skill in
                                    if skill.isInstalled {
                                        uninstallConfirmation = makeSkillUninstallConfirmation(for: skill) {
                                            Task { await uninstall(skill) }
                                        }
                                    } else {
                                        Task {
                                            await install(skill)
                                        }
                                    }
                                }
                            )
                            if viewModel.isSearchingSkillsSh {
                                SearchingSkillsLabel()
                            }
                        }
                    } else if filteredInstalled.isEmpty && filteredRecommended.isEmpty && viewModel.searchResults.isEmpty && hasLoaded {
                        EmptyStateView(
                            icon: "puzzlepiece.extension",
                            heading: "No skills available",
                            subtext: "Install or create a skill once catalog data is available.",
                            actions: [
                                .init(
                                    title: "New Skill",
                                    systemImage: "plus",
                                    style: .primary,
                                    focusID: "skills-new-empty"
                                ) {
                                    openNewSkill(focusRestorationID: "skills-new-empty")
                                }
                            ],
                            actionFocus: $focusedPaneTriggerID
                        )
                    } else {
                        if !filteredInstalled.isEmpty {
                            SkillsSection(
                                title: "Installed",
                                skills: filteredInstalled,
                                columns: gridColumns,
                                activeDetailSkillID: selectedSkillID,
                                focusedPaneTrigger: $focusedPaneTriggerID,
                                onOpen: { skill in
                                    openDetails(skill)
                                },
                                onPrimaryAction: { skill in
                                    if skill.isInstalled {
                                        uninstallConfirmation = makeSkillUninstallConfirmation(for: skill) {
                                            Task { await uninstall(skill) }
                                        }
                                    } else {
                                        Task {
                                            await install(skill)
                                        }
                                    }
                                }
                            )
                        }

                        if !filteredRecommended.isEmpty {
                            SkillsSection(
                                title: "Recommended",
                                skills: filteredRecommended,
                                columns: gridColumns,
                                activeDetailSkillID: selectedSkillID,
                                focusedPaneTrigger: $focusedPaneTriggerID,
                                onOpen: { skill in
                                    openDetails(skill)
                                },
                                onPrimaryAction: { skill in
                                    if skill.isInstalled {
                                        uninstallConfirmation = makeSkillUninstallConfirmation(for: skill) {
                                            Task { await uninstall(skill) }
                                        }
                                    } else {
                                        Task {
                                            await install(skill)
                                        }
                                    }
                                }
                            )
                        }

                        if !viewModel.searchResults.isEmpty {
                            SkillsSection(
                                title: "skills.sh",
                                skills: viewModel.searchResults,
                                columns: gridColumns,
                                activeDetailSkillID: selectedSkillID,
                                focusedPaneTrigger: $focusedPaneTriggerID,
                                onOpen: { skill in
                                    openDetails(skill)
                                },
                                onPrimaryAction: { skill in
                                    if skill.isInstalled {
                                        uninstallConfirmation = makeSkillUninstallConfirmation(for: skill) {
                                            Task { await uninstall(skill) }
                                        }
                                    } else {
                                        Task {
                                            await install(skill)
                                        }
                                    }
                                }
                            )
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
                fallbackID: SkillsPaneTarget.newSkill.defaultFocusRestorationID
            )
        }
        .destructiveConfirmation($uninstallConfirmation)
    }
}

private struct NoSkillsInstalledLabel: View {
    var body: some View {
        CenteredSkillsStatusLabel("No skills installed")
    }
}

private struct CenteredSkillsStatusLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
            .padding(.vertical, 16)
    }
}

private struct SearchingSkillsLabel: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
            .padding(.vertical, 16)
    }
}

private extension SkillsScreen {
    var visiblePaneTriggerFocusIDs: Set<String> {
        var ids = Set([SkillsPaneTarget.newSkill.defaultFocusRestorationID])
        ids.formUnion(viewModel.searchDisplayResults.map {
            SkillsPaneTarget.details($0.id).defaultFocusRestorationID
        })
        if !viewModel.hasActiveSearch,
           viewModel.filteredInstalled.isEmpty,
           viewModel.filteredRecommended.isEmpty,
           viewModel.searchResults.isEmpty,
           hasLoaded {
            ids.insert("skills-new-empty")
        }
        return ids
    }

    /// The skill whose details pane is open, so its card can render selected. Resolved
    /// once per body pass and handed down, rather than each card asking the view model.
    var activeDetailSkillID: String? {
        guard case .details(let skillID) = viewModel.activePaneTarget else {
            return nil
        }
        return skillID
    }

    var gridColumns: [GridItem] {
        AdaptiveCardGridLayout.columns(count: gridColumnCount)
    }

    func openNewSkill(focusRestorationID: String? = nil) {
        viewModel.requestNewSkill(focusRestorationID: focusRestorationID)
    }

    func openDetails(_ skill: Skill) {
        viewModel.requestDetails(for: skill)
    }

    func install(_ skill: Skill) async {
        do {
            try await viewModel.install(skill)
        } catch {
            screenError = error.localizedDescription
        }
    }

    func uninstall(_ skill: Skill) async {
        do {
            try await viewModel.uninstall(skill)
        } catch {
            screenError = error.localizedDescription
        }
    }
}

func makeSkillUninstallConfirmation(
    for skill: Skill,
    confirm: @escaping () -> Void
) -> DestructiveConfirmationRequest {
    let message: String
    if skill.syncedAgentIDs.isEmpty {
        message = "This removes \(skill.name) from your local skills directory."
    } else {
        message = "This removes \(skill.name) from your local skills directory and unsyncs it from \(skill.syncedAgentIDs.joined(separator: ", "))."
    }

    return DestructiveConfirmationRequest(
        title: "Uninstall skill?",
        message: message,
        confirmTitle: "Uninstall",
        confirm: confirm
    )
}

enum UIApplicationShim {
    static func open(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}
