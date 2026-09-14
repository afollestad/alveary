import SwiftUI

struct ProjectSettingsPreservePatternsCard: View {
    let patterns: [String]
    let bindingForPattern: (Int) -> Binding<String>
    let onRemovePattern: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ProjectSettingsLayout.rowSpacing) {
            HStack(spacing: 6) {
                Text("Files to copy")
                    .font(.subheadline.weight(.medium))
                    .accessibilityAddTraits(.isHeader)
                AppHoverInfoIcon(
                    text: "Copy matching files from this folder into new worktrees. Use file paths or glob patterns, such as config/*.json."
                )
            }

            Text(defaultsDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: ProjectSettingsLayout.rowSpacing) {
                ForEach(Array(patterns.enumerated()), id: \.offset) { index, pattern in
                    HStack(spacing: ProjectSettingsLayout.rowSpacing) {
                        AppTextField(
                            "File or pattern",
                            text: bindingForPattern(index),
                            horizontalPadding: 10,
                            verticalPadding: ProjectSettingsLayout.fieldVerticalPadding
                        )
                        .font(.body.monospaced())

                        if index < patterns.count - 1 || !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ProjectSettingsAccessoryIconButton(
                                systemImage: "trash",
                                accessibilityLabel: pattern.isEmpty ? "Remove file pattern" : "Remove file pattern \(pattern)",
                                usesDestructiveStyle: true,
                                action: { onRemovePattern(index) }
                            )
                            .help("Remove file pattern")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var defaultsDescription: String {
        let hasCustomPatterns = patterns.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if hasCustomPatterns {
            return "Custom patterns replace the defaults. Clear all patterns to restore .env, .env.local, and .env.development."
        }
        return "Using defaults: .env, .env.local, and .env.development. Add patterns to replace these defaults."
    }
}
