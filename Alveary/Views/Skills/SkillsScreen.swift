import AppKit
import SwiftUI
import Textual

struct SkillsScreen: View {
    let viewModel: SkillsViewModel

    @State private var hasLoaded = false
    @State private var screenError: String?
    @State private var isCreateSheetPresented = false
    @State private var selectedSkill: Skill?
    @State private var uninstallConfirmation: DestructiveConfirmationRequest?

    private let columns = [
        GridItem(.flexible(minimum: 240), spacing: 16),
        GridItem(.flexible(minimum: 240), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
                    onCreate: {
                        isCreateSheetPresented = true
                    }
                )

                if let screenError {
                    InlineBanner(message: screenError, severity: .error, autoDismissAfter: nil) {
                        self.screenError = nil
                    }
                }

                if viewModel.installed.isEmpty && !viewModel.catalog.isEmpty && !viewModel.hasActiveSearch {
                    NoSkillsInstalledLabel()
                }

                let filteredInstalled = viewModel.filteredInstalled
                let filteredRecommended = viewModel.filteredRecommended
                let combinedSearchResults = viewModel.searchDisplayResults

                if viewModel.hasActiveSearch {
                    if combinedSearchResults.isEmpty && hasLoaded {
                        if viewModel.isSearchingSkillsSh {
                            SearchingSkillsLabel()
                        } else {
                            CenteredSkillsStatusLabel("No search results")
                        }
                    }
                    if !combinedSearchResults.isEmpty {
                        SkillsSection(
                            title: "Results",
                            skills: combinedSearchResults,
                            columns: columns,
                            onOpen: { skill in
                                selectedSkill = skill
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
                    if viewModel.isSearchingSkillsSh {
                        SearchingSkillsLabel()
                    }
                } else if filteredInstalled.isEmpty && filteredRecommended.isEmpty && viewModel.searchResults.isEmpty && hasLoaded {
                    EmptyStateView(
                        icon: "puzzlepiece.extension",
                        heading: "No skills available",
                        subtext: "Install or create a skill once catalog data is available.",
                        actions: [
                            .init(title: "New Skill", systemImage: "plus", style: .primary) {
                                isCreateSheetPresented = true
                            }
                        ]
                    )
                } else {
                    if !filteredInstalled.isEmpty {
                        SkillsSection(
                            title: "Installed",
                            skills: filteredInstalled,
                            columns: columns,
                            onOpen: { skill in
                                selectedSkill = skill
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
                            columns: columns,
                            onOpen: { skill in
                                selectedSkill = skill
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
                            columns: columns,
                            onOpen: { skill in
                                selectedSkill = skill
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
            .padding(28)
        }
        .task {
            guard !hasLoaded else {
                return
            }

            hasLoaded = true
            await viewModel.load()
        }
        .sheet(item: $selectedSkill) { skill in
            SkillDetailSheet(
                viewModel: viewModel,
                skill: skill,
                onInstall: { skill in
                    await install(skill)
                },
                onUninstall: { skill in
                    await uninstall(skill)
                },
                onError: { error in
                    screenError = error.localizedDescription
                }
            )
        }
        .sheet(isPresented: $isCreateSheetPresented) {
            CreateSkillSheet { name, description, instructions in
                Task {
                    do {
                        try await viewModel.create(name: name, description: description, instructions: instructions)
                        isCreateSheetPresented = false
                    } catch {
                        screenError = error.localizedDescription
                    }
                }
            }
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

private struct SkillDetailSheet: View {
    let viewModel: SkillsViewModel
    let skill: Skill
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void
    let onError: (Error) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var markdown = ""
    @State private var markdownBaseURL: URL?
    @State private var resolvedGitHubURL: URL?
    @State private var isLoading = true
    @State private var uninstallConfirmation: DestructiveConfirmationRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(skill.name)
                        .font(.title2.weight(.semibold))

                    Text(skill.description.isEmpty ? "No description available." : skill.description)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ModalCloseButton("Close skill details") {
                    dismiss()
                }
            }

            SkillMarkdownContent(markdown: markdown, baseURL: markdownBaseURL, isLoading: isLoading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if let url = resolvedGitHubURL ?? skill.githubURL {
                    Button("View on GitHub") {
                        UIApplicationShim.open(url: url)
                    }
                    .secondaryActionButtonStyle()
                }

                Spacer()

                if skill.isInstalled {
                    Button("Uninstall", role: .destructive) {
                        uninstallConfirmation = makeSkillUninstallConfirmation(for: skill) {
                            Task {
                                await onUninstall(skill)
                                dismiss()
                            }
                        }
                    }
                    .destructiveActionButtonStyle()
                } else {
                    Button("Install") {
                        Task {
                            await onInstall(skill)
                            dismiss()
                        }
                    }
                    .primaryActionButtonStyle()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 520)
        .destructiveConfirmation($uninstallConfirmation)
        .task {
            do {
                let document = try await viewModel.fetchSkillMarkdown(for: skill)
                markdown = document.markdown
                markdownBaseURL = document.baseURL
                resolvedGitHubURL = document.browserURL ?? skill.githubURL
            } catch {
                onError(error)
                markdown = skill.description
                markdownBaseURL = nil
                resolvedGitHubURL = skill.githubURL
            }
            isLoading = false
        }
    }
}

private struct SkillMarkdownContent: View {
    let markdown: String
    let baseURL: URL?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            Group {
                if isLoading {
                    ProgressView("Loading skill details...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        // Apply only `inlineStyle` so skill readmes get the accent-colored
                        // inline-code chip treatment. Intentionally skip `codeBlockStyle` —
                        // skill markdown keeps Textual's default code-block rendering, which
                        // reads fine against the SkillsScreen background and differs from
                        // the chat transcript's `AppMarkdownCodeBlockStyle` chrome.
                        StructuredText(markdown: markdown, baseURL: baseURL)
                            .textual.inlineStyle(appMarkdownInlineStyle)
                            .textual.textSelection(.enabled)
                            .environment(\.openURL, OpenURLAction { url in
                                UIApplicationShim.open(url: resolvedURL(for: url))
                                return .handled
                            })
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
        }
    }

    private func resolvedURL(for url: URL) -> URL {
        guard url.scheme == nil, let baseURL else {
            return url
        }
        return URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL ?? url
    }
}

private struct CreateSkillSheet: View {
    let onCreate: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var instructions = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text("Create Skill")
                    .font(.title2.weight(.semibold))

                Spacer()

                ModalCloseButton("Close create skill") {
                    dismiss()
                }
            }

            AppTextField("Name (kebab-case)", text: $name)
            AppTextField("Description", text: $description)

            AppTextEditor(text: $instructions, minHeight: 220)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .secondaryActionButtonStyle()

                Spacer()

                Button("Create") {
                    onCreate(name, description, instructions)
                }
                .primaryActionButtonStyle()
                .disabled(name.isEmpty || description.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
    }
}

private func makeSkillUninstallConfirmation(
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

private enum UIApplicationShim {
    static func open(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}
