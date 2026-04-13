import SwiftUI

struct ProjectSettingsActionsCard: View {
    let actions: [ProjectSettingsActionDraft]
    let onUpdateAction: (Int, ProjectSettingsActionDraft) -> Void
    let onAddAction: () -> Void
    let onRemoveAction: (Int) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                if actions.isEmpty {
                    Text("Add actions that appear in the toolbar whenever one of this project's threads is selected.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        ProjectSettingsActionEditor(
                            action: action,
                            onChange: { onUpdateAction(index, $0) },
                            onRemove: { onRemoveAction(index) }
                        )
                    }
                }

                HStack {
                    Button("Add Action", action: onAddAction)
                        .secondaryActionButtonStyle()

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
        } label: {
            Label("Actions", systemImage: "play")
        }
    }
}

struct ProjectSettingsAccessoryIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovering ? 0.12 : 0))
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                self.isHovering = isHovering
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

private enum ProjectSettingsActionEditorLayout {
    static let rowControlWidth: CGFloat = 520
    static let accessoryButtonWidth: CGFloat = 24
    static let accessorySpacing: CGFloat = 12

    static let nameFieldWidth = rowControlWidth - accessoryButtonWidth - accessorySpacing
}

private struct ProjectSettingsActionEditor: View {
    let action: ProjectSettingsActionDraft
    let onChange: (ProjectSettingsActionDraft) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Name")
                    .accessibilityHidden(true)

                Spacer(minLength: 16)

                AppTextField(
                    "Name",
                    text: Binding(
                        get: { action.name },
                        set: { newValue in
                            var updatedAction = action
                            updatedAction.name = newValue
                            onChange(updatedAction)
                        }
                    ),
                    showsPrompt: false,
                    textAlignment: .leading,
                    horizontalPadding: 10,
                    verticalPadding: 7
                )
                .frame(width: ProjectSettingsActionEditorLayout.nameFieldWidth)

                ProjectSettingsAccessoryIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "Remove action",
                    action: onRemove
                )
            }
            .frame(maxWidth: .infinity, minHeight: SettingsScreenLayout.settingsRowHeight, alignment: .leading)

            SettingsTextFieldRow(
                "Command",
                text: Binding(
                    get: { action.command },
                    set: { newValue in
                        var updatedAction = action
                        updatedAction.command = newValue
                        onChange(updatedAction)
                    }
                ),
                width: ProjectSettingsActionEditorLayout.rowControlWidth,
                textAlignment: .leading
            )

            ProjectSettingsActionIconRow(
                symbolName: action.displayedIconName,
                onSelect: { selectedIcon in
                    var updatedAction = action
                    updatedAction.icon = selectedIcon
                    onChange(updatedAction)
                }
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct ProjectSettingsActionIconRow: View {
    let symbolName: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Icon")
                .accessibilityHidden(true)

            Spacer(minLength: 16)

            Menu {
                ForEach(ProjectSettingsActionIconOption.supported) { option in
                    Button {
                        onSelect(option.symbolName)
                    } label: {
                        Label(option.label, systemImage: option.symbolName)
                    }
                }
            } label: {
                let currentOption = ProjectSettingsActionIconOption.resolved(for: symbolName)
                Label(currentOption.label, systemImage: currentOption.symbolName)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Action icon")
        }
        .frame(maxWidth: .infinity, minHeight: SettingsScreenLayout.settingsRowHeight, alignment: .leading)
    }
}

private struct ProjectSettingsActionIconOption: Identifiable {
    let symbolName: String
    let label: String

    var id: String { symbolName }

    static let supported: [Self] = [
        .init(symbolName: "terminal", label: "Terminal"),
        .init(symbolName: "hammer", label: "Build"),
        .init(symbolName: "checkmark.circle", label: "Check"),
        .init(symbolName: "play", label: "Run"),
        .init(symbolName: "shippingbox", label: "Package"),
        .init(symbolName: "wand.and.stars", label: "Generate"),
        .init(symbolName: "ladybug", label: "Debug"),
        .init(symbolName: "sparkles", label: "Custom")
    ]

    static func resolved(for symbolName: String) -> Self {
        if symbolName == "play.square" {
            return .init(symbolName: "play", label: "Run")
        }

        return supported.first(where: { $0.symbolName == symbolName })
            ?? .init(symbolName: symbolName, label: symbolName.replacingOccurrences(of: ".", with: " ").capitalized)
    }
}
