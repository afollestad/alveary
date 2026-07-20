import SwiftUI

struct SkillsPane: View {
    let viewModel: SkillsViewModel

    var body: some View {
        switch viewModel.activePaneTarget {
        case .newSkill:
            NewSkillPane(viewModel: viewModel)
        case .details(let skillID):
            if let session = viewModel.detailSessions[skillID] {
                SkillDetailsPane(viewModel: viewModel, session: session)
            }
        case nil:
            EmptyView()
        }
    }
}

private struct NewSkillPane: View {
    let viewModel: SkillsViewModel

    @FocusState private var isNameFocused: Bool

    private var draft: Binding<NewSkillDraft> {
        Binding(
            get: { viewModel.newSkillSession?.draft ?? NewSkillDraft() },
            set: { viewModel.updateNewSkillDraft($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ContextualPaneHeader(
                "New Skill",
                closeAccessibilityLabel: "Close new skill pane",
                onClose: viewModel.dismissActivePane
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let errorMessage = viewModel.newSkillSession?.errorMessage {
                        InlineBanner(
                            message: errorMessage,
                            severity: .error,
                            autoDismissAfter: nil,
                            onDismiss: viewModel.clearActivePaneError
                        )
                    }

                    AppTextField("Name (kebab-case)", text: draft.name)
                        .focused($isNameFocused)
                    AppTextField("Description", text: draft.description)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Instructions")
                            .font(.headline)
                        AppTextEditor(text: draft.instructions, minHeight: 260)
                    }
                }
                .padding(20)
            }

            footer
        }
        .onAppear {
            isNameFocused = true
        }
        .onExitCommand(perform: viewModel.dismissActivePane)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Button("Cancel", action: viewModel.dismissActivePane)
                    .secondaryActionButtonStyle()
                Spacer()
                createButton
            }

            VStack(alignment: .leading, spacing: 10) {
                createButton
                Button("Cancel", action: viewModel.dismissActivePane)
                    .secondaryActionButtonStyle()
            }
        }
        .padding(16)
        .background(.bar)
        .overlay(alignment: .top) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }

    private var createButton: some View {
        Button("Create") {
            Task { await viewModel.submitNewSkill() }
        }
        .primaryActionButtonStyle()
        .disabled(
            draft.wrappedValue.name.isEmpty
                || draft.wrappedValue.description.isEmpty
                || viewModel.newSkillSession?.isSubmitting == true
        )
    }
}

private struct SkillDetailsPane: View {
    let viewModel: SkillsViewModel
    let session: SkillDetailsPaneSession

    @State private var uninstallConfirmation: DestructiveConfirmationRequest?

    var body: some View {
        VStack(spacing: 0) {
            ContextualPaneHeader(
                session.skill.name,
                subtitle: session.skill.description.isEmpty ? "No description available." : session.skill.description,
                closeAccessibilityLabel: "Close skill details",
                onClose: viewModel.dismissActivePane
            )

            if let errorMessage = session.errorMessage {
                InlineBanner(
                    message: errorMessage,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: viewModel.clearActivePaneError
                )
                .padding([.horizontal, .top], 16)
            }

            SkillMarkdownContent(
                markdown: session.markdown,
                baseURL: session.markdownBaseURL,
                isLoading: session.isLoading
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .destructiveConfirmation($uninstallConfirmation)
        .onExitCommand(perform: viewModel.dismissActivePane)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                githubButton
                Spacer()
                mutationButton
            }

            VStack(alignment: .leading, spacing: 10) {
                mutationButton
                githubButton
            }
        }
        .padding(16)
        .background(.bar)
        .overlay(alignment: .top) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }

    @ViewBuilder
    private var githubButton: some View {
        if let url = session.resolvedGitHubURL ?? session.skill.githubURL {
            Button("View on GitHub") {
                UIApplicationShim.open(url: url)
            }
            .secondaryActionButtonStyle()
        }
    }

    @ViewBuilder
    private var mutationButton: some View {
        if session.skill.isInstalled {
            Button("Uninstall", role: .destructive) {
                uninstallConfirmation = makeSkillUninstallConfirmation(for: session.skill) {
                    Task { await viewModel.uninstallActiveSkill() }
                }
            }
            .destructiveActionButtonStyle()
            .disabled(session.isSubmitting)
        } else {
            Button("Install") {
                Task { await viewModel.installActiveSkill() }
            }
            .primaryActionButtonStyle()
            .disabled(session.isSubmitting)
        }
    }
}

private struct SkillMarkdownContent: View {
    let markdown: String
    let baseURL: URL?
    let isLoading: Bool

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading skill details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    AppMarkdownText(markdown: markdown, baseURL: baseURL)
                        .environment(\.openURL, OpenURLAction { url in
                            UIApplicationShim.open(url: resolvedURL(for: url))
                            return .handled
                        })
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func resolvedURL(for url: URL) -> URL {
        guard url.scheme == nil, let baseURL else {
            return url
        }
        return URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL ?? url
    }
}
