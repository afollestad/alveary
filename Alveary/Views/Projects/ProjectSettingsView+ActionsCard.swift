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
    let usesDestructiveStyle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .modifier(AccessoryIconButtonStyleModifier(usesDestructiveStyle: usesDestructiveStyle))
        .accessibilityLabel(accessibilityLabel)
    }
}

private enum ProjectSettingsActionEditorLayout {
    static let accessoryButtonWidth: CGFloat = 30
    static let accessorySpacing: CGFloat = 12
}

private struct ProjectSettingsActionEditor: View {
    let action: ProjectSettingsActionDraft
    let onChange: (ProjectSettingsActionDraft) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsResponsiveControlRow("Name") {
                HStack(spacing: ProjectSettingsActionEditorLayout.accessorySpacing) {
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

                    ProjectSettingsAccessoryIconButton(
                        systemImage: "trash",
                        accessibilityLabel: "Remove action",
                        usesDestructiveStyle: true,
                        action: onRemove
                    )
                    .frame(width: ProjectSettingsActionEditorLayout.accessoryButtonWidth)
                }
            }

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

private struct AccessoryIconButtonStyleModifier: ViewModifier {
    let usesDestructiveStyle: Bool

    func body(content: Content) -> some View {
        if usesDestructiveStyle {
            content.destructiveIconActionButtonStyle()
        } else {
            content.iconActionButtonStyle()
        }
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
        .init(symbolName: "safari", label: "Browser"),
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
