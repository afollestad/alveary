import SwiftUI

/// The `AGENTS.md` sub-section on the Agents settings tab: a shared global
/// instructions file at `~/.agents/AGENTS.md`, per-agent link rows, and an
/// `Edit` row opening `AgentsInstructionsEditorSheet`.
struct AgentsInstructionsSection: View {
    let model: GlobalInstructionsEditorModel

    @State private var confirmation: DestructiveConfirmationRequest?
    @State private var linkRequest: AgentInstructionsLinkRequest?
    @State private var isEditorPresented = false

    var body: some View {
        presentations(
            SettingsFormSection("AGENTS.md") {
                SettingsFormRow(showsDivider: !visibleLinkRows.isEmpty || model.errorMessage != nil) {
                    SettingsResponsiveControlRow(
                        "Shared instructions",
                        helpText: "Shared instructions for every agent, stored at \(model.sharedPathDescription).",
                        horizontalControlSizing: .intrinsicInline
                    ) {
                        editControl
                    }
                }

                linkRows

                errorRow
            }
        )
        .task {
            await model.loadIfNeeded()
        }
    }
}

private extension AgentsInstructionsSection {
    var editControl: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            if model.isDirty {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Edit") {
                isEditorPresented = true
            }
            .secondaryActionButtonStyle()
        }
    }

    /// Only agents needing attention get a row; a fully linked agent adds
    /// nothing beyond what the shared-path help text already says, and hiding
    /// those rows keeps the section flat as more agents are added.
    var visibleLinkRows: [(agent: AgentDefinition, state: AgentInstructionsLinkState)] {
        model.linkRows.filter { $0.state != .linked }
    }

    @ViewBuilder
    var linkRows: some View {
        let rows = visibleLinkRows
        ForEach(Array(rows.enumerated()), id: \.element.agent.id) { index, row in
            SettingsFormRow(showsDivider: index < rows.count - 1 || model.errorMessage != nil) {
                AgentInstructionsLinkRow(
                    agent: row.agent,
                    state: row.state,
                    onCopyIntoShared: { requestCopyIntoShared(for: row.agent) },
                    onLink: { requestLink(for: row.agent) }
                )
            }
        }
    }

    @ViewBuilder
    var errorRow: some View {
        if let errorMessage = model.errorMessage {
            SettingsFormRow(showsDivider: false) {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    /// Presentation modifiers live in one helper to keep `body` off the type-check budget.
    func presentations<Content: View>(_ content: Content) -> some View {
        content
            .destructiveConfirmation($confirmation)
            .sheet(isPresented: $isEditorPresented) {
                AgentsInstructionsEditorSheet(
                    model: model,
                    onCancel: { isEditorPresented = false },
                    onSaved: { isEditorPresented = false }
                )
            }
            .confirmationDialog(
                linkRequest?.title ?? "",
                isPresented: linkDialogPresentationBinding,
                titleVisibility: .visible,
                presenting: linkRequest
            ) { request in
                Button("Copy contents and link") {
                    linkRequest = nil
                    Task {
                        await model.link(agentID: request.agentID, copyingContents: true)
                    }
                }
                Button("Link only", role: .destructive) {
                    linkRequest = nil
                    Task {
                        await model.link(agentID: request.agentID, copyingContents: false)
                    }
                }
                Button("Cancel", role: .cancel) {
                    linkRequest = nil
                }
            } message: { request in
                Text(request.message)
            }
    }

    var linkDialogPresentationBinding: Binding<Bool> {
        Binding(
            get: { linkRequest != nil },
            set: { isPresented in
                if !isPresented {
                    linkRequest = nil
                }
            }
        )
    }

    /// Both migration actions reload the shared file from disk afterwards, which
    /// drops an unsaved draft. The sheet's Cancel deliberately keeps that draft
    /// alive off-screen, so the warning is the only thing standing between the
    /// user and silently losing it.
    var discardWarning: String {
        model.isDirty ? " Unsaved changes to the shared file will be discarded." : ""
    }

    func requestCopyIntoShared(for agent: AgentDefinition) {
        guard let path = agent.instructionsPath else {
            return
        }
        let message = "This appends the contents of \(path) to \(model.sharedPathDescription). "
            + "The original file is left unchanged.\(discardWarning)"
        confirmation = DestructiveConfirmationRequest(
            title: "Copy into shared file?",
            message: message,
            confirmTitle: "Copy",
            confirm: {
                Task {
                    await model.copyIntoShared(agentID: agent.id)
                }
            }
        )
    }

    func requestLink(for agent: AgentDefinition) {
        guard let path = agent.instructionsPath else {
            return
        }
        let backupPath = "\(path).backup"
        let backupSentence: String
        if case .hasOwnFile = model.linkStates[agent.id] {
            backupSentence = "The current file is backed up to \(backupPath) first, replacing any existing backup."
        } else {
            backupSentence = ""
        }
        linkRequest = AgentInstructionsLinkRequest(
            agentID: agent.id,
            title: "Link \(agent.name) to the shared file?",
            message: "\(path) becomes a symlink to \(model.sharedPathDescription). \(backupSentence)"
                .trimmingCharacters(in: .whitespaces)
                + discardWarning
        )
    }
}

private struct AgentInstructionsLinkRequest {
    let agentID: String
    let title: String
    let message: String
}
