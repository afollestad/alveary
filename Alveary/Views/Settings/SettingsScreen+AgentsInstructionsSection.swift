import SwiftUI

/// The `AGENTS.md` sub-section on the Agents settings tab: a shared global
/// instructions file at `~/.agents/AGENTS.md`, per-agent link rows, and a
/// BlockInputKit editor with confirmed Revert/Save actions.
struct AgentsInstructionsSection: View {
    let model: GlobalInstructionsEditorModel

    @State private var confirmation: DestructiveConfirmationRequest?
    @State private var linkRequest: AgentInstructionsLinkRequest?

    var body: some View {
        confirmationDialogs(
            VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionHeaderSpacing) {
                SettingsFormSectionHeader("AGENTS.md")

                VStack(alignment: .leading, spacing: 14) {
                    Text("Shared instructions for every agent, stored at \(model.sharedPathDescription).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }

                    linkRows

                    AgentsInstructionsEditor(model: model)

                    actionRow
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(
                        cornerRadius: SettingsScreenLayout.settingsSectionCornerRadius,
                        style: .continuous
                    )
                    .fill(Color.secondary.opacity(0.08))
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
        .task {
            await model.loadIfNeeded()
        }
    }
}

private extension AgentsInstructionsSection {
    /// Only agents needing attention get a row; a fully linked agent adds
    /// nothing beyond what the shared-path caption already says, and hiding
    /// those rows keeps the section flat as more agents are added.
    @ViewBuilder
    var linkRows: some View {
        let rows = model.linkRows.filter { $0.state != .linked }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.agent.id) { row in
                    AgentInstructionsLinkRow(
                        agent: row.agent,
                        state: row.state,
                        onCopyIntoShared: { requestCopyIntoShared(for: row.agent) },
                        onLink: { requestLink(for: row.agent) }
                    )
                }
            }
        }
    }

    var actionRow: some View {
        HStack(spacing: 10) {
            Spacer()

            Button("Revert", action: requestRevert)
                .secondaryActionButtonStyle()
                .disabled(!model.isDirty)

            Button("Save", action: requestSave)
                .primaryActionButtonStyle()
                .disabled(!model.isDirty)
        }
    }

    /// Presentation modifiers live in one helper to keep `body` off the type-check budget.
    func confirmationDialogs<Content: View>(_ content: Content) -> some View {
        content
            .destructiveConfirmation($confirmation)
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

    func requestSave() {
        let message = "This overwrites \(model.sharedPathDescription). "
            + "Formatting is normalized to canonical markdown, so spacing may differ from the original file."
        confirmation = DestructiveConfirmationRequest(
            title: "Save shared instructions?",
            message: message,
            confirmTitle: "Save",
            confirm: {
                Task {
                    await model.save()
                }
            }
        )
    }

    func requestRevert() {
        confirmation = DestructiveConfirmationRequest(
            title: "Revert changes?",
            message: "This discards unsaved changes and reloads \(model.sharedPathDescription) from disk.",
            confirmTitle: "Revert",
            confirm: {
                Task {
                    await model.revert()
                }
            }
        )
    }

    func requestCopyIntoShared(for agent: AgentDefinition) {
        guard let path = agent.instructionsPath else {
            return
        }
        confirmation = DestructiveConfirmationRequest(
            title: "Copy into shared file?",
            message: "This appends the contents of \(path) to \(model.sharedPathDescription). The original file is left unchanged.",
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
        )
    }
}

private struct AgentInstructionsLinkRequest {
    let agentID: String
    let title: String
    let message: String
}
