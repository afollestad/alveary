import AppKit
import SwiftUI

struct SkillsScreen: View {
    let viewModel: SkillsViewModel

    @State private var hasLoaded = false
    @State private var screenError: String?
    @State private var uninstallConfirmation: DestructiveConfirmationRequest?
    @State private var lastPaneTriggerID = "skills-new"
    @State private var gridColumnCount = 2
    @FocusState private var focusedPaneTriggerID: String?

    var body: some View {
        VStack(spacing: 0) {
            SkillsScreenHeader(
                searchQuery: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchQuery = $0 }
                ),
                onRefresh: {
                    Task {
                        await viewModel.refreshCatalog()
                    }
                },
                onCreate: openNewSkill,
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
                    let combinedSearchResults = viewModel.searchDisplayResults

                    if viewModel.hasActiveSearch {
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
                                .init(title: "New Skill", systemImage: "plus", style: .primary) {
                                    openNewSkill()
                                }
                            ]
                        )
                    } else {
                        if !filteredInstalled.isEmpty {
                            SkillsSection(
                                title: "Installed",
                                skills: filteredInstalled,
                                columns: gridColumns,
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
    var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 240), spacing: 16),
            count: gridColumnCount
        )
    }

    func openNewSkill() {
        lastPaneTriggerID = "skills-new"
        viewModel.requestNewSkill()
    }

    func openDetails(_ skill: Skill) {
        lastPaneTriggerID = "skills-details-\(skill.id)"
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
