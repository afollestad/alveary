import AppKit
import SwiftUI

/// Shown under a failed required row. The onboarding modal cannot be dismissed and `gh` cannot be
/// made optional, so a machine where the in-app install cannot work still needs a way forward.
struct AppOnboardingManualInstallGuidance: View {
    let dependency: OnboardingDependency

    @State private var didCopyCommand = false

    var body: some View {
        if let guidance = dependency.manualInstallGuidance {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(guidance.command)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.86))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button {
                        copy(guidance.command)
                    } label: {
                        Image(systemName: didCopyCommand ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .iconActionButtonStyle()
                    .help("Copies `\(guidance.command)` to the clipboard.")
                    .accessibilityLabel("Copy \(dependency.displayName) install command")
                    .accessibilityValue(didCopyCommand ? "Copied" : "")
                    // Revert so the control keeps looking like a copy button; a permanent
                    // checkmark reads as a disabled "done" state on a row the user may retry.
                    .task(id: didCopyCommand) {
                        guard didCopyCommand else {
                            return
                        }
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else {
                            return
                        }
                        didCopyCommand = false
                    }

                    if let helpURL = guidance.helpURL {
                        Link(destination: helpURL) {
                            Text(helpURL.host() ?? helpURL.absoluteString)
                                .font(.caption)
                        }
                        .accessibilityLabel("Open \(dependency.displayName) download page")
                    }

                    Spacer(minLength: 0)
                }

                Text("Install manually in Terminal, then return to Alveary — it re-checks automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        didCopyCommand = true
    }
}
