import SwiftData
import SwiftUI
import Textual

struct SidebarThreadRow: View {
    let thread: AgentThread
    let status: ThreadStatus
    @Binding var editingThreadID: PersistentIdentifier?
    let onCommitRename: (String) -> Void

    @State private var editText = ""
    @FocusState private var isFieldFocused: Bool

    private var isEditing: Bool {
        editingThreadID == thread.persistentModelID
    }

    private var displayName: String {
        thread.displayName()
    }

    private var containsMarkdownCode: Bool {
        AppMarkdownCodeBlockParser.containsCode(in: displayName)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .offset(x: -3)

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Thread name", text: $editText)
                        .textFieldStyle(.plain)
                        .focused($isFieldFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                        .lineLimit(1)
                } else {
                    if containsMarkdownCode {
                        InlineText(
                            displayName,
                            parser: AppMarkdownParser(
                                baseURL: nil,
                                inlineCodeStyle: .standard,
                                parsingMode: .inline
                            )
                        )
                        .lineLimit(1)
                    } else {
                        Text(displayName)
                            .lineLimit(1)
                    }
                }

                if let branch = thread.branch {
                    Text(branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .onChange(of: isEditing) { _, editing in
            if editing {
                editText = displayName
                isFieldFocused = true
            }
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused && isEditing {
                commitRename()
            }
        }
        .accessibilityAction(named: Text("Rename")) {
            editingThreadID = thread.persistentModelID
        }
    }

    private var statusColor: Color {
        switch status {
        case .busy:
            return .green
        case .idle:
            return .blue
        case .error:
            return .red
        case .archived:
            return .secondary
        case .stopped:
            return .secondary
        }
    }

    private func commitRename() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onCommitRename(trimmed)
        }
        editingThreadID = nil
    }

    private func cancelRename() {
        editingThreadID = nil
    }
}
