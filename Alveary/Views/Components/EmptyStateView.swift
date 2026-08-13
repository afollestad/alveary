import SwiftUI

/// Octicon artwork under-fills its canvas, so this box has to exceed the 42pt
/// font below to match the optical size of the SF Symbols it stands in for.
/// Move both together.
private let emptyStateOcticonSize: CGFloat = 48

struct EmptyStateView<Accessory: View>: View {
    let icon: ActionIcon
    let heading: String
    let subtext: String
    let actions: [EmptyStateAction]
    var actionFocus: FocusState<String?>.Binding?
    let iconToHeadingSpacing: CGFloat
    /// Screen-specific content below the actions — the Scheduled screen's suggestion cards.
    /// It renders raw and owns its own top padding, so an `EmptyView` accessory costs the
    /// layout nothing and no branch here has to ask whether one was supplied.
    let accessory: Accessory

    init(
        icon: ActionIcon,
        heading: String,
        subtext: String,
        actions: [EmptyStateAction],
        actionFocus: FocusState<String?>.Binding? = nil,
        iconToHeadingSpacing: CGFloat = 24,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.heading = heading
        self.subtext = subtext
        self.actions = actions
        self.actionFocus = actionFocus
        self.iconToHeadingSpacing = iconToHeadingSpacing
        self.accessory = accessory()
    }

    /// SF Symbol convenience for the majority of empty states.
    init(
        icon: String,
        heading: String,
        subtext: String,
        actions: [EmptyStateAction],
        actionFocus: FocusState<String?>.Binding? = nil,
        iconToHeadingSpacing: CGFloat = 24,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(
            icon: .system(icon),
            heading: heading,
            subtext: subtext,
            actions: actions,
            actionFocus: actionFocus,
            iconToHeadingSpacing: iconToHeadingSpacing,
            accessory: accessory
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // The font sizes the SF Symbol case; `octiconSize` sizes the other.
            // The glyph restates the heading, so it stays out of VoiceOver —
            // an octicon would otherwise announce its asset name.
            ActionIconImage(icon: icon, octiconSize: emptyStateOcticonSize)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

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
                EmptyStateActionRow(actions: actions, actionFocus: actionFocus)
                    .padding(.top, 24)
            }

            accessory
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// The shape every empty state without extra content keeps, so the accessory slot stays
/// invisible to the ten-plus screens that never needed one.
extension EmptyStateView where Accessory == EmptyView {
    init(
        icon: ActionIcon,
        heading: String,
        subtext: String,
        actions: [EmptyStateAction],
        actionFocus: FocusState<String?>.Binding? = nil,
        iconToHeadingSpacing: CGFloat = 24
    ) {
        self.init(
            icon: icon,
            heading: heading,
            subtext: subtext,
            actions: actions,
            actionFocus: actionFocus,
            iconToHeadingSpacing: iconToHeadingSpacing,
            accessory: { EmptyView() }
        )
    }

    /// SF Symbol convenience for the majority of empty states.
    init(
        icon: String,
        heading: String,
        subtext: String,
        actions: [EmptyStateAction],
        actionFocus: FocusState<String?>.Binding? = nil,
        iconToHeadingSpacing: CGFloat = 24
    ) {
        self.init(
            icon: .system(icon),
            heading: heading,
            subtext: subtext,
            actions: actions,
            actionFocus: actionFocus,
            iconToHeadingSpacing: iconToHeadingSpacing
        )
    }
}

/// Top-level rather than nested in `EmptyStateView` because that type is generic over its
/// accessory, and a nested type would drag the generic argument into every call site that
/// names an action explicitly.
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

enum EmptyStateActionStyle {
    case primary
    case secondary
}

/// Extracted from `EmptyStateView.body` to keep its three nested `Group`s off the host's
/// type-check budget — see the budget rules in `Alveary/Views/AGENTS.md`.
private struct EmptyStateActionRow: View {
    let actions: [EmptyStateAction]
    let actionFocus: FocusState<String?>.Binding?

    var body: some View {
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
    }
}
