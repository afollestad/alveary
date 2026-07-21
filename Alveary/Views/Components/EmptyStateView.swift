import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let heading: String
    let subtext: String
    let actions: [EmptyStateAction]
    var actionFocus: FocusState<String?>.Binding?
    let iconToHeadingSpacing: CGFloat

    init(
        icon: String,
        heading: String,
        subtext: String,
        actions: [EmptyStateAction],
        actionFocus: FocusState<String?>.Binding? = nil,
        iconToHeadingSpacing: CGFloat = 24
    ) {
        self.icon = icon
        self.heading = heading
        self.subtext = subtext
        self.actions = actions
        self.actionFocus = actionFocus
        self.iconToHeadingSpacing = iconToHeadingSpacing
    }

    struct EmptyStateAction {
        let title: String
        let systemImage: String?
        let style: EmptyStateActionStyle
        let helpText: String?
        let focusID: String?
        let action: () -> Void

        init(
            title: String,
            systemImage: String? = nil,
            style: EmptyStateActionStyle,
            helpText: String? = nil,
            focusID: String? = nil,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.systemImage = systemImage
            self.style = style
            self.helpText = helpText
            self.focusID = focusID
            self.action = action
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 10) {
                Text(heading)
                    .font(.title2.weight(.semibold))

                Text(subtext)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(.top, iconToHeadingSpacing)

            if !actions.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        let button = Group {
                            if let systemImage = action.systemImage {
                                Button(action: action.action) {
                                    Label(action.title, systemImage: systemImage)
                                }
                            } else {
                                Button(action.title, action: action.action)
                            }
                        }

                        let styled = Group {
                            if action.style == .primary {
                                button
                                    .primaryActionButtonStyle()
                            } else {
                                button
                                    .secondaryActionButtonStyle()
                            }
                        }

                        let focusable = Group {
                            if let actionFocus, let focusID = action.focusID {
                                styled.focused(actionFocus, equals: focusID)
                            } else {
                                styled
                            }
                        }

                        if let helpText = action.helpText {
                            focusable.help(helpText)
                        } else {
                            focusable
                        }
                    }
                }
                .padding(.top, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

enum EmptyStateActionStyle {
    case primary
    case secondary
}
