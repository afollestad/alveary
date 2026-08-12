import SwiftUI

/// The pane compares equal across the lane's own render passes so a resize drag or an
/// unrelated root invalidation cannot rebuild the detail subtree. Its body still reads
/// `detailSessions`, so a write to the displayed session re-renders it as before.
struct SkillsPane: View, Equatable {
    let viewModel: SkillsViewModel
    let target: SkillsPaneTarget
    let onDismiss: () -> Void

    /// `onDismiss` is excluded: `ResizableRightPane` keys the pane by presentation
    /// identity, so a fresh closure meaning something different arrives only with a
    /// new `.id` — which tears this view down instead of comparing it.
    nonisolated static func == (lhs: SkillsPane, rhs: SkillsPane) -> Bool {
        lhs.viewModel === rhs.viewModel && lhs.target == rhs.target
    }

    var body: some View {
        switch target {
        case .newSkill:
            NewSkillPane(viewModel: viewModel, onDismiss: onDismiss)
                .equatable()
        case .details(let skillID):
            if let session = viewModel.detailSessions[skillID] {
                SkillDetailsPane(viewModel: viewModel, session: session, onDismiss: onDismiss)
                    .equatable()
            }
        }
    }
}

private struct NewSkillPane: View, Equatable {
    let viewModel: SkillsViewModel
    let onDismiss: () -> Void

    @FocusState private var isNameFocused: Bool
    /// The instructions live here rather than in the session draft: writing markdown
    /// back per keystroke would reconfigure the editor mid-typing. Appearing and
    /// disappearing sync it with the session so a closed pane keeps its text.
    @State private var instructionsDraft = AppMarkdownDraft(markdown: "")

    /// The draft is read through `viewModel` inside the body, so typing invalidates this
    /// view directly regardless of `==`; equality only gates the lane's own passes.
    nonisolated static func == (lhs: NewSkillPane, rhs: NewSkillPane) -> Bool {
        lhs.viewModel === rhs.viewModel
    }

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
                        AppMarkdownEditor(
                            draft: instructionsDraft,
                            placeholder: "Write the skill instructions in markdown...",
                            sizing: .growsToLineCount(minimum: 9, maximum: 20)
                        )
                    }
                }
                .padding(ContextualPaneLayout.contentInsets())
            }

            footer
        }
        .onAppear {
            isNameFocused = true
            let stored = draft.wrappedValue.instructions
            if !stored.isEmpty {
                instructionsDraft.resetContent(to: stored)
            }
        }
        .onDisappear(perform: storeInstructions)
        .onExitCommand(perform: onDismiss)
    }

    /// Moves the editor's text into the session draft. Called before submitting and
    /// on teardown, which is what lets a dismissed pane reopen with its text intact.
    private func storeInstructions() {
        var updated = draft.wrappedValue
        guard updated.instructions != instructionsDraft.markdown else {
            return
        }
        updated.instructions = instructionsDraft.markdown
        viewModel.updateNewSkillDraft(updated)
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
            storeInstructions()
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

private struct SkillDetailsPane: View, Equatable {
    let viewModel: SkillsViewModel
    let session: SkillDetailsPaneSession
    let onDismiss: () -> Void

    @State private var uninstallConfirmation: DestructiveConfirmationRequest?

    /// Takes the session by value, so another skill's markdown landing in
    /// `detailSessions` no longer rebuilds this pane's rendered markdown.
    nonisolated static func == (lhs: SkillDetailsPane, rhs: SkillDetailsPane) -> Bool {
        lhs.session == rhs.session && lhs.viewModel === rhs.viewModel
    }

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
                ActionButtonLabel(title: "Install", icon: .system("plus"))
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

    @Environment(\.rightPaneHasSettled) private var paneHasSettled

    /// Latches the first settle so a beginning dismissal, which flips the environment
    /// back to `false`, cannot swap the document out for the spinner mid-retract —
    /// see `RightPaneHasSettledKey`.
    @State private var hasSettledOnce = false

    /// The document waits for the lane's slide on top of its own load: laying out the
    /// whole markdown on the pane's first frames stalls the main thread mid-animation,
    /// freezing the slide for the layout's whole cost. The spinner is cheap to animate,
    /// and the document fades in once the pane has stopped moving.
    private var showsDocument: Bool {
        !isLoading && (paneHasSettled || hasSettledOnce)
    }

    var body: some View {
        Group {
            if showsDocument {
                ScrollView {
                    AppMarkdownText(markdown: markdown, baseURL: baseURL)
                        .environment(\.openURL, OpenURLAction { url in
                            UIApplicationShim.open(url: resolvedURL(for: url))
                            return .handled
                        })
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ContextualPaneLayout.contentInsets())
                }
                .transition(.opacity)
            } else {
                ProgressView("Loading skill details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showsDocument)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: paneHasSettled, initial: true) { _, hasSettled in
            if hasSettled {
                hasSettledOnce = true
            }
        }
    }

    private func resolvedURL(for url: URL) -> URL {
        guard url.scheme == nil, let baseURL else {
            return url
        }
        return URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL ?? url
    }
}
