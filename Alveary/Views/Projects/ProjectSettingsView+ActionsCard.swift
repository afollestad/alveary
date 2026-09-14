import SwiftUI

struct ProjectSettingsActionsCard: View {
    let actions: [ProjectSettingsActionDraft]
    let onUpdateAction: (Int, ProjectSettingsActionDraft) -> Void
    let onRemoveAction: (Int) -> Void

    @State private var isCompact = false

    var body: some View {
        ProjectSettingsSection(title: "Toolbar actions") {
            VStack(alignment: .leading, spacing: ProjectSettingsLayout.rowSpacing) {
                if !isCompact {
                    ProjectSettingsActionRowLayout(isCompact: false) {
                        Text("Icon")
                            .frame(width: ActionButtonMetrics.iconButtonDiameter)
                        Text("Name")
                        Text("Command")
                        Color.clear.frame(height: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                }

                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    ProjectSettingsActionEditor(
                        index: index,
                        action: action,
                        isCompact: isCompact,
                        allowsRemoval: index != actions.count - 1 || !action.isEmpty,
                        onChange: { onUpdateAction(index, $0) },
                        onRemove: { onRemoveAction(index) }
                    )
                    .equatable()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.size.width < ProjectSettingsLayout.compactBreakpoint
            } action: { isCompact = $0 }
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
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ProjectSettingsActionIconOption: Identifiable {
    let symbolName: String
    let label: String

    var id: String { symbolName }

    static let supported: [Self] = [
        .init(symbolName: "arrow.trianglehead.branch", label: "Branch"),
        .init(symbolName: "safari", label: "Browser"),
        .init(symbolName: "hammer", label: "Build"),
        .init(symbolName: "checkmark.circle", label: "Check"),
        .init(symbolName: "sparkles", label: "Custom"),
        .init(symbolName: "ladybug", label: "Debug"),
        .init(symbolName: "icloud.and.arrow.down", label: "Download"),
        .init(symbolName: "wand.and.stars", label: "Generate"),
        .init(symbolName: "shippingbox", label: "Package"),
        .init(symbolName: "arrow.triangle.branch", label: "Pull Request"),
        .init(symbolName: "play", label: "Run"),
        .init(symbolName: "arrow.trianglehead.2.clockwise.rotate.90.icloud", label: "Sync"),
        .init(symbolName: "terminal", label: "Terminal"),
        .init(symbolName: "icloud.and.arrow.up", label: "Upload")
    ]

    static func resolved(for symbolName: String) -> Self {
        if symbolName == "play.square" {
            return .init(symbolName: "play", label: "Run")
        }

        return supported.first(where: { $0.symbolName == symbolName })
            ?? .init(symbolName: symbolName, label: symbolName.replacingOccurrences(of: ".", with: " ").capitalized)
    }
}

private struct ProjectSettingsActionEditor: View, Equatable {
    let index: Int
    let action: ProjectSettingsActionDraft
    let isCompact: Bool
    let allowsRemoval: Bool
    let onChange: (ProjectSettingsActionDraft) -> Void
    let onRemove: () -> Void

    /// Callbacks capture parent state storage and the compared index/draft; the index changes when an earlier row is removed.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.action == rhs.action
            && lhs.isCompact == rhs.isCompact && lhs.allowsRemoval == rhs.allowsRemoval
    }

    var body: some View {
        ProjectSettingsActionRowLayout(isCompact: isCompact) {
            ProjectSettingsActionIconPicker(
                symbolName: action.displayedIconName,
                onSelect: { selectedIcon in
                    var updatedAction = action
                    updatedAction.icon = selectedIcon
                    onChange(updatedAction)
                }
            )

            VStack(alignment: .leading, spacing: 4) {
                if isCompact {
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                }
                AppTextField(
                    "Name",
                    text: nameBinding,
                    horizontalPadding: 10,
                    verticalPadding: ProjectSettingsLayout.fieldVerticalPadding
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                if isCompact {
                    Text("Command").font(.caption).foregroundStyle(.secondary)
                }
                AppTextField(
                    "Command",
                    text: commandBinding,
                    horizontalPadding: 10,
                    verticalPadding: ProjectSettingsLayout.fieldVerticalPadding
                )
            }

            if allowsRemoval {
                ProjectSettingsAccessoryIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "Remove action",
                    usesDestructiveStyle: true,
                    action: onRemove
                )
            } else {
                Color.clear
                    .frame(width: ActionButtonMetrics.iconButtonDiameter, height: ActionButtonMetrics.iconButtonDiameter)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { action.name },
            set: { newValue in
                var updatedAction = action
                updatedAction.name = newValue
                onChange(updatedAction)
            }
        )
    }

    private var commandBinding: Binding<String> {
        Binding(
            get: { action.command },
            set: { newValue in
                var updatedAction = action
                updatedAction.command = newValue
                onChange(updatedAction)
            }
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
