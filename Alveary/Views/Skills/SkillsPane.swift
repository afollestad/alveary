import SwiftUI

struct SkillsPane: View {
    let viewModel: SkillsViewModel
    let target: SkillsPaneTarget
    let onDismiss: () -> Void

    var body: some View {
        switch target {
        case .newSkill:
            NewSkillPane(viewModel: viewModel, onDismiss: onDismiss)
        case .details(let skillID):
            if let session = viewModel.detailSessions[skillID] {
                SkillDetailsPane(viewModel: viewModel, session: session, onDismiss: onDismiss)
            }
        }
    }
}

private struct NewSkillPane: View {
    let viewModel: SkillsViewModel
    let onDismiss: () -> Void

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
                onClose: onDismiss
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
                .padding(ContextualPaneLayout.contentInsets())
            }

            footer
        }
        .onAppear {
            isNameFocused = true
        }
        .onExitCommand(perform: onDismiss)
    }

    private var footer: some View {
        ContextualPaneFooter {
            Button(action: onDismiss) {
                ActionButtonLabel(title: "Cancel", icon: .system("xmark"))
            }
            .secondaryActionButtonStyle(expandsHorizontally: true)
        } trailingAction: {
            createButton
        }
    }

    private var createButton: some View {
        Button {
            Task { await viewModel.submitNewSkill() }
        } label: {
            ActionButtonLabel(title: "Create", icon: .system("checkmark"))
        }
        .primaryActionButtonStyle(expandsHorizontally: true)
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
    let onDismiss: () -> Void

    @State private var uninstallConfirmation: DestructiveConfirmationRequest?

    var body: some View {
        VStack(spacing: 0) {
            ContextualPaneHeader(
                session.skill.name,
                closeAccessibilityLabel: "Close skill details",
                onClose: onDismiss
            )

            if let errorMessage = session.errorMessage {
                InlineBanner(
                    message: errorMessage,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: viewModel.clearActivePaneError
                )
                .contextualPaneHorizontalInsets()
                .padding(.top, 12)
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
        .onExitCommand(perform: onDismiss)
    }

    private var footer: some View {
        ContextualPaneFooter {
            githubButton
        } trailingAction: {
            mutationButton
        }
    }

    @ViewBuilder
    private var githubButton: some View {
        if let url = session.resolvedGitHubURL ?? session.skill.githubURL {
            Button {
                UIApplicationShim.open(url: url)
            } label: {
                ActionButtonLabel(title: "View on GitHub", icon: .system("arrow.up.right.square"))
            }
            .secondaryActionButtonStyle(expandsHorizontally: true)
        }
    }

    @ViewBuilder
    private var mutationButton: some View {
        if session.skill.isInstalled {
            Button(role: .destructive) {
                uninstallConfirmation = makeSkillUninstallConfirmation(for: session.skill) {
                    Task { await viewModel.uninstallActiveSkill() }
                }
            } label: {
                ActionButtonLabel(title: "Uninstall", icon: .system("trash"))
            }
            .destructiveActionButtonStyle(expandsHorizontally: true)
            .disabled(session.isSubmitting)
        } else {
            Button {
                Task { await viewModel.installActiveSkill() }
            } label: {
                ActionButtonLabel(title: "Install", icon: .system("arrow.down.circle"))
            }
            .primaryActionButtonStyle(expandsHorizontally: true)
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
                        .padding(ContextualPaneLayout.contentInsets())
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
