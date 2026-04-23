import SwiftData
import SwiftUI

struct SidebarThreadRow: View {
    private static let statusIndicatorSize: CGFloat = 8
    private static let trailingStatusPadding = SidebarProjectRow.horizontalPadding
        + statusIndicatorSize / 2

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
            Color.clear
                .frame(width: Self.statusIndicatorSize, height: Self.statusIndicatorSize)

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

            statusIndicator
                .frame(width: Self.statusIndicatorSize, height: Self.statusIndicatorSize)
        }
        .padding(.vertical, 6)
        .padding(.trailing, Self.trailingStatusPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private var statusIndicator: some View {
        if status == .busy {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.5)
                .tint(.blue)
        } else {
            Circle()
                .fill(statusColor)
        }
    }

    private var statusColor: Color {
        switch status {
        case .busy:
            return .blue
        case .unread:
            return .green
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
