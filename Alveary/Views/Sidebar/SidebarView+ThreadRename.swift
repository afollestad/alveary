import SwiftData
import SwiftUI

struct ThreadRenameDraft: Identifiable {
    let threadID: PersistentIdentifier
    let currentDisplayName: String
    var title: String

    var id: PersistentIdentifier {
        threadID
    }

    init(thread: AgentThread) {
        threadID = thread.persistentModelID
        currentDisplayName = thread.displayName()
        title = thread.displayName()
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        !trimmedTitle.isEmpty
    }

    var persistedName: String? {
        AgentThread.persistedName(from: title)
    }
}

struct ThreadRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: ThreadRenameDraft
    let onSave: (ThreadRenameDraft) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rename Thread")
                        .font(.title2.weight(.semibold))

                    Text("Current label: \(draft.currentDisplayName)")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ModalCloseButton("Close rename thread") {
                    dismiss()
                }
            }

            AppTextField("Thread name", text: $draft.title)
                .onSubmit(save)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .secondaryActionButtonStyle()

                Spacer()

                Button("Save", action: save)
                    .primaryActionButtonStyle()
                    .disabled(!draft.canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}

private extension ThreadRenameSheet {
    func save() {
        guard onSave(draft) else {
            return
        }

        dismiss()
    }
}

enum SidebarThreadActionError: LocalizedError {
    case renameTargetMissing
    case renameFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .renameTargetMissing:
            return "Couldn't rename thread: it no longer exists"
        case .renameFailed(let error):
            return "Couldn't rename thread: \(error.localizedDescription)"
        }
    }
}
