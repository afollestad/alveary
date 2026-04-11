import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let heading: String
    let subtext: String
    let actions: [EmptyStateAction]

    struct EmptyStateAction {
        let title: String
        let systemImage: String?
        let style: EmptyStateActionStyle
        let action: () -> Void

        init(
            title: String,
            systemImage: String? = nil,
            style: EmptyStateActionStyle,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.systemImage = systemImage
            self.style = style
            self.action = action
        }
    }

    var body: some View {
        VStack(spacing: 24) {
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

                        if action.style == .primary {
                            button
                                .primaryActionButtonStyle()
                        } else {
                            button
                                .secondaryActionButtonStyle()
                        }
                    }
                }
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
