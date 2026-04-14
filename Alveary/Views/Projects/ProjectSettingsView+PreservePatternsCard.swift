import SwiftUI

struct ProjectSettingsPreservePatternsCard: View {
    let patterns: [String]
    let bindingForPattern: (Int) -> Binding<String>
    let onRemovePattern: (Int) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Files matching these patterns are copied into new worktrees when a thread is created.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(patterns.enumerated()), id: \.offset) { index, pattern in
                        HStack(spacing: 10) {
                            AppTextField(
                                "Pattern",
                                text: bindingForPattern(index),
                                textAlignment: .leading,
                                horizontalPadding: 10,
                                verticalPadding: 7
                            )

                            if index < patterns.count - 1 || !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                ProjectSettingsAccessoryIconButton(
                                    systemImage: "trash",
                                    accessibilityLabel: "Remove preserve pattern",
                                    usesDestructiveStyle: true,
                                    action: { onRemovePattern(index) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
        } label: {
            Label("Preserved Files", systemImage: "doc.on.doc")
        }
    }
}
