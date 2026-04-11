import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let heading: String
    let subtext: String
    let actions: [EmptyStateAction]

    struct EmptyStateAction {
        let title: String
        let style: EmptyStateActionStyle
        let action: () -> Void
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
                        if action.style == .primary {
                            Button(action.title, action: action.action)
                                .primaryActionButtonStyle()
                        } else {
                            Button(action.title, action: action.action)
                                .buttonStyle(.bordered)
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
