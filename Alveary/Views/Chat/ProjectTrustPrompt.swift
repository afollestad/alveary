import SwiftData
import SwiftUI

private let projectTrustPromptMessageMaxWidth: CGFloat = 760

struct ProjectTrustPrompt: Equatable {
    let threadID: PersistentIdentifier
    let canonicalProjectPath: String
    let projectName: String
    let providerID: String

    var displayProjectPath: String {
        CanonicalPath.abbreviateHomeDirectory(canonicalProjectPath)
    }
}

struct ProjectTrustPromptView: View {
    let prompt: ProjectTrustPrompt
    let onTrust: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Trust this project?")
                    .font(.title3.weight(.semibold))

                Text("This provider needs the project marked as trusted before the thread can start.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: projectTrustPromptMessageMaxWidth)

                Text(prompt.displayProjectPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(prompt.canonicalProjectPath)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 12) {
                Button("No, don't trust it", role: .destructive, action: onDeny)
                    .secondaryActionButtonStyle()

                Button("Yes, trust it", action: onTrust)
                    .primaryActionButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
