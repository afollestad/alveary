import AppKit
import SwiftUI

struct SkillsScreen: View {
    let viewModel: SkillsViewModel

    @State private var hasLoaded = false
    @State private var screenError: String?
    @State private var isCreateSheetPresented = false
    @State private var selectedSkill: Skill?

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

                if viewModel.installed.isEmpty && viewModel.catalog.isEmpty && viewModel.searchResults.isEmpty && hasLoaded {
                    EmptyStateView(
                        icon: "puzzlepiece.extension",
                        heading: "No skills available",
                        subtext: "Install or create a skill once catalog data is available.",
                        actions: [
                            .init(title: "+ New Skill", style: .primary) {
                                isCreateSheetPresented = true
                            }
                        ]
                    )
                } else {
                    if !viewModel.installed.isEmpty {
                        section(title: "Installed", skills: viewModel.installed)
                    }

                    let recommended = viewModel.catalog.filter { !$0.isInstalled }
                    if !recommended.isEmpty {
                        section(title: "Recommended", skills: recommended)
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

                Button("Refresh") {
                    Task {
                        await viewModel.refreshCatalog()
                    }
                }

                Button("+ New Skill") {
                    isCreateSheetPresented = true
                }
                .buttonStyle(.borderedProminent)
            }

            TextField(
                "Search skills",
                text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchQuery = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
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

                Button("+ New Skill") {
                    isCreateSheetPresented = true
                }
                .buttonStyle(.borderedProminent)
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
                            Task {
                                if skill.isInstalled {
                                    await uninstall(skill)
                                } else {
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
                Spacer()
                if skill.isInstalled {
                    Button("Uninstall", action: onPrimaryAction)
                        .buttonStyle(.bordered)
                } else {
                    Button("Install", action: onPrimaryAction)
                        .buttonStyle(.borderedProminent)
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

            Group {
                if isLoading {
                    ProgressView("Loading skill details...")
                } else {
                    ScrollView {
                        if let rendered = try? AttributedString(markdown: markdown) {
                            Text(rendered)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        } else {
                            Text(markdown)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if let owner = skill.owner,
                   let repo = skill.repo,
                   let url = URL(string: "https://github.com/\(owner)/\(repo)") {
                    Button("View on GitHub") {
                        UIApplicationShim.open(url: url)
                    }
                }

                Spacer()

                if skill.isInstalled {
                    Button("Uninstall") {
                        Task {
                            await onUninstall(skill)
                            dismiss()
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Install") {
                        Task {
                            await onInstall(skill)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 520)
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

            TextField("Name (kebab-case)", text: $name)
            TextField("Description", text: $description)

            TextEditor(text: $instructions)
                .font(.body)
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Create") {
                    onCreate(name, description, instructions)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || description.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
    }
}

private enum UIApplicationShim {
    static func open(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}
