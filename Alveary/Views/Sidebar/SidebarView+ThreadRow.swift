import SwiftData
import SwiftUI

struct SidebarThreadRow: View {
    let thread: AgentThread
    let status: ThreadStatus
    let isSelected: Bool
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

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .offset(x: -3)

            if isEditing {
                TextField("Thread name", text: $editText)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .lineLimit(1)
            } else {
                AppMarkdownInlineLabel(text: displayName)
                    .allowsHitTesting(false)
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
        .accessibilityActions {
            // Gate the VoiceOver "Rename..." rotor action on `editingThreadID == nil`,
            // matching the context-menu button's gate (see `SidebarView.swift`). Without
            // this, VoiceOver users could bypass the guard and hit the SwiftUI unmount/
            // mount race that leaves the target row stuck in editing state without an
            // input field.
            if editingThreadID == nil {
                Button("Rename...") {
                    editingThreadID = thread.persistentModelID
                }
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .busy:
            return .green
        case .unread:
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
