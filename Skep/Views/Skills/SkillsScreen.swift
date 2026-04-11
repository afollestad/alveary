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
                header

                if let screenError {
                    InlineBanner(message: screenError, severity: .error, autoDismissAfter: nil) {
                        self.screenError = nil
                    }
                }

                if viewModel.installed.isEmpty && !viewModel.catalog.isEmpty {
                    introCard
                }

                let filteredInstalled = viewModel.filteredInstalled
                let filteredRecommended = viewModel.filteredCatalog.filter { !$0.isInstalled }

                if filteredInstalled.isEmpty && filteredRecommended.isEmpty && viewModel.searchResults.isEmpty && hasLoaded {
                    EmptyStateView(
                        icon: "puzzlepiece.extension",
                        heading: viewModel.hasActiveSearch ? "No matching skills" : "No skills available",
                        subtext: viewModel.hasActiveSearch
                            ? "Try a different search or create a new skill."
                            : "Install or create a skill once catalog data is available.",
                        actions: [
                            .init(title: "New Skill", systemImage: "plus", style: .primary) {
                                isCreateSheetPresented = true
                            }
                        ]
                    )
                } else {
                    if !filteredInstalled.isEmpty {
                        section(title: "Installed", skills: filteredInstalled)
                    }

                    if !filteredRecommended.isEmpty {
                        section(title: "Recommended", skills: filteredRecommended)
                    }

                    if !viewModel.searchResults.isEmpty {
                        section(title: "skills.sh", skills: viewModel.searchResults)
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

private extension SkillsScreen {
    var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skills")
                        .font(.largeTitle.weight(.semibold))

                    Text("Give your agents superpowers.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await viewModel.refreshCatalog()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .secondaryActionButtonStyle()

                Button {
                    isCreateSheetPresented = true
                } label: {
                    Label("New Skill", systemImage: "plus")
                }
                .primaryActionButtonStyle()
            }

            AppTextField(
                "Search skills",
                text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchQuery = $0 }
                )
            )
        }
    }

    var introCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Extend your agents with skills")
                        .font(.headline)

                    Text("Skills are reusable modules that give agents new capabilities.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isCreateSheetPresented = true
                } label: {
                    Label("New Skill", systemImage: "plus")
                }
                .primaryActionButtonStyle()
            }
        }
    }

    func section(title: String, skills: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(skills) { skill in
                    SkillCard(
                        skill: skill,
                        onOpen: {
                            selectedSkill = skill
                        },
                        onPrimaryAction: {
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

private struct SkillCard: View {
    let skill: Skill
    let onOpen: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(skill.name)
                        .font(.headline)
                        .lineLimit(2)

                    Text(skill.owner.map { owner in
                        guard let repo = skill.repo else { return owner }
                        return "\(owner)/\(repo)"
                    } ?? "Local")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(skill.source == .skillsSh ? "skills.sh" : skill.source.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
            }

            Text(skill.description.isEmpty ? "No description available." : skill.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if skill.isInstalled, !skill.syncedAgentIDs.isEmpty {
                Text("Synced: \(skill.syncedAgentIDs.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let installs = skill.installs {
                Text("\(installs.formatted()) installs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Details", action: onOpen)
                    .secondaryActionButtonStyle()
                Spacer()
                if skill.isInstalled {
                    Button("Uninstall", role: .destructive, action: onPrimaryAction)
                        .destructiveActionButtonStyle()
                } else {
                    Button("Install", action: onPrimaryAction)
                        .primaryActionButtonStyle()
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
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

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            SkillMarkdownContent(markdown: markdown, isLoading: isLoading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if let owner = skill.owner,
                   let repo = skill.repo,
                   let url = URL(string: "https://github.com/\(owner)/\(repo)") {
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
                markdown = try await viewModel.fetchSkillMarkdown(for: skill)
            } catch {
                onError(error)
                markdown = skill.description
            }
            isLoading = false
        }
    }
}

private struct SkillMarkdownContent: View {
    let markdown: String
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
                        StructuredText(markdown: markdown)
                            .textual.structuredTextStyle(.default)
                            .textual.textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
        }
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
            Text("Create Skill")
                .font(.title2.weight(.semibold))

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
